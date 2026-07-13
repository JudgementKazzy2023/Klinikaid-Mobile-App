import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/repositories/patients_repository.dart';
import '../../../../core/repositories/profiles_repository.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/verification_state.dart';
import '../../data/verification_service.dart';
import '../../data/session_activity_service.dart';
import '../../domain/password_reset_result.dart';
import '../../domain/password_change_result.dart';
import '../../data/mfa_service.dart';
import '../../domain/login_outcome.dart';

/// Provider that manages authentication state, RA 10173 consent, and patient onboarding flow.
class AuthProvider extends ChangeNotifier {
  final SupabaseClient _client;
  final PatientsRepository _patientsRepo;
  final ProfilesRepository _profilesRepo;
  final VerificationService _verificationService;
  final SessionActivityService _activityService;
  final MfaService _mfaService;

  User? _user;
  Session? _session;
  Profile? _profile;
  Patient? _patient;
  bool _hasConsented = false;
  bool _isOnboarded = false;
  bool _isLoading = true;
  String? _errorMessage;
  VerificationState _verificationState = VerificationState();
  bool _wasLoggedOutForInactivity = false;
  bool _isFirstAuthCheck = true;
  String? _pendingMfaFactorId;
  bool _needsMfaEnrollment = false;

  Profile? get profile => _profile;
  Patient? get patient => _patient;
  VerificationState get verificationState => _verificationState;
  bool get wasLoggedOutForInactivity => _wasLoggedOutForInactivity;
  String? get pendingMfaFactorId => _pendingMfaFactorId;
  bool get needsMfaEnrollment => _needsMfaEnrollment;
  bool get isAal1Pending => _pendingMfaFactorId != null || _needsMfaEnrollment;

  bool get isAal2 {
    try {
      final aal = _client.auth.mfa.getAuthenticatorAssuranceLevel();
      return aal.currentLevel == AuthenticatorAssuranceLevels.aal2;
    } catch (_) {
      return false;
    }
  }

  StreamSubscription<AuthState>? _authStateSubscription;

  AuthProvider({
    SupabaseClient? client,
    PatientsRepository? patientsRepo,
    ProfilesRepository? profilesRepo,
    VerificationService? verificationService,
    SessionActivityService? activityService,
    MfaService? mfaService,
  })  : _client = client ?? Supabase.instance.client,
        _patientsRepo = patientsRepo ?? PatientsRepository(),
        _profilesRepo = profilesRepo ?? ProfilesRepository(),
        _verificationService = verificationService ?? SupabaseVerificationService(),
        _activityService = activityService ?? SessionActivityService(),
        _mfaService = mfaService ?? MfaService(client ?? Supabase.instance.client),
        super() {
    _init();
  }

