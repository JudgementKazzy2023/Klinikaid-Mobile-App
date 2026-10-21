import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klinikaid_mobile/features/auth/domain/password_reset_result.dart';
import 'package:klinikaid_mobile/features/auth/domain/registration_validators.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:klinikaid_mobile/features/auth/presentation/widgets/email_change_modal.dart';

// No AuthProvider constructor, SDK initialization, storage or network calls.
class _Auth extends ChangeNotifier implements AuthProvider {
  final resetEmails = <String>[];

  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  Future<PasswordResetResult> sendPasswordReset(String email) async {
    resetEmails.add(email);
    return PasswordResetResult.success;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const validEmails = [
    'name@example.com',
    'Mixed.Case@Example.COM',
    'patient+lab@care.example.technology',
    "o'connor@example.com",
    '  name@example.com  ',
  ];
  const invalidEmails = [
    '',
    'name',
    'name@',
    '@example.com',
    'name@example',
    'name@@example.com',
    'na me@example.com',
    'name@exam ple.com',
    'name\n@example.com',
    '.name@example.com',
    'name..last@example.com',
    'name.@example.com',
    'name@-example.com',
    'name@example-.com',
    'name@exam_ple.com',
    'name@example..com',
    r'name\@example.com',
    r'name@example\.com',
  ];

  for (final email in validEmails) {
    test('shared email accepts $email', () {
      expect(RegistrationValidators.validateEmail(email), isTrue);
    });
  }
  for (final email in invalidEmails) {
    test('shared email rejects $email', () {
      expect(RegistrationValidators.validateEmail(email), isFalse);
    });
  }
  for (final phone in ['09123456789', '+639123456789', ' 09123456789 ']) {
    test('shared contact accepts $phone', () {
      expect(RegistrationValidators.validateContactNumber(phone), isTrue);
    });
  }
  for (final phone in [
    '',
    '0912345678',
    '091234567890',
    '+63912345678',
    '+6391234567890',
    '639123456789',
    '08123456789',
    '09123abc789',
    '09123 56789',
    r'09\ddddddddd',
    r'\+639123456789',
  ]) {
    test('shared contact rejects $phone', () {
      expect(RegistrationValidators.validateContactNumber(phone), isFalse);
    });
  }

  late _Auth auth;
  setUp(() => auth = _Auth());
  tearDown(() => auth.dispose());

  Widget app(Widget child) => ChangeNotifierProvider<AuthProvider>.value(
    value: auth,
    child: MaterialApp(home: child),
  );

  testWidgets('recovery enables valid email, disables invalid, submits once', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      app(
        RepaintBoundary(key: boundaryKey, child: const ForgotPasswordScreen()),
      ),
    );
    final field = find.byType(TextFormField);
    final button = find.widgetWithText(ElevatedButton, 'Send Reset Link');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    // Single-line fields remove newlines before validation; covered above in units.
    for (final email in [
      ...validEmails,
      ...invalidEmails.where((email) => !email.contains('\n')),
    ]) {
      await tester.enterText(field, email);
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(button).onPressed != null,
        validEmails.contains(email),
        reason: email,
      );
    }
    expect(auth.resetEmails, isEmpty);
    await tester.enterText(field, ' patient+lab@care.example.technology ');
    await tester.pumpAndSettle();

    // Optional private visual evidence from the same mocked widget assertion.
    final evidenceDir = Platform.environment['AUTH_VALIDATION_SCREENSHOT_DIR'];
    if (evidenceDir != null) {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final imageFuture = boundary.toImage();
      await tester.runAsync(() async {
        final image = await imageFuture.timeout(const Duration(seconds: 20));
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$evidenceDir/recovery-valid.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(auth.resetEmails, ['patient+lab@care.example.technology']);
    expect(find.text('Check Your Email'), findsOneWidget);
  });

  for (final entry in {
    'registration': const RegisterScreen(),
    'email change': const EmailChangeModal(),
  }.entries) {
    testWidgets('${entry.key} uses shared email validation', (tester) async {
      await tester.pumpWidget(app(entry.value));
      final field = find.byType(TextFormField).first;
      // Single-line fields remove newlines before validation; covered above in units.
      for (final email in [
        ...validEmails,
        ...invalidEmails.where((email) => !email.contains('\n')),
      ]) {
        await tester.enterText(field, email);
        // Validate the actual consumer field without submitting any auth flow.
        final state = tester.state<FormFieldState<String>>(field);
        expect(state.validate(), validEmails.contains(email), reason: email);
        await tester.pump();
        expect(state.errorText == null, validEmails.contains(email));
      }
      expect(auth.resetEmails, isEmpty);
    });
  }
}
