import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/cache/local_database.dart';
import '../../../../core/repositories/patients_repository.dart';
import '../../../../core/repositories/profiles_repository.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/permissions/permission_service.dart';
import '../../../../core/permissions/permission_source.dart';
import '../../domain/verification_state.dart';
import '../../domain/patient_record_state.dart';
import '../../data/verification_service.dart';
import '../../data/patient_provisioning_service.dart';
import '../../data/password_reset_service.dart';
import '../../data/session_activity_service.dart';
import '../../domain/password_reset_result.dart';
import '../../domain/password_change_result.dart';
import '../../domain/signup_outcome.dart';
import '../../data/mfa_service.dart';
import '../../domain/login_outcome.dart';
import '../../domain/temporary_password.dart' as temporary_password;

/// Provider that manages authentication state, RA 10173 consent, and patient onboarding flow.
class AuthProvider extends ChangeNotifier implements PermissionSource {
  final SupabaseClient _client;
  final PatientsRepository _patientsRepo;
  final ProfilesRepository _profilesRepo;
  final VerificationService _verificationService;
  final PatientProvisioningService _patientProvisioningService;
  final PasswordResetService _passwordResetService;
  final PermissionService _permissionService;
  final SessionActivityService _activityService;
  final MfaService _mfaService;
  final LocalDatabase? localDatabase;

  User? _activeUser;
  int _identityEpoch = 0;

  /// Bumped synchronously by every [signOut] call so in-flight sign-ins can
  /// detect that a newer sign-out intent superseded them, even before any
  /// identity change is visible.
  int _signOutGeneration = 0;
  User? get _user => _activeUser;
  set _user(User? value) {
    // Only a real identity change resets state. The signed-out event that
    // follows a local sign-out must not wipe the message that explains it.
    if (value?.id != _activeUser?.id) {
      _identityEpoch++;
      _pendingMfaFactorId = null;
      _needsMfaEnrollment = false;
      _verificationState = VerificationState();
      _errorMessage = null;
      _hasConsented = false;
      _isOnboarded = false;
      _profile = null;
      _patient = null;
      _patientRecordState = PatientRecordState.unknown;
      _patientRecordError = null;
      _permissions = const <String>{};
      _permissionLoadState = PermissionLoadState.idle;
      _permissionLoadError = null;
    }
    _activeUser = value;
  }
  Session? _session;
  Profile? _profile;
  Patient? _patient;
  PatientRecordState _patientRecordState = PatientRecordState.unknown;
  String? _patientRecordError;
  bool _hasConsented = false;
  bool _isOnboarded = false;
  bool _isLoading = true;
  String? _errorMessage;
  VerificationState _verificationState = VerificationState();
  bool _wasLoggedOutForInactivity = false;
  bool _isFirstAuthCheck = true;
  String? _pendingMfaFactorId;
  bool _needsMfaEnrollment = false;
  Set<String> _permissions = const <String>{};

  /// How the last permission load ended.
  ///
  /// A failed load is kept apart from a load that returned no grants: the
  /// first leaves the grants unknown and offers a retry, the second is an
  /// answer that denies every screen.
  PermissionLoadState _permissionLoadState = PermissionLoadState.idle;

  /// Why the last permission load failed, when it failed.
  String? _permissionLoadError;

  Profile? get profile => _profile;
  Patient? get patient => _patient;

  /// Outcome of the patient record lookup for the active account.
  PatientRecordState get patientRecordState => _patientRecordState;

  /// Reason the patient record lookup failed, when [patientRecordState] is
  /// [PatientRecordState.failed].
  String? get patientRecordError => _patientRecordError;

  VerificationState get verificationState => _verificationState;
  bool get wasLoggedOutForInactivity => _wasLoggedOutForInactivity;
  String? get pendingMfaFactorId => _pendingMfaFactorId;
  bool get needsMfaEnrollment => _needsMfaEnrollment;
  bool get isAal1Pending => _pendingMfaFactorId != null || _needsMfaEnrollment;
  Set<String> get permissions => _permissions;

