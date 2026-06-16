import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/repositories/patients_repository.dart';
import '../../../../core/repositories/profiles_repository.dart';
import '../../../../core/models/patient.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/errors/failures.dart';

/// Provider that manages authentication state, RA 10173 consent, and patient onboarding flow.
class AuthProvider extends ChangeNotifier {
  final _client = Supabase.instance.client;
  final _patientsRepo = PatientsRepository();
  final _profilesRepo = ProfilesRepository();

  User? _user;
  Session? _session;
  Profile? _profile;
  Patient? _patient;
  bool _hasConsented = false;
  bool _isOnboarded = false;
  bool _isLoading = true;
  String? _errorMessage;

  Profile? get profile => _profile;
  Patient? get patient => _patient;

  StreamSubscription<AuthState>? _authStateSubscription;

  AuthProvider() {
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
  Future<void> _updateLocalStates() async {
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

    // If the profile is admin, block access, sign out, and clear state
    if (_profile?.role == UserRole.admin) {
      _errorMessage = 'Admin accounts must sign in via the web portal.';
      await _client.auth.signOut();
      _user = null;
      _session = null;
      _profile = null;
      _patient = null;
      _hasConsented = false;
      _isOnboarded = false;
      return;
    }

    // If staff role, bypass consent and onboarding gates
    if (_profile?.role == UserRole.receptionist ||
        _profile?.role == UserRole.departmentStaff ||
        _profile?.role == UserRole.medicalSpecialist) {
      _hasConsented = true;
      _isOnboarded = true;
      _patient = null;
      return;
    }

    // 2. Evaluate Privacy Consent (check both user metadata and profiles table)
    final consentAtMetadata = currentUser.userMetadata?['privacy_consent_at'];
    final consentAtProfile = _profile?.acceptedPrivacyAt;
    _hasConsented = consentAtMetadata != null || consentAtProfile != null;

    // 3. Evaluate Onboarding Status (linked patients row)
    try {
      _patient = await _patientsRepo.getPatientByProfileId(currentUser.id);
      _isOnboarded = _patient != null;
    } catch (_) {
      _patient = null;
      _isOnboarded = false;
    }
  }


  /// Clear active error messages.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Signs in a user using email and password.
  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _client.auth.signInWithPassword(email: email, password: password);
      _session = response.session;
      _user = response.user;
      await _updateLocalStates();
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

  /// Registers a new user with metadata mapping to trigger profiles creation.
  Future<bool> signUp(String email, String password, String fullName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
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
      await _updateLocalStates();
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

  /// Updates user metadata and database profile to record RA 10173 consent acceptance.
  Future<bool> acceptConsent() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Update user metadata
      await _client.auth.updateUser(
        UserAttributes(
          data: {
            'privacy_consent_at': DateTime.now().toIso8601String(),
          },
        ),
      );

      // 2. Update profiles table (with fallback if schema columns are not yet deployed)
      final currentUser = _user;
      if (currentUser != null) {
        try {
          final profile = _profile ?? await _profilesRepo.getProfile(currentUser.id);
          final updatedProfile = Profile(
            id: profile.id,
            fullName: profile.fullName,
            role: profile.role,
            department: profile.department,
            isActive: profile.isActive,
            acceptedPrivacyAt: DateTime.now(),
            createdAt: profile.createdAt,
            updatedAt: DateTime.now(),
          );
          _profile = await _profilesRepo.updateProfile(updatedProfile);
        } catch (dbError) {
          // ignore: avoid_print
          print('Database profile consent update skipped (possibly column not deployed yet): $dbError');
        }
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

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