  User? get user => _user;
  Session? get session => _session;
  bool get isAuthenticated => _session != null;
  bool get hasConsented => _hasConsented;
  bool get isOnboarded => _isOnboarded;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Initializes the provider by checking current session and subscribing to auth changes.
  void _init() {
    _session = _client.auth.currentSession;
    _user = _session?.user;
    
    _updateLocalStates().then((_) {
      _isLoading = false;
      notifyListeners();
    });

    _authStateSubscription = _client.auth.onAuthStateChange.listen((data) async {
      _session = data.session;
      _user = data.session?.user;
      
      _isLoading = true;
      notifyListeners();

      await _updateLocalStates();
      
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Evaluates consent and onboarding status based on active user state.
  bool _isDisposed = false;
  Future<void>? _currentUpdateFuture;

  Future<void> _updateLocalStates() async {
    if (_isDisposed) return;

    // Mutex lock to ensure sequential execution of state updates
    while (_currentUpdateFuture != null) {
      await _currentUpdateFuture;
    }
    final completer = Completer<void>();
    _currentUpdateFuture = completer.future;

    try {
      final currentUser = _user;
      if (currentUser == null) {
       _hasConsented = false;
       _isOnboarded = false;
       _profile = null;
       return;
     }

    // 1. Fetch profile from database
    try {
      _profile = await _profilesRepo.getProfile(currentUser.id);
    } catch (_) {
      _profile = null;
    }

    if (_profile?.isActive == false) {
      _errorMessage = 'This account has been deactivated. Contact an administrator.';
      _user = null;
      _session = null;
      _profile = null;
      _patient = null;
      _hasConsented = false;
      _isOnboarded = false;
      _client.auth.signOut().catchError((_) {});
      return;
    }

    // If admin or staff role, bypass consent and onboarding gates
    if (_profile?.role == UserRole.admin ||
        _profile?.role == UserRole.receptionist ||
        _profile?.role == UserRole.departmentStaff ||
        _profile?.role == UserRole.medicalSpecialist) {
      _hasConsented = true;
      _isOnboarded = true;
      _patient = null;

      if (_profile?.role == UserRole.admin && !isAal2) {
        // IMPORTANT: If we already have a pending factor from enrollment/login,
        // do NOT call listVerifiedFactors — the newly-enrolled factor is still
        // unverified and will not appear, and overwriting _pendingMfaFactorId
        // mid-verify would kill the challenge→verify sequence.
        if (_pendingMfaFactorId != null) {
          print('[AuthProvider _updateLocalStates] Admin has pendingMfaFactorId=$_pendingMfaFactorId — skipping listVerifiedFactors to preserve mid-verify state.');
          _needsMfaEnrollment = false;
        } else {
          try {
            print('[AuthProvider _updateLocalStates] Admin AAL1, no pending factor — calling listVerifiedFactors.');
            final factors = await _mfaService.listVerifiedFactors();
            print('[AuthProvider _updateLocalStates] listVerifiedFactors returned ${factors.length} factor(s).');
            if (factors.isNotEmpty) {
              _pendingMfaFactorId = factors.first.id;
              _needsMfaEnrollment = false;
              print('[AuthProvider _updateLocalStates] Set pendingMfaFactorId=${factors.first.id} from verified factor.');
            } else {
              _needsMfaEnrollment = true;
              print('[AuthProvider _updateLocalStates] No verified factors — needs enrollment.');
            }
          } catch (e) {
            print('[AuthProvider _updateLocalStates] listVerifiedFactors error: $e — defaulting to needs enrollment.');
            _needsMfaEnrollment = true;
          }
        }
      } else if (_profile?.role != UserRole.admin) {
        _needsMfaEnrollment = false;
      }
    } else {
      _needsMfaEnrollment = false;
      // 2. Evaluate Privacy Consent (read exclusively from database profiles.accepted_privacy_at)
      _hasConsented = _profile?.acceptedPrivacyAt != null;

      // 3. Evaluate Onboarding Status (linked patients row)
      try {
        _patient = await _patientsRepo.getPatientByProfileId(currentUser.id);
        _isOnboarded = _patient != null;
      } catch (_) {
        _patient = null;
        _isOnboarded = false;
      }
    }

    // Session activity check on resume / startup / login:
    if (isAuthenticated) {
      if (_isFirstAuthCheck) {
        _isFirstAuthCheck = false;
        await _activityService.restoreLastActivity();
        final role = _profile?.role;
        final timeout = (role == UserRole.patient)
            ? const Duration(minutes: 20)
            : const Duration(minutes: 10);
        if (!_activityService.isExempt && _activityService.idleTime > timeout) {
          _wasLoggedOutForInactivity = true;
          await _client.auth.signOut();
          _user = null;
          _session = null;
          _profile = null;
          _patient = null;
          _hasConsented = false;
          _isOnboarded = false;
          _activityService.stopMonitoring();
          return;
        }
      }
      _startInactivityMonitor();
    } else {
      _isFirstAuthCheck = false;
    }
    } finally {
      completer.complete();
      if (_currentUpdateFuture == completer.future) {
        _currentUpdateFuture = null;
      }
    }
  }

  void _startInactivityMonitor() {
    if (_isDisposed) return;
    final role = _profile?.role;
    if (role == null) return;

    final timeout = (role == UserRole.patient)
        ? const Duration(minutes: 20)
        : const Duration(minutes: 10);

    _activityService.recordActivity();
    _activityService.startMonitoring(
      timeout: timeout,
      onTimeout: handleInactivityLogout,
    );
  }

  Future<void> handleInactivityLogout() async {
    _wasLoggedOutForInactivity = true;
    await signOut();
  }

  void clearInactivityFlag() {
    _wasLoggedOutForInactivity = false;
    notifyListeners();
  }


  /// Clear active error messages.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Triggers server-side secure password reset Edge Function request-password-reset.
  Future<PasswordResetResult> sendPasswordReset(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _client.functions.invoke(
        'request-password-reset',
        body: {'email': email},
      );
      
      _isLoading = false;
      notifyListeners();
      return PasswordResetResult.success;
    } catch (e) {
      // Even on exception/error, return success to maintain uniform outcome
      // and prevent account enumeration via timing or client-side error states
      _isLoading = false;
      notifyListeners();
      return PasswordResetResult.success;
    }
  }

  /// Signs in a user using email and password.
  Future<LoginOutcome> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client.auth.signInWithPassword(email: email, password: password);
      _session = response.session;
      _user = response.user;
      await _updateLocalStates();

      if (_errorMessage == 'This account has been deactivated. Contact an administrator.') {
        _isLoading = false;
        notifyListeners();
        return LoginOutcome.invalidCredentials;
      }

      // Check if step-up required
      if (_mfaService.requiresStepUp()) {
        final factors = await _mfaService.listVerifiedFactors();
        if (factors.isNotEmpty) {
          _pendingMfaFactorId = factors.first.id;
          _isLoading = false;
          notifyListeners();
          return LoginOutcome.mfaRequired;
        }
      }

      _isLoading = false;
      notifyListeners();
      return LoginOutcome.success;
    } catch (e) {
      _errorMessage = e is AuthException ? e.message : e.toString();
      _isLoading = false;
      notifyListeners();
      return LoginOutcome.invalidCredentials;
    }
  }

