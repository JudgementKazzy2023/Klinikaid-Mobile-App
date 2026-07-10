import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/auth/domain/password_change_result.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/screens/profile_screen.dart';
import 'package:klinikaid_mobile/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/widgets/change_password_modal.dart';

// ─── Mock user ───────────────────────────────────────────────────────────────

class _MockUser extends supabase.User {
  final String _email;
  _MockUser({required this._email, required super.id})
      : super(
          appMetadata: {},
          userMetadata: {},
          aud: '',
          createdAt: '',
        );
  @override
  String? get email => _email;
}

// ─── Mock AuthProvider ───────────────────────────────────────────────────────

class PasswordChangeMockAuthProvider extends AuthProvider {
  supabase.User? _mockUser;
  Profile? _mockProfile;
  final bool _mockIsLoading = false;

  // Controls returned by changePassword()
  PasswordChangeResult changePasswordResult = PasswordChangeResult.success;
  bool changePasswordCalled = false;
  String? lastCurrentPassword;
  String? lastNewPassword;

  PasswordChangeMockAuthProvider() : super();

  void setMockUser(supabase.User? u) => _mockUser = u;
  void setMockProfile(Profile? p) => _mockProfile = p;

  @override
  supabase.User? get user => _mockUser;

  @override
  Profile? get profile => _mockProfile;

  @override
  bool get isLoading => _mockIsLoading;

  @override
  Future<PasswordChangeResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalled = true;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    return changePasswordResult;
  }

  @override
  Future<void> signOut() async {}
}

