import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
import '../../domain/admin_rbac.dart';
import '../../domain/staff_filters.dart';
import '../../../../core/models/profile.dart';
import '../../../../core/permissions/permission_constants.dart';
import '../../../../core/permissions/web_operation_permissions.dart';
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

    // A role the catalogue does not know is dropped, so the registry shows
    // every staff member instead of an unexplained empty list.
    final catalogueKnowsRole =
        provider.rbacRoles.any((role) => role.id == _roleFilter);
    final effectiveRoleFilter =
        provider.isRbacLoaded && roleFilterSelected && !catalogueKnowsRole
            ? kStaffFilterAll
            : _roleFilter;

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
          catalogueFailed ? 'Role unavailable' : 'Loading roles...',
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

  void _showEditStaffSheet(BuildContext context, Profile staff) {
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final authProvider = _authProvider(context);
    final currentUserId = authProvider?.user?.id;
    final isOwnAccount = staff.id == currentUserId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _EditStaffSheet(
          staff: staff,
          isOwnAccount: isOwnAccount,
          roles: adminProvider.rbacRoles,
          rolesLoading: adminProvider.isRbacLoading,
          onSave: (isActive, selectedRole, department, fullName, employeeType) async {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            final roleChanged = selectedRole.id != staff.roleId ||
                selectedRole.legacyProfileRole != staff.role.toJsonValue();
            final profileChanged = fullName.trim() != staff.fullName.trim() ||
                employeeType.trim() != (staff.employeeType ?? '').trim() ||
                department?.toJsonValue() != staff.department?.toJsonValue();
            final statusChanged = isActive != staff.isActive;

            // The preflight runs before the first side effect and asks for
            // every permission the web requires for the same write: the status
            // write needs `staff.manage` and `profiles.manage` (web:
            // `PATCH /api/admin/staff/[id]`), the profile write needs
            // `staff.manage`, `roles.read` and `profiles.manage` (web:
            // `PUT /api/admin/staff/[id]`).
            //
            // This is a client-side preflight only. The shared backend checks
            // the same permissions again on every request, and the server
            // stays the authority.
            final required = <String>[
              if (statusChanged) ...WebOperationPermissions.staffStatusUpdate,
              if (roleChanged || profileChanged)
                ...WebOperationPermissions.staffProfileUpdate,
            ];
            if (required.isNotEmpty &&
                authProvider != null &&
                !authProvider.hasAllPermissions(required)) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'This account cannot make that change. It needs: ${required.join(', ')}.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            try {
              if (statusChanged) {
                await adminProvider.toggleStaffActive(staff.id, isActive);
              }
              if (roleChanged || profileChanged) {
                await adminProvider.editStaffProfile(
                  userId: staff.id,
                  fullName: fullName,
                  selectedRole: selectedRole,
                  department: department?.toJsonValue(),
                  employeeType: employeeType,
                );
              }
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Staff updated successfully'),
                  backgroundColor: Colors.green,
                ),
              );
              if (context.mounted) {
                Navigator.pop(context);
              }
            } catch (e) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('Failed to update staff: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        );
      },
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
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEditStaffSheet(context, staff),
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
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: theme.colorScheme.primary),
                  tooltip: 'Edit Staff Member',
                  onPressed: () => _showEditStaffSheet(context, staff),
                ),
              ],
            ),
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

class _EditStaffSheet extends StatefulWidget {
  final Profile staff;
  final bool isOwnAccount;
  final List<AdminRole> roles;
  final bool rolesLoading;
  final Future<void> Function(
    bool isActive,
    AdminRole selectedRole,
    Department? department,
    String fullName,
    String employeeType,
  ) onSave;

  const _EditStaffSheet({
    required this.staff,
    required this.isOwnAccount,
    required this.roles,
    required this.rolesLoading,
    required this.onSave,
  });

  @override
  State<_EditStaffSheet> createState() => _EditStaffSheetState();
}