  /// Starts MFA Enrollment for admin
  Future<dynamic> startMfaEnrollment() async {
    _isLoading = true;
    notifyListeners();
    try {
      print('[AuthProvider startMfaEnrollment] (${identityHashCode(this)}) Enrolling TOTP factor...');
      final response = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'KlinikAid',
      );
      _pendingMfaFactorId = response.id;
      _needsMfaEnrollment = false; // Factor enrolled, now verify it
      print('[AuthProvider startMfaEnrollment] (${identityHashCode(this)}) Success: factorId = ${response.id}');
      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      print('[AuthProvider startMfaEnrollment] (${identityHashCode(this)}) Error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Verify TOTP code → upgrades session to AAL2
  Future<MfaVerifyResult> verifyMfa(String code) async {
    print('[AuthProvider verifyMfa] Called. _pendingMfaFactorId=$_pendingMfaFactorId, code length=${code.length}');
    if (_pendingMfaFactorId == null) {
      print('[AuthProvider verifyMfa] ABORT: _pendingMfaFactorId is null — cannot verify.');
      return MfaVerifyResult.error;
    }

    _isLoading = true;
    notifyListeners();

    try {
      print('[AuthProvider verifyMfa] Calling verifyTotp: factorId=$_pendingMfaFactorId code=$code');
      final result = await _mfaService.verifyTotp(
        factorId: _pendingMfaFactorId!,
        code: code,
      );
      print('[AuthProvider verifyMfa] verifyTotp outcome: $result');

      if (result == MfaVerifyResult.success) {
        _pendingMfaFactorId = null;
        _needsMfaEnrollment = false;
        print('[AuthProvider verifyMfa] Success. Refreshing session...');
        try {
          await _client.auth.refreshSession();
          print('[AuthProvider verifyMfa] Session refreshed. isAal2=${isAal2}');
        } catch (e) {
          print('[AuthProvider verifyMfa] refreshSession error (non-fatal): $e');
        }
        await _updateLocalStates();
      }

      return result;
    } catch (e, stack) {
      print('[AuthProvider verifyMfa] UNEXPECTED EXCEPTION: $e');
      print('[AuthProvider verifyMfa] Stack: $stack');
      return MfaVerifyResult.error;
    } finally {
      // ALWAYS clear loading — this was missing and caused the spinner to lock
      _isLoading = false;
      notifyListeners();
      print('[AuthProvider verifyMfa] finally: _isLoading cleared.');
    }
  }

  /// Cancels registration/MFA flow, signs out, and resets state.
  Future<void> cancelMfaFlow() async {
    _pendingMfaFactorId = null;
    _needsMfaEnrollment = false;
    await signOut();
  }

  /// Registers a new user with patient demographic metadata and inserts patient details.
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String address,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fullName = '$firstName $lastName'.trim();
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': 'patient',
        },
      );
      _session = response.session;
      _user = response.user;

