import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/permissions/permission_constants.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'providers/specialist_provider.dart';

class SpecialistShell extends StatelessWidget {
  final Widget child;

  const SpecialistShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    SpecialistProvider? parentProvider;
    try {
      parentProvider = Provider.of<SpecialistProvider>(context, listen: false);
    } catch (_) {}

    return MultiProvider(
      providers: [
        if (parentProvider != null)
          ChangeNotifierProvider<SpecialistProvider>.value(value: parentProvider)
        else
          ChangeNotifierProvider<SpecialistProvider>(
            create: (context) {
              final provider = SpecialistProvider();
              if (auth.usesLegacyPermissionFallback ||
                  auth.hasPermission(PermissionConstants.specialistAnalytics)) {
                provider.loadDashboard();
              }
              if (auth.usesLegacyPermissionFallback ||
                  auth.hasPermission(PermissionConstants.specialistPatients)) {
                provider.loadDirectory();
              }
              return provider;
            },
          ),
      ],
      child: Scaffold(
        body: child,
        bottomNavigationBar: const _SpecialistBottomNavBar(),
      ),
    );
  }
}

class _SpecialistBottomNavBar extends StatelessWidget {
  const _SpecialistBottomNavBar();

  List<_SpecialistNavItem> _items(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final legacyFallback = auth.usesLegacyPermissionFallback;
    return [
      if (legacyFallback || auth.hasPermission(PermissionConstants.specialistAnalytics))
        const _SpecialistNavItem(
          path: '/specialist/dashboard',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: 'Dashboard',
        ),
      if (legacyFallback || auth.hasPermission(PermissionConstants.specialistPatients))
        const _SpecialistNavItem(
          path: '/specialist/patients',
          icon: Icons.people_outline_rounded,
          activeIcon: Icons.people_rounded,
          label: 'My Patients',
        ),
      const _SpecialistNavItem(
        path: '/specialist/profile',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile',
      ),
    ];
  }

  int _calculateSelectedIndex(BuildContext context, List<_SpecialistNavItem> items) {
    final String location = GoRouterState.of(context).matchedLocation;
    final index = items.indexWhere((item) => item.path == location);
    return index < 0 ? 0 : index;
  }

  void _onItemTapped(int index, BuildContext context, List<_SpecialistNavItem> items) {
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

class _SpecialistNavItem {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _SpecialistNavItem({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
