import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/admin_rbac.dart';
import '../providers/admin_provider.dart';

class AdminRbacScreen extends StatefulWidget {
  const AdminRbacScreen({super.key});

  @override
  State<AdminRbacScreen> createState() => _AdminRbacScreenState();
}

class _AdminRbacScreenState extends State<AdminRbacScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AdminProvider>(context, listen: false);
      if (provider.rbacRoles.isEmpty && !provider.isRbacLoading) {
        provider.loadRbacCatalog();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AdminProvider>(context);

    if (provider.isRbacLoading && provider.rbacRoles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.rbacError != null && provider.rbacRoles.isEmpty) {
      return _buildErrorState(theme, provider.rbacError!, provider.loadRbacCatalog);
    }

    final permissionsByModule = <String, List<AdminPermission>>{};
    for (final permission in provider.rbacPermissions) {
      permissionsByModule.putIfAbsent(permission.module, () => []).add(permission);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: provider.loadRbacCatalog,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildReadOnlyNote(theme),
            const SizedBox(height: 16),
            Text(
              'Roles',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...provider.rbacRoles.map((role) => _RoleCard(role: role)),
            const SizedBox(height: 20),
            Text(
              'Permissions Catalog',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...permissionsByModule.entries.map((entry) {
              return _PermissionModuleTile(module: entry.key, permissions: entry.value);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyNote(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Role creation and editing is available on the web portal.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Failed to load role catalog: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final AdminRole role;

  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = role.isSystem ? theme.colorScheme.primary : theme.colorScheme.secondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    role.displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    role.isSystem ? 'SYSTEM' : 'CUSTOM',
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (role.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                role.description,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
            if (!role.isSystem && role.baseRole != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cloned from ${role.baseRole}',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '${role.permissions.length} granted permissions',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: role.permissions.map((permission) {
                return Chip(
                  label: Text(permission.name),
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 11),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionModuleTile extends StatelessWidget {
  final String module;
  final List<AdminPermission> permissions;

  const _PermissionModuleTile({
    required this.module,
    required this.permissions,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        module.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text('${permissions.length} permissions'),
      children: permissions.map((permission) {
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 12, right: 4),
          title: Text(permission.name, style: const TextStyle(fontSize: 13)),
          subtitle: permission.description.isEmpty
              ? null
              : Text(permission.description, style: const TextStyle(fontSize: 12)),
        );
      }).toList(),
    );
  }
}

