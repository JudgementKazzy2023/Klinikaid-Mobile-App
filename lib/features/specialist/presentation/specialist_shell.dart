import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'providers/specialist_provider.dart';

class SpecialistShell extends StatelessWidget {
  final Widget child;

  const SpecialistShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
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
            create: (context) => SpecialistProvider()..loadDashboard()..loadDirectory(),
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

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location == '/specialist/patients') return 1;
    if (location == '/specialist/profile') return 2;
    return 0; // /specialist/dashboard
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/specialist/dashboard');
        break;
      case 1:
        context.go('/specialist/patients');
        break;
      case 2:
        context.go('/specialist/profile');
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
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline_rounded),
            activeIcon: Icon(Icons.people_rounded),
            label: 'My Patients',
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
