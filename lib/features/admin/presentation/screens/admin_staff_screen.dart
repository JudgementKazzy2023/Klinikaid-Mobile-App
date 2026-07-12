import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
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
                          value: _roleFilter,
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
          onSave: (isActive, role, department) async {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            try {
              if (isActive != staff.isActive) {
                await adminProvider.toggleStaffActive(staff.id, isActive);
              }
              if (role.toJsonValue() != staff.role.toJsonValue() || department?.toJsonValue() != staff.department?.toJsonValue()) {
                await adminProvider.editStaffRole(
                  staff.id,
                  role.toJsonValue(),
                  department?.toJsonValue(),
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
  final Future<void> Function(bool isActive, UserRole role, Department? department) onSave;

  const _EditStaffSheet({
    required this.staff,
    required this.isOwnAccount,
    required this.onSave,
  });

  @override
  State<_EditStaffSheet> createState() => _EditStaffSheetState();
}

class _EditStaffSheetState extends State<_EditStaffSheet> {
  late bool _isActive;
  late UserRole _role;
  Department? _department;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.staff.isActive;
    _role = widget.staff.role;
    _department = widget.staff.department;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showDept = _role == UserRole.departmentStaff;

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
          
          // Read-only info
          Text(
            'Name',
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 4),
          Text(
            widget.staff.fullName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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

          // Role dropdown
          const Text(
            'Role',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<UserRole>(
            key: const Key('edit_staff_role_dropdown'),
            value: _role,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: [
              UserRole.admin,
              UserRole.receptionist,
              UserRole.departmentStaff,
              UserRole.medicalSpecialist,
              UserRole.patient,
            ].map((role) {
              return DropdownMenuItem<UserRole>(
                value: role,
                child: Text(role.displayName),
              );
            }).toList(),
            onChanged: (widget.isOwnAccount || _isLoading)
                ? null
                : (val) {
                    if (val != null) {
                      setState(() {
                        _role = val;
                        if (_role != UserRole.departmentStaff) {
                          _department = null;
                        } else if (_department == null) {
                          _department = Department.laboratory; // default fallback if none set
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
              value: _department,
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
                  onPressed: (_isLoading || widget.isOwnAccount)
                      ? null
                      : () async {
                          setState(() {
                            _isLoading = true;
                          });
                          await widget.onSave(_isActive, _role, _department);
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
