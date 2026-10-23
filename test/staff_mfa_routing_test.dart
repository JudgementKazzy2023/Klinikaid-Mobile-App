import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/routing/app_router.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

// Implements rather than constructs AuthProvider: no Supabase or platform work.
class RouterAuth extends ChangeNotifier implements AuthProvider {
  RouterAuth(UserRole? role)
    : profile = role == null
          ? null
          : Profile(
              id: 'test-user',
              fullName: 'Test User',
              role: role,
              department: Department.laboratory,
              emailVerifiedAt: DateTime(2026),
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            );

  @override
  final Profile? profile;
  @override
  bool get isAuthenticated => true;
  @override
  bool get isLoading => false;
  @override
  bool get hasConsented => true;
  @override
  bool isAal2 = false;
  @override
  bool isAal1Pending = false;
  @override
  bool get usesLegacyPermissionFallback => true;
  @override
  Set<String> get permissions => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const homes = {
    UserRole.admin: '/admin/dashboard',
    UserRole.receptionist: '/reception/queue',
    UserRole.departmentStaff: '/department/queue',
    UserRole.medicalSpecialist: '/specialist/dashboard',
  };

  for (final entry in homes.entries) {
    testWidgets(
      '${entry.key.name}: AAL1 gates home and stays at MFA; AAL2 exits',
      (tester) async {
        final auth = RouterAuth(entry.key);
        final router = AppRouter(auth).router;
        addTearDown(router.dispose);
        addTearDown(auth.dispose);
        late BuildContext context;
        await tester.pumpWidget(
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        );

        Future<String?> redirect(String location) async =>
            router.configuration.topRedirect(
              context,
              GoRouterState(
                router.configuration,
                uri: Uri.parse(location),
                matchedLocation: location,
                fullPath: location,
                pathParameters: const {},
                pageKey: ValueKey(location),
              ),
            );

        // No pending flag: exercises the protective router check independently
        // of enrollment discovery, including a restored AAL1 session.
        expect(await redirect(entry.value), '/mfa-verify');
        expect(await redirect('/'), '/mfa-verify');
        expect(await redirect('/mfa-verify'), isNull);
        auth.isAal1Pending = true;
        expect(await redirect(entry.value), '/mfa-verify');
        expect(await redirect('/mfa-verify'), isNull);
        auth.isAal1Pending = false;
        auth.isAal2 = true;
        expect(await redirect('/mfa-verify'), entry.value);
        expect(await redirect('/'), entry.value);
        expect(await redirect(entry.value), isNull);
      },
    );
  }

  testWidgets('patient at AAL1 stays exempt, including a missing role_id', (
    tester,
  ) async {
    final auth = RouterAuth(UserRole.patient);
    final router = AppRouter(auth).router;
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    );
    Future<String?> redirect(String location) async =>
        router.configuration.topRedirect(
          context,
          GoRouterState(
            router.configuration,
            uri: Uri.parse(location),
            matchedLocation: location,
            fullPath: location,
            pathParameters: const {},
            pageKey: ValueKey(location),
          ),
        );
    expect(auth.profile?.roleId, isNull);
    // The backend also needs role_id linked to the patient role for its RLS
    // exemption. Fixing a missing link is outside this client gating change.
    expect(await redirect('/'), '/patient');
    expect(await redirect('/patient'), isNull);
    expect(await redirect('/mfa-verify'), '/patient');
  });
  testWidgets('authenticated AAL1 with a missing profile is not sent to MFA', (
    tester,
  ) async {
    final auth = RouterAuth(null);
    final router = AppRouter(auth).router;
    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    );
    Future<String?> redirect(String location) async =>
        router.configuration.topRedirect(
          context,
          GoRouterState(
            router.configuration,
            uri: Uri.parse(location),
            matchedLocation: location,
            fullPath: location,
            pathParameters: const {},
            pageKey: ValueKey(location),
          ),
        );
    expect(auth.profile, isNull);
    expect(await redirect('/'), isNull);
    expect(await redirect('/login'), isNull);
    expect(await redirect('/patient'), isNull);
    expect(await redirect('/mfa-verify'), isNull);
  });
}
