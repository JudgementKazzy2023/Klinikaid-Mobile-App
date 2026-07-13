import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/native.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/data/session_activity_service.dart';
import 'package:klinikaid_mobile/features/auth/presentation/screens/login_screen.dart';

class MockSessionActivityService extends SessionActivityService {
  @override
  void startMonitoring({required Duration timeout, required VoidCallback onTimeout}) {}
  @override
  void stopMonitoring() {}
  @override
  void recordActivity() {}
  @override
  Future<void> restoreLastActivity() async {}
}

class MockSupabaseClient extends SupabaseClient {
  MockSupabaseClient()
      : super('https://onzeyejlfydvvbkejvwf.supabase.co', 'mock-anon-key');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  setUpAll(() async {
    try {
      await Supabase.initialize(
        url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    } catch (_) {}
  });

  late LocalDatabase localDatabase;
  late AuthProvider authProvider;
  late MockSessionActivityService mockActivityService;
  late MockSupabaseClient mockSupabaseClient;

  setUp(() {
    localDatabase = LocalDatabase(NativeDatabase.memory());
    mockActivityService = MockSessionActivityService();
    mockSupabaseClient = MockSupabaseClient();
    authProvider = AuthProvider(
      client: mockSupabaseClient,
      activityService: mockActivityService,
    );
  });

  tearDown(() async {
    authProvider.dispose();
    await localDatabase.close();
  });

  Widget createTestWidget(AppRouter appRouter) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: MaterialApp.router(
        routerConfig: appRouter.router,
      ),
    );
  }

  group('Login Screen Password Visibility Toggle Tests', () {
    testWidgets('Password obscureText toggles correctly on suffix icon tap', (tester) async {
      final router = AppRouter(authProvider);
      await tester.pumpWidget(createTestWidget(router));
      await tester.pumpAndSettle();

      // Find password field
      final passwordFinder = find.widgetWithText(TextFormField, 'Password');
      expect(passwordFinder, findsOneWidget);

      final textFieldFinder = find.descendant(
        of: passwordFinder,
        matching: find.byType(TextField),
      );
      expect(textFieldFinder, findsOneWidget);

      // Verify initial obscureText state is true
      TextField textFieldWidget = tester.widget(textFieldFinder);
      expect(textFieldWidget.obscureText, isTrue);

      // Find the toggle button
      final toggleButton = find.byKey(const Key('show_password_btn'));
      expect(toggleButton, findsOneWidget);

      // Tap the toggle button to show password
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Verify obscureText is now false
      textFieldWidget = tester.widget(textFieldFinder);
      expect(textFieldWidget.obscureText, isFalse);

      // Tap again to hide password
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Verify obscureText is true again
      textFieldWidget = tester.widget(textFieldFinder);
      expect(textFieldWidget.obscureText, isTrue);
    });
  });
}