// ─── Setup helpers ────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') return <String, Object>{};
    return true;
  });

  late LocalDatabase localDatabase;
  late DashboardProvider dashboardProvider;

  setUpAll(() async {
    await supabase.Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
      ),
    );
  });

  setUp(() {
    localDatabase = LocalDatabase(NativeDatabase.memory());
    dashboardProvider = DashboardProvider(localDatabase);
  });

  tearDown(() async {
    await localDatabase.close();
  });

  // Build the ProfileScreen (non-patient / staff branch)
  Widget createProfileWidget(PasswordChangeMockAuthProvider auth) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<DashboardProvider>.value(value: dashboardProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ProfileScreen()),
      ),
    );
  }

  // Build the modal directly (skips profile screen navigation)
  Widget createModalWidget(PasswordChangeMockAuthProvider auth) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<DashboardProvider>.value(value: dashboardProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ChangePasswordModal()),
      ),
    );
  }

  // A staff mock profile (receptionist — any non-patient role works the same)
  Profile makeStaffProfile(UserRole role) => Profile(
        id: 'staff-uuid',
        fullName: 'Test Staff',
        role: role,
        department: null,
        emailVerifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  // ─── Widget Tests ───────────────────────────────────────────────────────────

  group('Phase R6: Staff Password Change', () {
    // ── Test 1: Button visible on profile for all staff roles ──────────────

    for (final role in [
      UserRole.receptionist,
      UserRole.departmentStaff,
      UserRole.medicalSpecialist,
    ]) {
      testWidgets(
        'Test 1 [${role.name}]: Profile shows Change Password button',
        (tester) async {
          final auth = PasswordChangeMockAuthProvider();
          auth.setMockUser(
              _MockUser(email: 'staff@clinic.ph', id: 'staff-uuid'));
          auth.setMockProfile(makeStaffProfile(role));

          await tester.pumpWidget(createProfileWidget(auth));
          await tester.pump();

          expect(find.byKey(const Key('btn_change_password')), findsOneWidget);
          expect(find.text('Change Password'), findsOneWidget);
        },
      );
    }

    // ── Test 2: Tap button → modal opens with 3 fields ─────────────────────

    testWidgets('Test 2: Tap Change Password → modal opens with 3 fields',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      auth.setMockUser(_MockUser(email: 'staff@clinic.ph', id: 'staff-uuid'));
      auth.setMockProfile(makeStaffProfile(UserRole.receptionist));

      await tester.pumpWidget(createProfileWidget(auth));
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_change_password')));
      await tester.pumpAndSettle();

      expect(find.text('Change Password'), findsWidgets); // title + button label
      expect(find.byKey(const Key('field_current_password')), findsOneWidget);
      expect(find.byKey(const Key('field_new_password')), findsOneWidget);
      expect(find.byKey(const Key('field_confirm_password')), findsOneWidget);
    });

    // ── Test 3: Update disabled when all fields empty ──────────────────────

    testWidgets('Test 3: Update Password disabled when fields empty',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_update_password')));
      expect(btn.onPressed, isNull);
    });

    // ── Test 4: Failing new password → inline error, button disabled ────────

    testWidgets(
        'Test 4: Failing new password shows inline error, button disabled',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      // Fill current password (non-empty) and a short new password
      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'CurrentP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'short');
      await tester.pump();

      // Inline validator error should show
      expect(find.textContaining('Min 8 characters'), findsOneWidget);

      // Button still disabled
      final btn = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_update_password')));
      expect(btn.onPressed, isNull);
    });

    // ── Test 5: Confirm ≠ new → mismatch error, button disabled ────────────

    testWidgets('Test 5: Confirm mismatch shows error, button disabled',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'CurrentP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'NewP@ssword1');
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), 'MismatchPass1!');
      await tester.pump();

      expect(find.textContaining('do not match'), findsOneWidget);

      final btn = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_update_password')));
      expect(btn.onPressed, isNull);
    });

    // ── Test 6: New == current → blocked, button disabled ──────────────────

    testWidgets('Test 6: New == current is blocked, button disabled',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      const same = 'SameP@ss1';
      await tester.enterText(
          find.byKey(const Key('field_current_password')), same);
      await tester.enterText(
          find.byKey(const Key('field_new_password')), same);
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), same);
      await tester.pump();

      expect(find.textContaining('must differ'), findsOneWidget);

      final btn = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_update_password')));
      expect(btn.onPressed, isNull);
    });

    // ── Test 7: All valid + match → button enabled ─────────────────────────

    testWidgets('Test 7: All valid and matching → Update enabled', (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'OldP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'NewP@ss12!');
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), 'NewP@ss12!');
      await tester.pump();

      final btn = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_update_password')));
      expect(btn.onPressed, isNotNull);
    });

    // ── Test 8: Show/hide toggles independently reveal each field ──────────

    testWidgets('Test 8: Show/hide toggles independently per field',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      // There are exactly 3 visibility toggles
      final toggles = find.byIcon(Icons.visibility_outlined);
      expect(toggles, findsNWidgets(3));

      // Tap only the first toggle
      await tester.tap(toggles.first);
      await tester.pump();

      // Now the first field shows visibility_off, the other two are still visible_outlined
      expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(1));
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    });

    // ── Test 9: Cancel → dismisses dialog, no changePassword call ──────────

    testWidgets('Test 9: Cancel dismisses modal, changePassword not called',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      await tester.pumpWidget(createProfileWidget(auth)
        ..key); // just need a widget host

      // Open modal directly
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<LocalDatabase>.value(value: localDatabase),
          ChangeNotifierProvider<DashboardProvider>.value(
              value: dashboardProvider),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (_) => const ChangePasswordModal(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordModal), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordModal), findsNothing);
      expect(auth.changePasswordCalled, isFalse);
    });

    // ─── Unit-style Tests (via mock AuthProvider) ─────────────────────────

    // ── Test 10: Correct password → success, SnackBar shown ────────────────

    testWidgets('Test 10: Correct current → success, SnackBar shown',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      auth.changePasswordResult = PasswordChangeResult.success;

      // Pump a Scaffold and show the dialog to permit popping and showing a SnackBar
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<LocalDatabase>.value(value: localDatabase),
          ChangeNotifierProvider<DashboardProvider>.value(
              value: dashboardProvider),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    barrierDismissible: false,
                    builder: (_) => const ChangePasswordModal(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'OldP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'NewP@ss12!');
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), 'NewP@ss12!');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_update_password')));
      await tester.pumpAndSettle();

      expect(auth.changePasswordCalled, isTrue);
      expect(auth.lastCurrentPassword, 'OldP@ss1');
      expect(auth.lastNewPassword, 'NewP@ss12!');
      expect(find.text('Password updated'), findsOneWidget);
    });

    // ── Test 11: Wrong current → wrongCurrentPassword, no dialog dismiss ───

    testWidgets(
        'Test 11: Wrong current → error banner, modal stays open',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      auth.changePasswordResult = PasswordChangeResult.wrongCurrentPassword;

      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'WrongP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'NewP@ss12!');
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), 'NewP@ss12!');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_update_password')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Current password is incorrect'), findsOneWidget);
      expect(auth.changePasswordCalled, isTrue);
      // Modal still visible (dialog not popped on error)
      expect(find.byType(ChangePasswordModal), findsOneWidget);
    });

    // ── Test 12: notAuthenticated → error banner shown ─────────────────────

    testWidgets('Test 12: notAuthenticated → error banner shown', (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      auth.changePasswordResult = PasswordChangeResult.notAuthenticated;

      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'OldP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'NewP@ss12!');
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), 'NewP@ss12!');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_update_password')));
      await tester.pumpAndSettle();

      expect(find.textContaining('No active session'), findsOneWidget);
    });

    // ── Test 13: error → generic error banner shown ─────────────────────────

    testWidgets('Test 13: error result → generic error banner shown',
        (tester) async {
      final auth = PasswordChangeMockAuthProvider();
      auth.changePasswordResult = PasswordChangeResult.error;

      await tester.pumpWidget(createModalWidget(auth));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('field_current_password')), 'OldP@ss1');
      await tester.enterText(
          find.byKey(const Key('field_new_password')), 'NewP@ss12!');
      await tester.enterText(
          find.byKey(const Key('field_confirm_password')), 'NewP@ss12!');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn_update_password')));
      await tester.pumpAndSettle();

      expect(find.textContaining('An error occurred'), findsOneWidget);
    });
  });
}
