import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is mocked; no live network or platform plugins run.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/repositories/rag_documents_repository.dart';
import 'package:klinikaid_mobile/features/admin/data/admin_repository.dart';
import 'package:klinikaid_mobile/features/admin/domain/admin_rbac.dart';
import 'package:klinikaid_mobile/features/admin/domain/staff_filters.dart';
import 'package:klinikaid_mobile/features/admin/presentation/providers/admin_provider.dart';
import 'package:klinikaid_mobile/features/admin/presentation/screens/admin_staff_screen.dart';

/// The ids of the catalogue roles, the way the web fixture names them.
const String kAdminRoleId = '11111111-1111-4111-8111-111111111111';
const String kReceptionistRoleId = '22222222-2222-4222-8222-222222222222';
const String kPatientRoleId = '44444444-4444-4444-8444-444444444444';
const String kCustomRoleId = '33333333-3333-4333-8333-333333333333';

/// A role id the catalogue does not know.
const String kUnknownRoleId = '99999999-9999-4999-8999-999999999999';

/// The live catalogue: the system roles and one custom role.
///
/// The custom role is the one the web creates in /admin/roles; it stores
/// "receptionist" as its base role, so its legacy text belongs to a
/// different role.
final AdminRbacCatalog kCatalogue = AdminRbacCatalog(
  roles: [
    AdminRole(
      id: kAdminRoleId,
      name: 'admin',
      description: '',
      isSystem: true,
    ),
    AdminRole(
      id: kReceptionistRoleId,
      name: 'receptionist',
      description: '',
      isSystem: true,
    ),
    AdminRole(
      id: kPatientRoleId,
      name: 'patient',
      description: '',
      isSystem: true,
    ),
    AdminRole(
      id: kCustomRoleId,
      name: 'Front Desk Supervisor',
      description: '',
      isSystem: false,
      baseRole: 'receptionist',
    ),
  ],
  permissions: const [],
);

