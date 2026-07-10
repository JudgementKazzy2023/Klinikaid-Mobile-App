import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'providers/department_provider.dart';

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

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location == '/department/records') return 1;
    if (location == '/department/profile') return 2;
    return 0; // /department/queue
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/department/queue');
        break;
      case 1:
        context.go('/department/records');
        break;
      case 2:
        context.go('/department/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => _onItemTapped(index, context),
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play_rounded),
            activeIcon: Icon(Icons.playlist_play_rounded),
            label: 'Daily Queue',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Records History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