      if (_user != null) {
        // Create the Patient record in the public table
        final patient = Patient(
          id: _user!.id,
          profileId: _user!.id,
          firstName: firstName,
          lastName: lastName,
          dateOfBirth: dateOfBirth,
          gender: gender,
          contactNumber: contactNumber,
          email: email,
          address: address,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _patientsRepo.createPatient(patient);
        _patient = patient;
        _isOnboarded = true;

        // Record the privacy policy consent immediately
        final profile = await _profilesRepo.getProfile(_user!.id);
        final updatedProfile = Profile(
          id: profile.id,
          fullName: fullName,
          role: profile.role,
          department: profile.department,
          isActive: profile.isActive,
          acceptedPrivacyAt: DateTime.now(),
          emailVerifiedAt: profile.emailVerifiedAt,
          createdAt: profile.createdAt,
          updatedAt: DateTime.now(),
        );
        _profile = await _profilesRepo.updateProfile(updatedProfile);
        _hasConsented = true;

        // Automatically send verification code upon successful signup
        final sent = await sendVerificationCode(email);
        if (!sent) {
          // If sending fails, clean up local session
          await _client.auth.signOut().catchError((_) {});
          _user = null;
          _session = null;
          _profile = null;
          _patient = null;
          _hasConsented = false;
          _isOnboarded = false;
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e is AuthException ? e.message : e.toString();
      // Safe cleanup of local states on failure (orphan strategy: accept orphan but clean session)
      await _client.auth.signOut().catchError((_) {});
      _user = null;
      _session = null;
      _profile = null;
      _patient = null;
      _hasConsented = false;
      _isOnboarded = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Updates database profile to record RA 10173 consent acceptance.
  Future<bool> acceptConsent() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Update profiles table (write directly to public.profiles.accepted_privacy_at)
      final currentUser = _user;
      if (currentUser != null) {
        final profile = _profile ?? await _profilesRepo.getProfile(currentUser.id);
        final updatedProfile = Profile(
          id: profile.id,
          fullName: profile.fullName,
          role: profile.role,
          department: profile.department,
          isActive: profile.isActive,
          acceptedPrivacyAt: DateTime.now(),
          emailVerifiedAt: profile.emailVerifiedAt,
          createdAt: profile.createdAt,
          updatedAt: DateTime.now(),
        );
        _profile = await _profilesRepo.updateProfile(updatedProfile);
      }

      _hasConsented = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e is AuthException ? e.message : e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Inserts a patient onboarding record.
  Future<bool> submitOnboarding({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String address,
  }) async {
    final currentUser = _user;
    if (currentUser == null) {
      _errorMessage = 'No authenticated user session found.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final patient = Patient(
        id: currentUser.id, // Primary key references profiles.id or generated
        profileId: currentUser.id,
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        contactNumber: contactNumber,
        email: currentUser.email,
        address: address,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _patientsRepo.createPatient(patient);
      _patient = patient;
      _isOnboarded = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on Failure catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Updates the patient record details.
  Future<bool> updatePatientDetails({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String address,
  }) async {
    final currentPatient = _patient;
    if (currentPatient == null) {
      _errorMessage = 'No active patient profile found.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = Patient(
        id: currentPatient.id,
        profileId: currentPatient.profileId,
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        contactNumber: contactNumber,
        email: currentPatient.email,
        address: address,
        createdAt: currentPatient.createdAt,
        updatedAt: DateTime.now(),
      );

      final result = await _patientsRepo.updatePatient(updated);
      _patient = result;
      _isLoading = false;
      notifyListeners();
      return true;
    } on Failure catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Signs out of the active session.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      _activityService.stopMonitoring();
      await _client.auth.signOut();
    } finally {
      _user = null;
      _session = null;
      _profile = null;
      _patient = null;
      _hasConsented = false;
      _isOnboarded = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Triggers Edge Function to send email verification code.
  Future<bool> sendVerificationCode(String email) async {
    _verificationState = _verificationState.copyWith(status: VerificationStatus.verifying);
    notifyListeners();

    final result = await _verificationService.sendCode(email: email);
    if (result.status == VerificationStatus.codeSent) {
      _verificationState = VerificationState(
        status: VerificationStatus.codeSent,
        cooldownUntil: DateTime.now().add(const Duration(seconds: 60)),
      );
      _errorMessage = null;
      notifyListeners();
      return true;
    } else {
      _verificationState = VerificationState(
        status: result.status,
        errorMessage: result.errorMessage,
      );
      _errorMessage = result.errorMessage;
      notifyListeners();
      return false;
    }
  }

  /// Triggers Edge Function to verify code and updates local profile state upon success.
  Future<bool> verifyCode(String code) async {
    final email = _user?.email;
    if (email == null) {
      _errorMessage = 'No active session email found.';
      notifyListeners();
      return false;
    }

    _verificationState = _verificationState.copyWith(status: VerificationStatus.verifying);
    notifyListeners();

    final result = await _verificationService.verifyCode(email: email, code: code);
    if (result.status == VerificationStatus.verified) {
      _verificationState = VerificationState(status: VerificationStatus.verified);
      _errorMessage = null;
      await _updateLocalStates();
      notifyListeners();
      return true;
    } else {
      _verificationState = VerificationState(
        status: result.status,
        attemptsRemaining: result.attemptsRemaining,
        errorMessage: result.errorMessage,
      );
      _errorMessage = result.errorMessage;
      notifyListeners();
      return false;
    }
  }

  /// Requests the server to verify the new email's OTP and perform the email change.
  Future<bool> changeEmailAddress({
    required String newEmail,
    required String code,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client.functions.invoke(
        'update-user-email',
        method: HttpMethod.post,
        body: {
          'newEmail': newEmail,
          'code': code,
        },
      );

      final data = response.data;
      final Map<String, dynamic> json = data is Map<String, dynamic> ? data : {};

      if (response.status == 200) {
        // Force refresh session to get updated user token with new email
        await _client.auth.refreshSession().catchError((_) {});
        await _updateLocalStates();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        final message = json['message'] as String? ?? 'Failed to update email address';
        _errorMessage = message;
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on FunctionException catch (fe) {
      final details = fe.details;
      final Map<String, dynamic> json = details is Map<String, dynamic> ? details : {};
      _errorMessage = json['message'] as String? ?? fe.reasonPhrase ?? 'Failed to update email address';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Cancels registration, deletes pending unverified user, signs out, and resets state.
  Future<bool> restartVerification() async {
    _isLoading = true;
    notifyListeners();

    final deleted = await _verificationService.deletePendingUser();
    if (!deleted) {
      _errorMessage = 'Failed to cancel registration. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    await signOut();
    _verificationState = VerificationState(status: VerificationStatus.idle);
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Changes the authenticated user's password after reauthentication.
  ///
  /// Reauthentication: calls [signInWithPassword] with [currentPassword] to
  /// verify the current credential before allowing the update. If reauth
  /// fails, the update is never attempted and [wrongCurrentPassword] is
  /// returned. This applies to all staff roles (receptionist, department
  /// staff, specialist) — no role gate is applied.
  Future<PasswordChangeResult> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    _errorMessage = null;
    notifyListeners();
    try {
      final email = _client.auth.currentUser?.email;
      if (email == null) {
        _errorMessage = 'No active user session found.';
        notifyListeners();
        return PasswordChangeResult.notAuthenticated;
      }

      final factors = await _client.auth.mfa.listFactors();
      final hasMfa = factors.totp.any((f) => f.status == FactorStatus.verified);

      if (hasMfa) {
        // Already AAL2 from TOTP at login. Do NOT signInWithPassword —
        // it downgrades to AAL1 and Supabase rejects the update.
        await _client.auth.updateUser(UserAttributes(password: newPassword));
      } else {
        // No MFA → verify current password via reauth, then update
        if (currentPassword == null || currentPassword.isEmpty) {
          _errorMessage = 'Current password is required.';
          notifyListeners();
          return PasswordChangeResult.wrongCurrentPassword;
        }
        try {
          await _client.auth.signInWithPassword(
            email: email,
            password: currentPassword,
          );
        } on AuthException catch (e) {
          _errorMessage = e.message;
          notifyListeners();
          return PasswordChangeResult.wrongCurrentPassword;
        }
        await _client.auth.updateUser(UserAttributes(password: newPassword));
      }
      return PasswordChangeResult.success;
    } catch (e, stack) {
      debugPrint('ChangePassword error: $e');
      debugPrint('Stacktrace: $stack');
      _errorMessage = e is AuthException ? e.message : e.toString();
      notifyListeners();
      return PasswordChangeResult.error;
    }
  }

  /// Retrieves all TOTP MFA factors registered to the current authenticated user.
  Future<List<Factor>> listMfaFactors() async {
    final factors = await _client.auth.mfa.listFactors();
    return factors.totp;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _authStateSubscription?.cancel();
    _activityService.stopMonitoring();
    super.dispose();
  }

  @visibleForTesting
  void setMockState({
    Session? session,
    User? user,
    Profile? profile,
    bool? needsMfaEnrollment,
    String? pendingMfaFactorId,
    bool? isLoading,
  }) {
    _session = session;
    _user = user;
    _profile = profile;
    if (needsMfaEnrollment != null) _needsMfaEnrollment = needsMfaEnrollment;
    if (pendingMfaFactorId != null) _pendingMfaFactorId = pendingMfaFactorId;
    if (isLoading != null) _isLoading = isLoading;
    notifyListeners();
  }
}