Profile _staff({
  required String id,
  required String name,
  UserRole role = UserRole.receptionist,
  String? roleId,
  Department? department,
  bool isActive = true,
  String? employeeType,
}) {
  return Profile(
    id: id,
    fullName: name,
    role: role,
    roleId: roleId,
    department: department,
    employeeType: employeeType,
    isActive: isActive,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

/// The registry the tests filter: the same rows the web fixture uses.
final List<Profile> kRegistry = [
  _staff(
    id: 'a',
    name: 'Ana Admin',
    role: UserRole.admin,
    roleId: kAdminRoleId,
  ),
  _staff(
    id: 'b',
    name: 'Ben Lab',
    role: UserRole.departmentStaff,
    department: Department.laboratory,
  ),
  _staff(
    id: 'c',
    name: 'Cara Imaging',
    role: UserRole.departmentStaff,
    department: Department.imaging,
  ),
  _staff(
    id: 'd',
    name: 'Dan Custom',
    roleId: kCustomRoleId,
  ),
  _staff(
    id: 'e',
    name: 'Eve Retired',
    roleId: kReceptionistRoleId,
    isActive: false,
  ),
];

/// The names of the rows a filter keeps.
List<String> _namesOf(List<Profile> staff) =>
    staff.map((member) => member.fullName).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the role filter', () {
    test('a custom catalogue role is filterable by its id', () {
      final filters = buildStaffFilters(
        roleId: kCustomRoleId,
        catalogue: kCatalogue.roles,
      );

      // Dan carries the custom role. Ben and Cara are plain department staff
      // and a custom role's legacy text is its *base* role, so they must not
      // match.
      expect(
        _namesOf(filterStaff(kRegistry, filters)),
        ['Dan Custom'],
      );
    });

    test('a custom role does not claim the staff that carry only its base role', () {
      final filters = buildStaffFilters(
        roleId: kCustomRoleId,
        catalogue: kCatalogue.roles,
      );
      final baseRoleRow = _staff(
        id: 'x',
        name: 'Legacy Receptionist',
        roleId: null,
      );

      expect(matchesStaffRole(baseRoleRow, filters.role!), isFalse);
    });

    test('a profile without a role id is matched through the system role text', () {
      final filters = buildStaffFilters(
        roleId: kReceptionistRoleId,
        catalogue: kCatalogue.roles,
      );

      // Eve carries the receptionist role id. The legacy department staff
      // rows carry the text "department_staff", which is a different role,
      // and Dan carries a custom role id, so neither is a receptionist.
      expect(
        _namesOf(filterStaff(kRegistry, filters)),
        ['Eve Retired'],
      );
    });

    test('a role the catalogue does not know keeps its filter, like the web', () {
      final filters = buildStaffFilters(
        roleId: kUnknownRoleId,
        catalogue: kCatalogue.roles,
      );

      // The filter is kept and matches no row of this registry.
      expect(filters.role?.id, kUnknownRoleId);
      expect(filters.role?.legacyName, isNull);
      expect(filterStaff(kRegistry, filters), isEmpty);
    });
  });

  group('the department filter', () {
    test('keeps only the staff of the chosen department', () {
      final filters = buildStaffFilters(
        department: StaffDepartmentFilter.laboratory,
        catalogue: kCatalogue.roles,
      );

      expect(_namesOf(filterStaff(kRegistry, filters)), ['Ben Lab']);
    });

    test('"none" keeps the staff without a department', () {
      final filters = buildStaffFilters(
        department: StaffDepartmentFilter.none,
        catalogue: kCatalogue.roles,
      );

      expect(
        _namesOf(filterStaff(kRegistry, filters)),
        ['Ana Admin', 'Dan Custom', 'Eve Retired'],
      );
    });

    test('does not confuse a missing department with a named one', () {
      final withoutDepartment = _staff(id: 'x', name: 'No Department');
      final withDepartment = _staff(
        id: 'y',
        name: 'Ecg Staff',
        department: Department.ecg,
      );

      expect(
        matchesStaffDepartment(
          withoutDepartment,
          StaffDepartmentFilter.none,
        ),
        isTrue,
      );
      expect(
        matchesStaffDepartment(
          withoutDepartment,
          StaffDepartmentFilter.laboratory,
        ),
        isFalse,
      );
      expect(
        matchesStaffDepartment(withDepartment, StaffDepartmentFilter.none),
        isFalse,
      );
    });
  });

  group('the status filter', () {
    test('keeps active staff and inactive staff apart', () {
      final active = buildStaffFilters(
        status: StaffStatusFilter.active,
        catalogue: kCatalogue.roles,
      );
      final inactive = buildStaffFilters(
        status: StaffStatusFilter.inactive,
        catalogue: kCatalogue.roles,
      );

      expect(
        _namesOf(filterStaff(kRegistry, active)),
        ['Ana Admin', 'Ben Lab', 'Cara Imaging', 'Dan Custom'],
      );
      expect(
        _namesOf(filterStaff(kRegistry, inactive)),
        ['Eve Retired'],
      );
    });
  });

  group('the filter values', () {
    test('a value the dimension does not know is dropped', () {
      expect(parseStaffDepartmentFilter('pharmacy'), isNull);
      expect(parseStaffStatusFilter('deleted'), isNull);
      expect(parseStaffDepartmentFilter('laboratory'),
          StaffDepartmentFilter.laboratory);
      expect(parseStaffStatusFilter('inactive'), StaffStatusFilter.inactive);
    });

    test('"all" and an empty value mean no filter', () {
      expect(parseStaffDepartmentFilter(kStaffFilterAll), isNull);
      expect(parseStaffStatusFilter(kStaffFilterAll), isNull);
      expect(parseStaffDepartmentFilter(''), isNull);
      expect(parseStaffStatusFilter('  '), isNull);
    });
  });

  group('combining the filters with the search', () {
    test('keeps only the rows that satisfy every dimension', () {
      final filters = buildStaffFilters(
        department: StaffDepartmentFilter.laboratory,
        status: StaffStatusFilter.active,
        catalogue: kCatalogue.roles,
      );

      expect(
        _namesOf(filterStaff(kRegistry, filters, search: 'ben')),
        ['Ben Lab'],
      );
    });

    test('narrows further when a search term is added', () {
      final filters = buildStaffFilters(
        status: StaffStatusFilter.inactive,
        catalogue: kCatalogue.roles,
      );

      expect(_namesOf(filterStaff(kRegistry, filters)), ['Eve Retired']);
      expect(filterStaff(kRegistry, filters, search: 'ana'), isEmpty);
    });

    test('never returns a row the unfiltered list does not contain', () {
      final filters = buildStaffFilters(
        roleId: kCustomRoleId,
        department: StaffDepartmentFilter.none,
        status: StaffStatusFilter.active,
        catalogue: kCatalogue.roles,
      );

      expect(_namesOf(filterStaff(kRegistry, filters)), ['Dan Custom']);
      expect(filterStaff(kRegistry, filters).length, lessThanOrEqualTo(kRegistry.length));
    });

    test('returns every row when nothing is filtered', () {
      final filters = buildStaffFilters(catalogue: kCatalogue.roles);

      expect(filterStaff(kRegistry, filters), hasLength(kRegistry.length));
      expect(filters.hasActiveFilters, isFalse);
    });
  });

  // --- The screen ---

  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  /// The provider on top of a repository that answers with the fixture.
  AdminProvider useProvider(_FakeAdminRepository repository) {
    return AdminProvider(
      repository: repository,
      ragRepository: _UnusedRag(),
    );
  }

  /// The repository the registry screen reads.
  _FakeAdminRepository useRepository() {
    return _FakeAdminRepository(
      client: client,
      staff: kRegistry,
      catalogue: kCatalogue,
    );
  }

  /// The screen on top of a provider whose data is already loaded.
  Future<AdminProvider> pumpStaffScreen(
    WidgetTester tester,
    AdminProvider provider,
  ) async {
    // A tall surface, so every card of the registry is built and can be
    // found by name.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: AdminStaffScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  /// Chooses a value in one of the filter pickers.
  Future<void> chooseFilter(
    WidgetTester tester,
    String dropdownKey,
    String label,
  ) async {
    await tester.tap(find.byKey(Key(dropdownKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the count shows how many of the staff the filters keep',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    expect(find.text('Showing 5 of 5 personnel'), findsOneWidget);
    expect(find.text('Ana Admin'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('the role picker offers the catalogue roles and filters the registry',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    // The picker is driven by the live catalogue: the custom role is in it,
    // the patient role is not offered, and nothing about it is hard-coded.
    await tester.tap(find.byKey(const Key('staff_filter_role_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Front Desk Supervisor'), findsOneWidget);
    expect(find.text('Receptionist'), findsOneWidget);
    expect(find.text('Patient'), findsNothing);
    await tester.tapAt(const Offset(0, 0));
    await tester.pumpAndSettle();

    await chooseFilter(
      tester,
      'staff_filter_role_dropdown',
      'Front Desk Supervisor',
    );

    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Dan Custom'), findsOneWidget);
    expect(find.text('Ana Admin'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('the department and the status filter narrow the registry',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    await chooseFilter(
      tester,
      'staff_filter_department_dropdown',
      'Imaging (X-Ray)',
    );
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Cara Imaging'), findsOneWidget);

    await chooseFilter(
      tester,
      'staff_filter_department_dropdown',
      'All departments',
    );
    await chooseFilter(
      tester,
      'staff_filter_status_dropdown',
      'Inactive',
    );
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);
    expect(find.text('Ana Admin'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('the filters combine with the search', (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    await chooseFilter(
      tester,
      'staff_filter_role_dropdown',
      'Receptionist',
    );
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pumpAndSettle();
    expect(find.text('Showing 0 of 5 personnel'), findsOneWidget);
    expect(find.text('No personnel match these filters'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'eve');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('a role deleted from the catalogue keeps its filter as "Unknown role"', (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    await chooseFilter(
      tester,
      'staff_filter_role_dropdown',
      'Front Desk Supervisor',
    );
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);

    // The custom role is gone from the catalogue (it was deleted on the
    // web). The selection is kept, as on the web: it is labelled
    // "Unknown role" and still matches by role_id, so the profile that
    // carries the deleted id is the one row it keeps.
    repository.catalogue = AdminRbacCatalog(
      roles: kCatalogue.roles
          .where((role) => role.id != kCustomRoleId)
          .toList(),
      permissions: const [],
    );
    await provider.loadRbacCatalog();
    await tester.pumpAndSettle();

    expect(find.text('Unknown role'), findsWidgets);
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Dan Custom'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('a failed catalogue read shows the error and no role-filtered table',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    await chooseFilter(
      tester,
      'staff_filter_role_dropdown',
      'Receptionist',
    );
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);

    // The catalogue read fails.
    repository.catalogueError = StateError('offline');
    await provider.loadRbacCatalog();
    await tester.pumpAndSettle();

    // The operator is told why, the count is withheld and the table is not
    // shown under a filter that cannot be applied.
    expect(
      find.byKey(const Key('staff_role_catalogue_error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('staff_role_catalogue_retry_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('staff_role_filter_unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('staff_registry_count')), findsNothing);
    expect(find.text('Eve Retired'), findsNothing);

    // The retry reads the catalogue again, and the registry returns.
    repository.catalogueError = null;
    await tester.tap(find.byKey(const Key('staff_role_catalogue_retry_button')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('Clear filters resets every dimension and the search',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    await chooseFilter(
      tester,
      'staff_filter_role_dropdown',
      'Receptionist',
    );
    await chooseFilter(
      tester,
      'staff_filter_department_dropdown',
      'No department',
    );
    await chooseFilter(
      tester,
      'staff_filter_status_dropdown',
      'Inactive',
    );
    await tester.enterText(find.byType(TextField), 'eve');
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('staff_filter_clear_button')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 5 of 5 personnel'), findsOneWidget);
    expect(find.text('Ana Admin'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);
    expect(find.text('No personnel match these filters'), findsNothing);
    // The search box is a filter too, so it is cleared as well.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('the staff screen hands changes off to the web and offers no edit action',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    expect(find.byKey(const Key('staff_web_handoff_note')), findsOneWidget);
    expect(
      find.text(
        "Staff changes are made on the KlinikAid web admin so the account's sign-in, role and audit record update together.",
      ),
      findsOneWidget,
    );
    // No card carries an edit control.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byTooltip('Edit Staff Member'), findsNothing);

    // Tapping a card opens no edit sheet, so no status, role or save control
    // appears.
    await tester.tap(find.text('Ben Lab'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit_staff_save_button')), findsNothing);
    expect(find.byKey(const Key('edit_staff_active_switch')), findsNothing);
    expect(find.byKey(const Key('edit_staff_role_dropdown')), findsNothing);
    expect(find.text('Edit Staff Member'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });

  testWidgets('the registry is still read and filtered beside the hand-off note',
      (tester) async {
    final repository = useRepository();
    final provider = useProvider(repository);
    await provider.loadStaff();
    await provider.loadRbacCatalog();

    await pumpStaffScreen(tester, provider);

    expect(find.text('Showing 5 of 5 personnel'), findsOneWidget);
    expect(find.byKey(const Key('staff_web_handoff_note')), findsOneWidget);

    await chooseFilter(
      tester,
      'staff_filter_status_dropdown',
      'Inactive',
    );
    expect(find.text('Showing 1 of 5 personnel'), findsOneWidget);
    expect(find.text('Eve Retired'), findsOneWidget);
    expect(find.text('Ana Admin'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}

/// A repository that answers the two reads the registry screen makes.
class _FakeAdminRepository extends AdminRepository {
  _FakeAdminRepository({
    required SupabaseClient client,
    required this.staff,
    required this.catalogue,
  }) : super(client: client);

  List<Profile> staff;
  AdminRbacCatalog catalogue;
  Object? catalogueError;

  @override
  Future<List<Profile>> getStaffPersonnel() async => staff;

  @override
  Future<AdminRbacCatalog> getRbacCatalog() async {
    final error = catalogueError;
    if (error != null) throw error;
    return catalogue;
  }
}

/// The RAG repository is out of scope for these reads.
class _UnusedRag implements RagDocumentsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RAG access');
}
