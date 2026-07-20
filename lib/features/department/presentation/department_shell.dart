import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'providers/department_provider.dart';
import '../../../core/permissions/permission_constants.dart';

class DepartmentShell extends StatelessWidget {
  final Widget child;

  const DepartmentShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final department = authProvider.profile?.department?.toJsonValue() ?? 'laboratory';

    DepartmentProvider? parentProvider;
    try {
      parentProvider = Provider.of<DepartmentProvider>(context, listen: false);
    } catch (_) {}

    return MultiProvider(
      providers: [
        if (parentProvider != null)
          ChangeNotifierProvider<DepartmentProvider>.value(value: parentProvider)
        else
          ChangeNotifierProvider<DepartmentProvider>(
            create: (context) => DepartmentProvider(department)..loadDashboard(),
          ),
      ],
      child: Scaffold(
        body: child,
        bottomNavigationBar: const _DepartmentBottomNavBar(),
      ),
    );
  }
}

class _DepartmentBottomNavBar extends StatelessWidget {
  const _DepartmentBottomNavBar();

  List<_DepartmentNavItem> _items(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final canRecords = auth.usesLegacyPermissionFallback ||
        auth.hasAnyPermission(PermissionConstants.departmentRecordsAny);
    return [
      if (canRecords)
        const _DepartmentNavItem(
          path: '/department/queue',
          icon: Icons.playlist_play_rounded,
          activeIcon: Icons.playlist_play_rounded,
          label: 'Daily Queue',
        ),
      if (canRecords)
        const _DepartmentNavItem(
          path: '/department/records',
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          label: 'Records History',
        ),
      const _DepartmentNavItem(
        path: '/department/profile',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile',
      ),
    ];
  }

  int _calculateSelectedIndex(BuildContext context, List<_DepartmentNavItem> items) {
    final String location = GoRouterState.of(context).matchedLocation;
    final index = items.indexWhere((item) => item.path == location);
    return index < 0 ? 0 : index;
  }

  void _onItemTapped(int index, BuildContext context, List<_DepartmentNavItem> items) {
    context.go(items[index].path);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    final selectedIndex = _calculateSelectedIndex(context, items);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => _onItemTapped(index, context, items),
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: items
            .map(
              (item) => BottomNavigationBarItem(
                icon: Icon(item.icon),
                activeIcon: Icon(item.activeIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DepartmentNavItem {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _DepartmentNavItem({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
