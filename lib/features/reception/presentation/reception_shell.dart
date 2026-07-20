import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/permissions/permission_constants.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../data/reception_repository.dart';
import 'providers/reception_queue_provider.dart';
import 'providers/reception_dashboard_provider.dart';

class ReceptionShell extends StatelessWidget {
  final Widget child;

  const ReceptionShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    ReceptionRepository repo;
    try {
      repo = Provider.of<ReceptionRepository>(context, listen: false);
    } catch (_) {
      repo = ReceptionRepository();
    }

    ReceptionQueueProvider? parentQueue;
    try {
      parentQueue = Provider.of<ReceptionQueueProvider>(context, listen: false);
    } catch (_) {}

    ReceptionDashboardProvider? parentDashboard;
    try {
      parentDashboard = Provider.of<ReceptionDashboardProvider>(context, listen: false);
    } catch (_) {}

    return MultiProvider(
      providers: [
        Provider<ReceptionRepository>.value(
          value: repo,
        ),
        if (parentQueue != null)
          ChangeNotifierProvider<ReceptionQueueProvider>.value(value: parentQueue)
        else
          ChangeNotifierProvider<ReceptionQueueProvider>(
            create: (context) => ReceptionQueueProvider(repository: repo)..loadSubmissions(),
          ),
        if (parentDashboard != null)
          ChangeNotifierProvider<ReceptionDashboardProvider>.value(value: parentDashboard)
        else
          ChangeNotifierProvider<ReceptionDashboardProvider>(
            create: (context) => ReceptionDashboardProvider(repository: repo)..loadDashboard(),
          ),
      ],
      child: Scaffold(
        body: child,
        bottomNavigationBar: const _ReceptionBottomNavBar(),
      ),
    );
  }
}

class _ReceptionBottomNavBar extends StatelessWidget {
  const _ReceptionBottomNavBar();

  List<_ReceptionNavItem> _items(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final canQueue = auth.usesLegacyPermissionFallback ||
        auth.hasAllPermissions(PermissionConstants.receptionQueue);
    return [
      if (canQueue)
        const _ReceptionNavItem(
          path: '/reception/dashboard',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: 'Dashboard',
        ),
      if (canQueue)
        const _ReceptionNavItem(
          path: '/reception/queue',
          icon: Icons.list_alt_outlined,
          activeIcon: Icons.list_alt_rounded,
          label: 'Queue',
        ),
      const _ReceptionNavItem(
        path: '/reception/profile',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile',
      ),
    ];
  }

  int _calculateSelectedIndex(BuildContext context, List<_ReceptionNavItem> items) {
    final String location = GoRouterState.of(context).matchedLocation;
    final index = items.indexWhere((item) => item.path == location);
    return index < 0 ? 0 : index;
  }

  void _onItemTapped(int index, BuildContext context, List<_ReceptionNavItem> items) {
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

class _ReceptionNavItem {
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _ReceptionNavItem({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
