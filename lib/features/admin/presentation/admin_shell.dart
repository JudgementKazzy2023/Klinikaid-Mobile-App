import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'providers/admin_provider.dart';

class AdminShell extends StatelessWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location == '/admin/staff') return 1;
    if (location == '/admin/queue') return 2;
    if (location == '/admin/records') return 3;
    if (location == '/admin/logs') return 4;
    if (location == '/admin/rag') return 5;
    if (location == '/admin/rbac') return 6;
    if (location == '/admin/profile') return 7;
    return 0; // /admin/dashboard
  }

  void _onItemTapped(int index, BuildContext context) {
    // Close the drawer if it's open
    Navigator.of(context).pop();

    switch (index) {
      case 0:
        context.go('/admin/dashboard');
        break;
      case 1:
        context.go('/admin/staff');
        break;
      case 2:
        context.go('/admin/queue');
        break;
      case 3:
        context.go('/admin/records');
        break;
      case 4:
        context.go('/admin/logs');
        break;
      case 5:
        context.go('/admin/rag');
        break;
      case 6:
        context.go('/admin/rbac');
        break;
      case 7:
        context.go('/admin/profile');
        break;
    }
  }

  String _getScreenTitle(int selectedIndex) {
    switch (selectedIndex) {
      case 0:
        return 'Admin Dashboard';
      case 1:
        return 'Staff Management';
      case 2:
        return 'Reception Queue';
      case 3:
        return 'Clinical Records';
      case 4:
        return 'System & Audit Logs';
      case 5:
        return 'RAG Knowledge Base';
      case 6:
        return 'Role & Access Management';
      case 7:
        return 'My Profile';
      default:
        return 'Admin Portal';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final selectedIndex = _calculateSelectedIndex(context);
    final screenTitle = _getScreenTitle(selectedIndex);

    AdminProvider? parentProvider;
    try {
      parentProvider = Provider.of<AdminProvider>(context, listen: false);
    } catch (_) {}

    return MultiProvider(
      providers: [
        if (parentProvider != null)
          ChangeNotifierProvider<AdminProvider>.value(value: parentProvider)
        else
          ChangeNotifierProvider<AdminProvider>(
            create: (context) => AdminProvider()
              ..loadDashboard()
              ..loadStaff()
              ..loadQueue()
              ..loadDepartmentRecords('laboratory')
              ..loadDepartmentQueue('laboratory')
              ..loadSystemEvents()
              ..loadChatbotAudit()
              ..loadApiCost()
              ..loadRag()
              ..loadRbacCatalog(),
          ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            screenTitle,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: theme.scaffoldBackgroundColor,
          iconTheme: IconThemeData(color: theme.colorScheme.primary),
        ),
        drawer: Drawer(
          backgroundColor: theme.colorScheme.surface,
          child: Column(
            children: [
              // Drawer Header
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: theme.colorScheme.onPrimary,
                  child: Text(
                    authProvider.profile?.fullName.isNotEmpty == true
                        ? authProvider.profile!.fullName.substring(0, 1).toUpperCase()
                        : 'A',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                accountName: Text(
                  authProvider.profile?.fullName ?? 'Administrator',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                accountEmail: Text(
                  authProvider.user?.email ?? 'admin@klinikaid.com',
                  style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.8)),
                ),
              ),
              // Navigation Options
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildDrawerItem(
                      context: context,
                      index: 0,
                      icon: Icons.dashboard_outlined,
                      activeIcon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 1,
                      icon: Icons.people_outline_rounded,
                      activeIcon: Icons.people_rounded,
                      label: 'Staff Management',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 2,
                      icon: Icons.list_alt_outlined,
                      activeIcon: Icons.list_alt_rounded,
                      label: 'Reception Queue',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 3,
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long_rounded,
                      label: 'Clinical Records',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 4,
                      icon: Icons.analytics_outlined,
                      activeIcon: Icons.analytics_rounded,
                      label: 'System & Audit Logs',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 5,
                      icon: Icons.folder_open_outlined,
                      activeIcon: Icons.folder_rounded,
                      label: 'RAG Knowledge',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 6,
                      icon: Icons.admin_panel_settings_outlined,
                      activeIcon: Icons.admin_panel_settings_rounded,
                      label: 'Role & Access',
                      selectedIndex: selectedIndex,
                    ),
                    _buildDrawerItem(
                      context: context,
                      index: 7,
                      icon: Icons.person_outline_rounded,
                      activeIcon: Icons.person_rounded,
                      label: 'My Profile',
                      selectedIndex: selectedIndex,
                    ),
                  ],
                ),
              ),
              // Footer / Sign Out Button
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                title: Text(
                  'Sign Out',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await authProvider.signOut();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        body: SafeArea(child: child),
      ),
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int selectedIndex,
  }) {
    final theme = Theme.of(context);
    final isSelected = index == selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: isSelected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
        leading: Icon(
          isSelected ? activeIcon : icon,
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        onTap: () => _onItemTapped(index, context),
      ),
    );
  }
}
