import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
import '../../domain/staff_filters.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/permissions/permission_constants.dart';
import '../../../../core/utils/role_formatter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AdminStaffScreen extends StatefulWidget {
  const AdminStaffScreen({super.key});

  @override
  State<AdminStaffScreen> createState() => _AdminStaffScreenState();
}

class _AdminStaffScreenState extends State<AdminStaffScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// The chosen role, `kStaffFilterAll` for every role.
  ///
  /// The web keeps the filter state in the query string, so a filtered view
  /// survives a reload and can be shared. The app has no address bar for the
  /// screen, so the state lives here; the rules that decide which rows a
  /// filter keeps are the same (see `staff_filters.dart`).
  String _roleFilter = kStaffFilterAll;

  /// The chosen department, `kStaffFilterAll` for every department.
  String _departmentFilter = kStaffFilterAll;

  /// The chosen status, `kStaffFilterAll` for both statuses.
  String _statusFilter = kStaffFilterAll;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// The signed-in account, when the screen is shown under one.
  ///
  /// The screen is also rendered in tests and previews without the auth
  /// provider above it, so the lookup is defensive: a missing provider means
  /// "no permissions are known here", not a crash.
  AuthProvider? _authProvider(BuildContext context) {
    try {
      return Provider.of<AuthProvider>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  /// Clears every filter dimension and the search box.
  ///
  /// The search box is a filter too, so one action clears the whole view: a
  /// "clear filters" that left the search term behind could still show an
  /// empty list and read as a broken button.
  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _roleFilter = kStaffFilterAll;
      _departmentFilter = kStaffFilterAll;
      _statusFilter = kStaffFilterAll;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);
    final auth = _authProvider(context);

    // The role catalogue is read under the permission the web requires
    // for the same read (`roles.read`). An account without it does not
    // ask for the catalogue at all.
    final canReadRoles =
        auth?.hasPermission(PermissionConstants.rolesRead) ?? true;

    if (!provider.isRbacLoaded &&
        provider.rbacRoles.isEmpty &&
        !provider.isRbacLoading &&
        provider.rbacError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (!canReadRoles) return;
          Provider.of<AdminProvider>(context, listen: false).loadRbacCatalog();
        }
      });
    }

    if (provider.isStaffLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.staffError != null) {
      return _buildErrorState(context, provider.staffError!, () => provider.loadStaff());
    }

    // The state of the role catalogue decides whether a role filter can be
    // applied at all. A profile created before `role_id` existed is
    // recognised by its legacy role text, and only the catalogue says which
    // text belongs to which role. A failed catalogue read is therefore not
    // the same as a slow one: without the catalogue the role filter cannot
    // be applied completely, so the filtered table and its count are not
    // shown at all rather than shown short.
    final catalogueFailed = provider.rbacError != null;
    final catalogueSettled =
        provider.isRbacLoaded || catalogueFailed || !canReadRoles;
    final roleFilterSelected = _roleFilter != kStaffFilterAll;

    // A role the catalogue does not know (deleted on the web while it was
    // selected) keeps its filter, the way the web keeps it: "no match" is
    // truer than quietly showing every staff member under that role's name.
    final effectiveRoleFilter = _roleFilter;

    final roleFilterPending = roleFilterSelected && !catalogueSettled;
    final roleFilterUnavailable =
        roleFilterSelected && (catalogueFailed || !canReadRoles);

    final filters = buildStaffFilters(
      roleId: effectiveRoleFilter == kStaffFilterAll
          ? null
          : effectiveRoleFilter,
      department: parseStaffDepartmentFilter(_departmentFilter),
      status: parseStaffStatusFilter(_statusFilter),
      catalogue: provider.rbacRoles,
    );
    // The filters run on the client over the whole registry, the way the
    // web runs them: the registry is read completely (the read pages over
    // the server's row cap, see `AdminRepository.getStaffPersonnel`) and the
    // filter runs over every row of it, so a match past the first page is
    // never lost and the count is the count of the whole registry.
    final filteredStaff =
        filterStaff(provider.staffList, filters, search: _searchQuery);

    // The clear action is offered when there is something to clear. A role
    // filter that cannot be applied is something to clear as well: the
    // operator has to be able to leave the view the catalogue broke.
    final filtersActive = filters.hasActiveFilters ||
        _searchQuery.trim().isNotEmpty ||
        roleFilterUnavailable;
    final registryReady = !roleFilterPending && !roleFilterUnavailable;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Search & Filter Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWebHandoffNote(theme),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by staff name or role...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // One selector per dimension, all combinable with each
                  // other and with the search above.
                  _buildFilterBar(
                    theme: theme,
                    provider: provider,
                    effectiveRoleFilter: effectiveRoleFilter,
                    catalogueFailed: catalogueFailed,
                    filtersActive: filtersActive,
                  ),
                  if (provider.rbacError != null) ...[
                    const SizedBox(height: 8),
                    _buildCatalogueError(theme, provider),
                  ],
                  const SizedBox(height: 8),
                  // Personnel count: the exact number of staff the server
                  // holds, and how many of them the current filters keep.
                  if (registryReady)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Showing ${filteredStaff.length} of ${provider.staffTotal} personnel',
                        key: const Key('staff_registry_count'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Personnel List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.loadStaff(),
                child: roleFilterPending
                    ? _buildPendingState(theme)
                    : roleFilterUnavailable
                        ? _buildRoleFilterUnavailableState(theme)
                        : filteredStaff.isEmpty
                            ? _buildEmptyState(
                                theme,
                                registryEmpty: provider.staffList.isEmpty,
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                itemCount: filteredStaff.length,
                                itemBuilder: (context, index) {
                                  final staff = filteredStaff[index];
                                  return _buildStaffCard(context, staff);
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The filter bar: one selector per dimension, the clear action and the
  /// count.
  ///
  /// The role list comes from the live role catalogue the screen already
  /// reads, so a custom role created on the web is filterable like any
  /// other; nothing about the catalogue is hard-coded.
  Widget _buildFilterBar({
    required ThemeData theme,
    required AdminProvider provider,
    required String effectiveRoleFilter,
    required bool catalogueFailed,
    required bool filtersActive,
  }) {
    // The roles a staff member may hold: the patient role is not one of them.
    final assignableRoles = provider.rbacRoles
        .where((role) => !(role.isSystem && role.name == 'patient'))
        .toList();

    final roleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: kStaffFilterAll,
        child: Text('All roles'),
      ),
      for (final role in assignableRoles)
        DropdownMenuItem<String>(
          value: role.id,
          child: Text(
            staffRoleFilterLabel(role),
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    // The chosen role stays in the picker even when the catalogue does not
    // offer it, so the picker never shows a bare id for a filter that is
    // applied.
    if (effectiveRoleFilter != kStaffFilterAll &&
        !assignableRoles.any((role) => role.id == effectiveRoleFilter)) {
      roleItems.add(DropdownMenuItem<String>(
        value: effectiveRoleFilter,
        child: Text(
          catalogueFailed
              ? 'Role unavailable'
              : provider.isRbacLoaded
                  ? 'Unknown role'
                  : 'Loading roles...',
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }

    final departmentItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: kStaffFilterAll,
        child: Text('All departments'),
      ),
      for (final option in StaffDepartmentFilter.values)
        DropdownMenuItem<String>(
          value: option.value,
          child: Text(option.label),
        ),
    ];

    final statusItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: kStaffFilterAll,
        child: Text('All statuses'),
      ),
      for (final option in StaffStatusFilter.values)
        DropdownMenuItem<String>(
          value: option.value,
          child: Text(option.label),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _buildFilterField(
              theme: theme,
              label: 'Role',
              width: 190.0,
              child: _buildFilterDropdown(
                theme: theme,
                dropdownKey: const Key('staff_filter_role_dropdown'),
                value: effectiveRoleFilter,
                items: roleItems,
                onChanged: (value) {
                  setState(() {
                    _roleFilter = value ?? kStaffFilterAll;
                  });
                },
              ),
            ),
            _buildFilterField(
              theme: theme,
              label: 'Department',
              width: 170.0,
              child: _buildFilterDropdown(
                theme: theme,
                dropdownKey: const Key('staff_filter_department_dropdown'),
                value: _departmentFilter,
                items: departmentItems,
                onChanged: (value) {
                  setState(() {
                    _departmentFilter = value ?? kStaffFilterAll;
                  });
                },
              ),
            ),
            _buildFilterField(
              theme: theme,
              label: 'Status',
              width: 130.0,
              child: _buildFilterDropdown(
                theme: theme,
                dropdownKey: const Key('staff_filter_status_dropdown'),
                value: _statusFilter,
                items: statusItems,
                onChanged: (value) {
                  setState(() {
                    _statusFilter = value ?? kStaffFilterAll;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('staff_filter_clear_button'),
          onPressed: filtersActive ? _clearFilters : null,
          icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
          label: const Text('Clear filters'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
          ),
        ),
      ],
    );
  }

  /// One labelled filter selector.
  Widget _buildFilterField({
    required ThemeData theme,
    required String label,
    required double width,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  /// The picker of one filter dimension.
  Widget _buildFilterDropdown({
    required ThemeData theme,
    required Key dropdownKey,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: DropdownButton<String>(
        key: dropdownKey,
        value: value,
        isExpanded: true,
        isDense: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(12),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  /// The banner of a failed role catalogue read.
  ///
  /// The catalogue is not optional data: it decides which roles may be
  /// granted, so a failed read must never be presented as an empty
  /// catalogue.
  Widget _buildCatalogueError(ThemeData theme, AdminProvider provider) {
    return Container(
      key: const Key('staff_role_catalogue_error'),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The role catalogue could not be loaded, so the role filter '
              'cannot be applied.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            key: const Key('staff_role_catalogue_retry_button'),
            onPressed: () => provider.loadRbacCatalog(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// The state of a registry whose role filter is still waiting for the
  /// catalogue.
  Widget _buildPendingState(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 48.0),
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Loading personnel registry...',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  /// The state of a registry whose role filter cannot be applied.
  ///
  /// Without the catalogue a profile created before `role_id` existed cannot
  /// be told from one that carries another role, so the table is not shown
  /// under that filter: a short table would read as authoritative while
  /// staff were missing from it.
  Widget _buildRoleFilterUnavailableState(ThemeData theme) {
    return ListView(
      key: const Key('staff_role_filter_unavailable'),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
      children: [
        Icon(
          Icons.filter_alt_off_rounded,
          size: 48,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 16),
        Text(
          'The role filter cannot be applied',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The role catalogue could not be loaded, so staff created before '
          'roles existed cannot be told apart from staff with another role. '
          'Clear the filters to see the whole registry.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            key: const Key('staff_role_filter_unavailable_clear_button'),
            onPressed: _clearFilters,
            child: const Text('Clear filters'),
          ),
        ),
      ],
    );
  }

  /// The note where the staff controls used to be.
  ///
  /// A status, role or profile change has to update the sign-in account, its
  /// sessions and the audit record together. Only the web does all three, so
  /// the app points there rather than offer a change it cannot finish.
  Widget _buildWebHandoffNote(ThemeData theme) {
    return Container(
      key: const Key('staff_web_handoff_note'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Staff changes are made on the KlinikAid web admin so the account's sign-in, role and audit record update together.",
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(BuildContext context, Profile staff) {
    final theme = Theme.of(context);
    final initials = staff.fullName.isNotEmpty
        ? staff.fullName.substring(0, 1).toUpperCase()
        : 'S';

    final roleLabel = roleDisplayLabel(staff.role, staff.department);
    final positionTitles = _parseEmployeeType(staff.employeeType);

    return Opacity(
      opacity: staff.isActive ? 1.0 : 0.65,
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.only(bottom: 12.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: staff.isActive
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.05),
                child: Text(
                  initials,
                  style: TextStyle(
                    color: staff.isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        roleLabel.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (positionTitles.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: positionTitles.map((title) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              title,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: staff.isActive ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          staff.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _parseEmployeeType(String? employeeType) {
    if (employeeType == null || employeeType.trim().isEmpty) return [];
    return employeeType
        .split('|')
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toList();
  }

  /// The state of a registry that holds no staff member under the filters.
  ///
  /// An empty registry and an empty filtered view are different facts, so
  /// they read differently: the first says no account exists, the second
  /// says the filters keep nothing.
  Widget _buildEmptyState(ThemeData theme, {required bool registryEmpty}) {
    final title =
        registryEmpty ? 'No personnel found' : 'No personnel match these filters';
    final subtitle = registryEmpty
        ? 'No staff account has been created yet.'
        : 'Try a different role, department or status, or clear the filters.';
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
      children: [
        Icon(
          Icons.people_outline,
          size: 48,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (!registryEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, String error, VoidCallback onRetry) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load staff list: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