  /// How the last permission load ended.
  PermissionLoadState get permissionLoadState => _permissionLoadState;

  /// Why the last permission load failed, when it failed.
  String? get permissionLoadError => _permissionLoadError;

  /// Whether the account is known to hold no permission at all.
  ///
  /// This is a successful load that returned no grants, not a failed load: the
  /// server answered, and the answer was "nothing". A failed load leaves
  /// [permissionLoadState] as [PermissionLoadState.failed] and the grants
  /// unknown, so it is never read as an empty grant set.
  bool get hasNoPermissions =>
      _permissionLoadState == PermissionLoadState.loaded &&
      _permissions.isEmpty;

  /// Whether the grants could not be read.
  bool get permissionLoadFailed =>
      _permissionLoadState == PermissionLoadState.failed;

  @override
  bool hasPermission(String permission) => _permissions.contains(permission);

  @override
  bool hasAllPermissions(List<String> permissions) =>
      permissions.every(_permissions.contains);

  @override
  bool hasAnyPermission(List<String> permissions) =>
      permissions.any(_permissions.contains);

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
    PatientProvisioningService? patientProvisioningService,
    PasswordResetService? passwordResetService,
    PermissionService? permissionService,
    SessionActivityService? activityService,
    MfaService? mfaService,
    this.localDatabase,
  })  : _client = client ?? Supabase.instance.client,
        _patientsRepo = patientsRepo ?? PatientsRepository(),
        _profilesRepo = profilesRepo ?? ProfilesRepository(),
        _verificationService = verificationService ?? SupabaseVerificationService(),
        _patientProvisioningService =
            patientProvisioningService ?? SupabasePatientProvisioningService(),
        _passwordResetService = passwordResetService ??
            SupabasePasswordResetService.forClient(client ?? Supabase.instance.client),
        _permissionService = permissionService ??
            SupabasePermissionService(client: client ?? Supabase.instance.client),
        _activityService = activityService ?? SessionActivityService(),
        _mfaService = mfaService ?? MfaService(client ?? Supabase.instance.client),
        super() {
    _init();
  }

  User? get user => _user;
  Session? get session => _session;
  bool get isAuthenticated => _session != null;

  /// The account still holds the temporary password reception set.
  bool get mustChangePassword => temporary_password.mustChangePassword(_user);
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
      // Ignore an obsolete signed-out event if the client already has a new
      // session. Expiry and SDK-initiated sign-outs also need cache cleanup.
      if (data.event == AuthChangeEvent.signedOut &&
          _client.auth.currentSession != null) {
        return;
      }
      _session = data.session;
      _user = data.session?.user;
      final epoch = _identityEpoch;
      
      _isLoading = true;
      notifyListeners();

      if (data.event == AuthChangeEvent.signedOut && epoch == _identityEpoch) {
        await _clearLocalCache();
      }
      if (epoch != _identityEpoch || _isDisposed) return;
      await _updateLocalStates();
      if (epoch != _identityEpoch || _isDisposed) return;
      
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
      final epoch = _identityEpoch;
      if (currentUser == null) {
       // No session was restored, so there is no idle time to judge: a later
       // sign-in or sign-up is fresh, not a resumed session.
       _isFirstAuthCheck = false;
       _hasConsented = false;
       _isOnboarded = false;
       _profile = null;
       _patient = null;
       _patientRecordState = PatientRecordState.unknown;
       _patientRecordError = null;
       _permissions = const <String>{};
       _permissionLoadState = PermissionLoadState.idle;
       _permissionLoadError = null;
       return;
     }

    // 1. Fetch profile from database
    try {
      final profile = await _profilesRepo.getProfile(currentUser.id);
      if (epoch != _identityEpoch) return;
      _profile = profile;
    } catch (_) {
      _profile = null;
    }

    if (epoch != _identityEpoch) return;
    await _loadPermissionsForProfile(epoch);
    if (epoch != _identityEpoch) return;

    if (_profile?.isActive == false) {
      _errorMessage = 'This account has been deactivated. Contact an administrator.';
      _user = null;
      _session = null;
      _profile = null;
      _patient = null;
      _patientRecordState = PatientRecordState.unknown;
      _patientRecordError = null;
      _permissions = const <String>{};
      _permissionLoadState = PermissionLoadState.idle;
      _permissionLoadError = null;
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
      // Staff accounts have no patient record to look up.
      _patientRecordState = PatientRecordState.unknown;
      _patientRecordError = null;

      if (_profile?.role != UserRole.patient && !isAal2) {
        // IMPORTANT: If we already have a pending factor from enrollment/login,
        // do NOT call listVerifiedFactors — the newly-enrolled factor is still
        // unverified and will not appear, and overwriting _pendingMfaFactorId
        // mid-verify would kill the challenge→verify sequence.
        if (_pendingMfaFactorId != null) {
          _needsMfaEnrollment = false;
        } else {
          try {
            final factors = await _mfaService.listVerifiedFactors();
            if (epoch != _identityEpoch) return;
            if (factors.isNotEmpty) {
              _pendingMfaFactorId = factors.first.id;
              _needsMfaEnrollment = false;
            } else {
              _needsMfaEnrollment = true;
            }
          } catch (e) {
            debugPrint('[AuthProvider _updateLocalStates] listVerifiedFactors error: $e — defaulting to needs enrollment.');
            if (epoch != _identityEpoch) return;
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
      //
      // A failed read and a missing row are recorded separately: the first is
      // retryable, the second is not. Collapsing them into a null patient made
      // every consumer spin forever with no way out.
      await _loadPatientRecord(currentUser.id);
      // The identity may have changed while the lookup was in flight; the
      // newer identity owns the state from here on.
      if (epoch != _identityEpoch) return;
    }

    // Session activity check on resume / startup / login:
    if (isAuthenticated) {
      if (_isFirstAuthCheck) {
        _isFirstAuthCheck = false;
        final activityEpoch = _identityEpoch;
        await _activityService.restoreLastActivity();
        // A sign-out or account switch that completed while the restore was
        // in flight owns the current state; do not run the idle-logout
        // decision against the newer identity with this run's stale context.
        if (activityEpoch == _identityEpoch) {
          final role = _profile?.role;
          final timeout = (role == UserRole.patient)
              ? const Duration(minutes: 20)
              : const Duration(minutes: 10);
          if (!_activityService.isExempt && _activityService.idleTime > timeout) {
            _wasLoggedOutForInactivity = true;
            await signOut();
            return;
          }
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

  /// Whether [profileId] still identifies the account this provider is
  /// signed in as.
  ///
  /// A patient lookup can finish after the account was signed out or replaced
  /// by another one. Its outcome belongs to the session that started it and
  /// must never be written into a different session.
  bool _isActiveAccount(String profileId) {
    if (_isDisposed) return false;
    return _user?.id == profileId;
  }

  /// Loads the patient record linked to [profileId] and records the outcome.
  ///
  /// The failure is kept, not swallowed: a failed read and a missing row are
  /// different states, and the consumer has to be able to tell them apart.
  ///
  /// The outcome is only applied while [profileId] is still the active
  /// account; a result that arrives after a sign-out or an account switch is
  /// discarded instead of leaking into the new session.
  Future<void> _loadPatientRecord(String profileId) async {
    try {
      final patient = await _patientsRepo.getPatientByProfileId(profileId);
      if (!_isActiveAccount(profileId)) return;
      _patient = patient;
      _isOnboarded = patient != null;
      _patientRecordState = patient != null
          ? PatientRecordState.loaded
          : PatientRecordState.missing;
      _patientRecordError = null;
    } on Failure catch (e) {
      if (!_isActiveAccount(profileId)) return;
      _patient = null;
      _isOnboarded = false;
      _patientRecordState = PatientRecordState.failed;
      _patientRecordError = e.message;
    } catch (e) {
      if (!_isActiveAccount(profileId)) return;
      _patient = null;
      _isOnboarded = false;
      _patientRecordState = PatientRecordState.failed;
      _patientRecordError = e.toString();
    }
  }

  /// Re-runs the patient record lookup for the active session.
  ///
  /// Used by the surfaces that show a retryable error when the read failed.
  /// Leaves [patientRecordState] as [PatientRecordState.failed] when the read
  /// fails again, and as [PatientRecordState.loaded] or
  /// [PatientRecordState.missing] when it succeeds.
  Future<void> retryPatientLookup() async {
    if (_isDisposed) return;
    final currentUser = _user;
    if (currentUser == null) return;

    _patientRecordState = PatientRecordState.loading;
    _patientRecordError = null;
    notifyListeners();

    await _loadPatientRecord(currentUser.id);
    if (_isDisposed) return;
    notifyListeners();
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

  /// Asks the server to send a password reset link for [email].
  ///
  /// The deployed `request-password-reset` function always answers HTTP 200
  /// `{success:true}`, whether or not [email] has an account, and it adds a
  /// fixed delay. So a non-2xx status seen here comes from the gateway or the
  /// transport, never from the account. Only the gateway's 429 (too many
  /// requests) and failures to get any answer or a 5xx are reported as
  /// failures. Other 4xx statuses are reported as [PasswordResetResult.success].
  /// Reporting a failed request as success would tell the user to check an
  /// inbox for a link that was never sent.
  Future<PasswordResetResult> sendPasswordReset(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _requestResetOutcome(email);

    _isLoading = false;
    notifyListeners();
    return result;
  }

  Future<PasswordResetResult> _requestResetOutcome(String email) async {
    try {
      await _passwordResetService.requestReset(email);
      return PasswordResetResult.success;
    } on FunctionException catch (e) {
      if (e.status == 429) return PasswordResetResult.rateLimited;
      return e.status >= 500
          ? PasswordResetResult.retryableFailure
          : PasswordResetResult.success;
    } catch (e) {
      debugPrint('[AuthProvider sendPasswordReset] no answer from the server: $e');
      return PasswordResetResult.retryableFailure;
    }
  }

  /// Signs in a user using email and password.
  Future<LoginOutcome> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    final signOutGeneration = _signOutGeneration;
    var loginEpoch = _identityEpoch;

    try {
      final response = await _client.auth.signInWithPassword(email: email, password: password);
      if (signOutGeneration != _signOutGeneration || loginEpoch != _identityEpoch) {
        // A sign-out was requested while this login was in flight; the newer
        // intent wins — never install this identity or report success.
        return LoginOutcome.invalidCredentials;
      }
      _session = response.session;
      _user = response.user;
      // Capture the epoch at the moment this identity becomes active, before
      // any further awaits: a sign-out or account switch during the profile
      // load or MFA factor listing below must not be mistaken for a
      // still-valid login.
      final epoch = _identityEpoch;
      loginEpoch = epoch;
      await _updateLocalStates();

      if (epoch != _identityEpoch) {
        // Identity changed while signing in — never report success or arm a
        // pending MFA factor for a session that is no longer active.
        return LoginOutcome.invalidCredentials;
      }

      if (_errorMessage == 'This account has been deactivated. Contact an administrator.') {
        _isLoading = false;
        notifyListeners();
        return LoginOutcome.invalidCredentials;
      }

      // Check if step-up required
      if (_mfaService.requiresStepUp()) {
        final factors = await _mfaService.listVerifiedFactors();
        if (epoch != _identityEpoch) return LoginOutcome.invalidCredentials;
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
      if (loginEpoch == _identityEpoch && signOutGeneration == _signOutGeneration) {
        _errorMessage = e is AuthException ? e.message : e.toString();
        _isLoading = false;
        notifyListeners();
      }
      return LoginOutcome.invalidCredentials;
    }
  }

  /// Starts MFA Enrollment for admin
  Future<dynamic> startMfaEnrollment() async {
    final epoch = _identityEpoch;
    if (_user == null) throw StateError('No active session');
    _isLoading = true;
    notifyListeners();
    try {
      final response = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'KlinikAid',
      );
      if (epoch != _identityEpoch) throw StateError('Session changed');
      _pendingMfaFactorId = response.id;
      _needsMfaEnrollment = false; // Factor enrolled, now verify it
      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      debugPrint('[AuthProvider startMfaEnrollment] (${identityHashCode(this)}) Error: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Verify TOTP code → upgrades session to AAL2
  Future<MfaVerifyResult> verifyMfa(String code) async {
    final epoch = _identityEpoch;
    if (_pendingMfaFactorId == null) {
      return MfaVerifyResult.error;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final result = await _mfaService.verifyTotp(
        factorId: _pendingMfaFactorId!,
        code: code,
      );

      if (epoch != _identityEpoch) return MfaVerifyResult.error;
      if (result == MfaVerifyResult.success) {
        _pendingMfaFactorId = null;
        _needsMfaEnrollment = false;
        try {
          await _client.auth.refreshSession();
        } catch (e) {
          debugPrint('[AuthProvider verifyMfa] refreshSession error (non-fatal): $e');
        }
        await _updateLocalStates();
      }

      return result;
    } catch (e, stack) {
      debugPrint('[AuthProvider verifyMfa] UNEXPECTED EXCEPTION: $e');
      debugPrint('[AuthProvider verifyMfa] Stack: $stack');
      return MfaVerifyResult.error;
    } finally {
      // ALWAYS clear loading — this was missing and caused the spinner to lock
      // — but only when this verify still owns the active identity; a newer
      // sign-in or sign-out flow manages its own loading state.
      if (epoch == _identityEpoch) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Cancels registration/MFA flow, signs out, and resets state.
  Future<void> cancelMfaFlow() async {
    _pendingMfaFactorId = null;
    _needsMfaEnrollment = false;
    await signOut();
  }

  /// Registers a new user with patient demographic metadata and inserts patient details.
  ///
  /// The result says how far registration got, so the caller can show the
  /// matching recovery message. See [SignUpOutcome].
  Future<SignUpOutcome> signUp({
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
      final user = response.user;
      final session = response.session;
      if (user == null || session == null) {
        // Email confirmation is required, so there is no session. The patient
        // record is written by an authenticated call, which cannot run without
        // one, so nothing is provisioned here. The account is not signed in.
        return _endFailedSignUp(SignUpOutcome.noSession, kSignUpNoSessionMessage);
      }
      _session = session;
      _user = user;

      final provisionedPatient = await _provisionPatientAfterSignUp(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        contactNumber: contactNumber,
        email: email,
        address: address,
      );
      if (provisionedPatient == null) {
        // The provisioning step has already ended the sign-up with its message.
        return SignUpOutcome.failed;
      }
      _patient = provisionedPatient;
      _isOnboarded = true;

      // The patient row exists from here on. A failure in the steps below must
      // not be reported as a failed registration, or the user would retry and
      // hit "already registered" with no way forward.
      var codeSent = false;
      try {
        _profile = await _profilesRepo.recordPrivacyAcceptance(user.id, DateTime.now());
        _hasConsented = true;
        // Automatically send verification code upon successful signup
        codeSent = await sendVerificationCode(email);
      } catch (e) {
        debugPrint('[AuthProvider signUp] setup after provisioning failed: $e');
      }
      if (!codeSent) {
        return _endFailedSignUp(SignUpOutcome.setupIncomplete, kSignUpSetupIncompleteMessage);
      }

      _isLoading = false;
      notifyListeners();
      return SignUpOutcome.registered;
    } on AuthException catch (e) {
      return _endFailedSignUp(SignUpOutcome.failed, e.message);
    } catch (e) {
      return _endFailedSignUp(SignUpOutcome.failed, e.toString());
    }
  }

  /// Ends a sign-up that did not finish: signs the local session out, clears
  /// the account state and shows [message].
  ///
  /// The message is set after the identity reset, because assigning `_user`
  /// clears the error message.
  Future<SignUpOutcome> _endFailedSignUp(SignUpOutcome outcome, String message) async {
    await _client.auth.signOut().catchError((_) {});
    _user = null;
    _session = null;
    _profile = null;
    _patient = null;
    _permissions = const <String>{};
    _permissionLoadState = PermissionLoadState.idle;
    _permissionLoadError = null;
    _hasConsented = false;
    _isOnboarded = false;
    _isLoading = false;
    _errorMessage = message;
    notifyListeners();
    return outcome;
  }

  Future<Patient?> _provisionPatientAfterSignUp({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  }) async {
    try {
      final provisionedPatient = await _patientProvisioningService.createPatientRecord(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        contactNumber: contactNumber,
        email: email,
        address: address,
      );

      return provisionedPatient ??
          Patient(
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
    } on PatientProvisioningException catch (e) {
      if (e.outcome == PatientProvisioningOutcome.uncertain) {
        // The function may have created the row before the connection dropped.
        // The account is kept either way: a pending account can be recovered,
        // a deleted one cannot.
        final resolved = await _resolveUncertainProvisioning(
          firstName: firstName,
          lastName: lastName,
          dateOfBirth: dateOfBirth,
          gender: gender,
          contactNumber: contactNumber,
          email: email,
          address: address,
        );
        if (resolved != null) {
          return resolved;
        }
      } else if (e.status == 400) {
        // The server refused the fields before writing or deleting anything,
        // so this login has no patient row and never will. Delete it while the
        // session is still valid, so the patient can register again.
        await _verificationService.deletePendingUser();
      }

      final message = e.message;
      await _client.auth.signOut().catchError((_) {});
      _user = null;
      _session = null;
      _profile = null;
      _patient = null;
      _permissions = const <String>{};
      _permissionLoadState = PermissionLoadState.idle;
      _permissionLoadError = null;
      _hasConsented = false;
      _isOnboarded = false;
      _isLoading = false;
      // After `_user = null`, whose identity reset clears the error.
      _errorMessage = message;
      notifyListeners();
      return null;
    }
  }

  /// Resolves a provisioning attempt whose outcome is unknown: the function
  /// may already have created the patient row.
  ///
  /// The row is looked up first and the (now idempotent) function is retried
  /// once, so a lost response never leaves the account without its patient row
  /// and never deletes a working account. Only a known outcome (the lookup
  /// proved there is no row and the server refused the retry) deletes the
  /// pending user, so the patient can register again; an uncertain result
  /// always keeps the account.
  Future<Patient?> _resolveUncertainProvisioning({
    required String firstName,
    required String lastName,
    required DateTime dateOfBirth,
    required Gender gender,
    required String contactNumber,
    required String email,
    required String address,
  }) async {
    final userId = _user?.id;
    if (userId == null) {
      return null;
    }

    var lookupSucceeded = false;
    try {
      final existing = await _patientsRepo.getPatientByProfileId(userId);
      lookupSucceeded = true;
      if (existing != null) {
        return existing;
      }
    } catch (_) {
      // The lookup failed (for example the device is offline); the retry
      // below is the second chance.
    }

    try {
      return await _patientProvisioningService.createPatientRecord(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        gender: gender,
        contactNumber: contactNumber,
        email: email,
        address: address,
      );
    } on PatientProvisioningException catch (e) {
      // Known outcome: the lookup succeeded and found no row, and the server
      // itself refused the retry, so nothing was written for this account.
      // Delete the pending user so the patient can register again. When the
      // lookup failed, a row may still exist, so the account is kept.
      if (lookupSucceeded && e.outcome == PatientProvisioningOutcome.rejected) {
        await _verificationService.deletePendingUser();
      }
      return null;
    }
  }

  /// Updates database profile to record RA 10173 consent acceptance.
  Future<bool> acceptConsent() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Consent without an account to attach it to is not consent. Reporting
    // success here would open the app with nothing recorded on the server.
    final currentUser = _user;
    if (currentUser == null) {
      _errorMessage = 'Your session has expired. Sign in again to accept the agreement.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    try {
      // Same write the web agreement page makes: the consent timestamp only.
      _profile = await _profilesRepo.recordPrivacyAcceptance(currentUser.id, DateTime.now());
      _hasConsented = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on Failure catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
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
    _signOutGeneration++;
    _user = null;
    _session = null;
    // Captured after the local clear above: if a newer identity signs in while
    // the network sign-out is in flight, its state must not be wiped below.
    final epoch = _identityEpoch;
    _isLoading = true;
    notifyListeners();
    try {
      _activityService.stopMonitoring();
      await _client.auth.signOut();
    } finally {
      if (epoch == _identityEpoch) {
        await _clearLocalCache();
      }
      if (epoch == _identityEpoch) {
        _user = null;
        _session = null;
        _profile = null;
        _patient = null;
        _patientRecordState = PatientRecordState.unknown;
        _patientRecordError = null;
        _permissions = const <String>{};
        _permissionLoadState = PermissionLoadState.idle;
        _permissionLoadError = null;
        _hasConsented = false;
        _isOnboarded = false;
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  // A failed cache clear must not leave sign-out half done.
  Future<void> _clearLocalCache() async {
    try {
      await localDatabase?.clearAllCache();
    } catch (e) {
      debugPrint('[AuthProvider] Local cache clear failed on sign-out: $e');
    }
  }

  Future<void> _loadPermissionsForProfile(int epoch) async {
    final profile = _profile;

    // Without a profile there is no account to ask about, and a patient
    // account has no permission-gated screen: the patient area is its own.
    // Asking the server for grants a patient never uses would only add a
    // round trip to every sign-in.
    if (profile == null || profile.role == UserRole.patient) {
      _permissions = const <String>{};
      _permissionLoadState = PermissionLoadState.idle;
      _permissionLoadError = null;
      return;
    }

    _permissionLoadState = PermissionLoadState.loading;
    _permissionLoadError = null;

    try {
      final loaded = await _permissionService.loadPermissions();
      if (epoch != _identityEpoch) return;
      // An empty answer is an answer: the account holds no permission. It is
      // not a failure, and it is not a reason to fall back to the role text
      // on the profile.
      _permissions = loaded;
      _permissionLoadState = PermissionLoadState.loaded;
    } catch (e) {
      if (epoch != _identityEpoch) return;
      // The grants are unknown here, not empty. The account is neither routed
      // as if it held nothing nor as if it held everything: the router shows
      // the failure and offers a retry.
      _permissions = const <String>{};
      _permissionLoadState = PermissionLoadState.failed;
      _permissionLoadError = e is PermissionLoadException
          ? e.message
          : 'Could not read your permissions. Check your connection and retry.';
    }
  }

  /// Re-runs the permission load for the active account.
  ///
  /// The retry belongs to the failed state: the grants are unknown then, and
  /// the account cannot be routed until the server answers again. A load that
  /// succeeds replaces the failure with the answer, empty or not.
  Future<void> retryPermissionLoad() async {
    if (_isDisposed) return;
    if (_user == null || _profile == null) return;
    if (_profile?.role == UserRole.patient) return;

    final epoch = _identityEpoch;
    _permissionLoadState = PermissionLoadState.loading;
    _permissionLoadError = null;
    notifyListeners();

    await _loadPermissionsForProfile(epoch);
    if (_isDisposed) return;
    notifyListeners();
  }

  /// Triggers Edge Function to send email verification code.
  Future<bool> sendVerificationCode(String email) async {
    final epoch = _identityEpoch;
    _verificationState = _verificationState.copyWith(status: VerificationStatus.verifying);
    notifyListeners();

    final result = await _verificationService.sendCode(email: email);
    if (epoch != _identityEpoch) return false;
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
    final epoch = _identityEpoch;
    final email = _user?.email;
    if (email == null) {
      _errorMessage = 'No active session email found.';
      notifyListeners();
      return false;
    }

    _verificationState = _verificationState.copyWith(status: VerificationStatus.verifying);
    notifyListeners();

    final result = await _verificationService.verifyCode(email: email, code: code);
    if (epoch != _identityEpoch) return false;
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
        try {
          await _client.auth.refreshSession();
        } catch (_) {}
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