class _EditStaffSheetState extends State<_EditStaffSheet> {
  late bool _isActive;
  AdminRole? _selectedRole;
  late TextEditingController _fullNameController;
  late TextEditingController _positionController;
  late List<String> _positionTitles;
  Department? _department;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.staff.isActive;
    _selectedRole = _findInitialRole(widget.roles);
    _fullNameController = TextEditingController(text: widget.staff.fullName);
    _positionController = TextEditingController();
    _positionTitles = _parsePositionTitles(widget.staff.employeeType);
    _department = widget.staff.department;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _EditStaffSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedRole == null && widget.roles.isNotEmpty) {
      _selectedRole = _findInitialRole(widget.roles);
    }
  }

  AdminRole? _findInitialRole(List<AdminRole> roles) {
    if (roles.isEmpty) return null;
    if (widget.staff.roleId != null) {
      for (final role in roles) {
        if (role.id == widget.staff.roleId) return role;
      }
    }
    for (final role in roles) {
      if (role.isSystem && role.name == widget.staff.role.toJsonValue()) return role;
    }
    for (final role in roles) {
      if (role.legacyProfileRole == widget.staff.role.toJsonValue()) return role;
    }
    return roles.first;
  }

  List<String> _parsePositionTitles(String? employeeType) {
    if (employeeType == null || employeeType.trim().isEmpty) return [];
    return employeeType
        .split('|')
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList();
  }

  String _serializePositionTitles() {
    return _positionTitles.map((title) => title.trim()).where((title) => title.isNotEmpty).join('|');
  }

  void _addPositionTitle() {
    final title = _positionController.text.trim();
    if (title.isEmpty) return;
    if (!_positionTitles.any((existing) => existing.toLowerCase() == title.toLowerCase())) {
      setState(() {
        _positionTitles.add(title);
      });
    }
    _positionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRole = _selectedRole;
    final showDept = selectedRole?.usesDepartment == true;
    final rolesUnavailable = selectedRole == null;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Edit Staff Member',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          
          Text(
            'Name',
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const Key('edit_staff_full_name_field'),
            controller: _fullNameController,
            enabled: !widget.isOwnAccount && !_isLoading,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'User ID',
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 4),
          Text(
            widget.staff.id,
            style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          ),
          const Divider(height: 32),

          // Self-lockout warning
          if (widget.isOwnAccount) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade700.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manage your own account via Profile / web portal.',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Active Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Switch(
                key: const Key('edit_staff_active_switch'),
                value: _isActive,
                onChanged: widget.isOwnAccount
                    ? null
                    : (val) {
                        setState(() {
                          _isActive = val;
                        });
                      },
              ),
            ],
          ),
          if (!_isActive && !widget.isOwnAccount) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade700.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade700.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.orange.shade800, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Marked inactive. The user's current session remains valid until it expires; for immediate sign-out, use the web portal.",
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          const Text(
            'Position(s) / Title(s)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('position_title_input'),
                  controller: _positionController,
                  enabled: !widget.isOwnAccount && !_isLoading,
                  decoration: InputDecoration(
                    hintText: 'Add a title',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (_) => _addPositionTitle(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const Key('add_position_title_button'),
                onPressed: (widget.isOwnAccount || _isLoading) ? null : _addPositionTitle,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add title',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_positionTitles.isEmpty)
            Text(
              'No position titles added.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _positionTitles.map((title) {
                return Chip(
                  key: Key('position_title_chip_$title'),
                  label: Text(title),
                  onDeleted: (widget.isOwnAccount || _isLoading)
                      ? null
                      : () {
                          setState(() {
                            _positionTitles.remove(title);
                          });
                        },
                );
              }).toList(),
            ),
          const SizedBox(height: 6),
          Text(
            'Optional display labels only. System role still controls access permissions.',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),

          // Role dropdown
          const Text(
            'Role',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (rolesUnavailable && widget.rolesLoading)
            const Center(child: CircularProgressIndicator())
          else if (rolesUnavailable)
            Text(
              'Role catalog unavailable. Changing the role of a staff member needs the '
              'roles.read permission; pull to refresh Staff Management.',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            )
          else
          DropdownButtonFormField<AdminRole>(
            key: const Key('edit_staff_role_dropdown'),
            initialValue: selectedRole,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: widget.roles.map((role) {
              return DropdownMenuItem<AdminRole>(
                value: role,
                child: Text(
                  '${role.displayName} (${role.isSystem ? 'SYSTEM' : 'CUSTOM'})',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (widget.isOwnAccount || _isLoading)
                ? null
                : (val) {
                    if (val != null) {
                      setState(() {
                        _selectedRole = val;
                        if (!val.usesDepartment) {
                          _department = null;
                        } else {
                          _department ??= Department.laboratory; // default fallback if none set
                        }
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),

          // Department dropdown
          if (showDept) ...[
            const Text(
              'Department',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<Department>(
              key: const Key('edit_staff_dept_dropdown'),
              initialValue: _department,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: Department.values.map((dept) {
                return DropdownMenuItem<Department>(
                  value: dept,
                  child: Text(dept.name.toUpperCase()),
                );
              }).toList(),
              onChanged: (widget.isOwnAccount || _isLoading)
                  ? null
                  : (val) {
                      if (val != null) {
                        setState(() {
                          _department = val;
                        });
                      }
                    },
            ),
            const SizedBox(height: 16),
          ],

          const Divider(height: 24),
          
          // Footnote
          Text(
            'This form changes the staff profile. The sign-in account, its role '
            'mirror and the audit trail are updated on the web portal, together with '
            'account creation and password resets.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Save / Cancel buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  key: const Key('edit_staff_save_button'),
                  onPressed: (_isLoading || widget.isOwnAccount || rolesUnavailable)
                      ? null
                      : () async {
                          setState(() {
                            _isLoading = true;
                          });
                          await widget.onSave(
                            _isActive,
                            selectedRole,
                            _department,
                            _fullNameController.text,
                            _serializePositionTitles(),
                          );
                          if (mounted) {
                            setState(() {
                              _isLoading = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
