import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
import '../../domain/admin_rbac.dart';
import '../../../../core/models/profile.dart';
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
  String _roleFilter = 'All';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);
    if (provider.rbacRoles.isEmpty && !provider.isRbacLoading && provider.rbacError == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
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

    final filteredStaff = provider.staffList.where((profile) {
      final name = profile.fullName.toLowerCase();
      final roleStr = profile.role.displayName.toLowerCase();
      
      final matchesSearch = name.contains(_searchQuery) || roleStr.contains(_searchQuery);
      final matchesRole = _roleFilter == 'All' || profile.role.displayName == _roleFilter;

      return matchesSearch && matchesRole;
    }).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Search & Filter Header
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
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
                  Row(
                    children: [
                      const Text(
                        'Filter Role:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _roleFilter,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: ['All', 'Receptionist', 'Department Staff', 'Medical Specialist'].map((role) {
                            return DropdownMenuItem<String>(
                              value: role,
                              child: Text(role, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _roleFilter = val;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),



            // Personnel List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.loadStaff(),
                child: filteredStaff.isEmpty
                    ? _buildEmptyState(theme)
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

  void _showEditStaffSheet(BuildContext context, Profile staff) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    final currentUserId = authProvider.user?.id;
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
            try {
              if (isActive != staff.isActive) {
                await adminProvider.toggleStaffActive(staff.id, isActive);
              }
              final roleChanged = selectedRole.id != staff.roleId ||
                  selectedRole.legacyProfileRole != staff.role.toJsonValue();
              final profileChanged = fullName.trim() != staff.fullName.trim() ||
                  employeeType.trim() != (staff.employeeType ?? '').trim() ||
                  department?.toJsonValue() != staff.department?.toJsonValue();
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

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No personnel found matching filters.',
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
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
              'Role catalog unavailable. Pull to refresh Staff Management.',
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
            'Account creation and password resets are managed on the web portal.',
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
