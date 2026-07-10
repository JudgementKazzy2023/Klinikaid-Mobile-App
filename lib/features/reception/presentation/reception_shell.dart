import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../data/reception_repository.dart';
import 'providers/reception_queue_provider.dart';

class ReceptionShell extends StatelessWidget {
  final Widget child;

  const ReceptionShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ReceptionRepository>(
          create: (_) => ReceptionRepository(),
        ),
        ChangeNotifierProvider<ReceptionQueueProvider>(
          create: (context) => ReceptionQueueProvider(
            repository: Provider.of<ReceptionRepository>(context, listen: false),
          )..loadSubmissions(),
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

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location == '/reception/queue') return 1;
    if (location == '/reception/profile') return 2;
    return 0; // /reception/dashboard
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/reception/dashboard');
        break;
      case 1:
        context.go('/reception/queue');
        break;
      case 2:
        context.go('/reception/profile');
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
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt_rounded),
            label: 'Queue',
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
