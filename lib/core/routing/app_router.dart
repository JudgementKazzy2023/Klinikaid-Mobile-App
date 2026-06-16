import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/consent_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/profile_screen.dart';
import '../../features/documents/presentation/screens/submit_document_screen.dart';
import '../../features/records/presentation/screens/records_screen.dart';
import '../../features/records/presentation/providers/records_provider.dart';
import '../../features/queue/presentation/screens/queue_screen.dart';
import '../../features/queue/presentation/providers/queue_provider.dart';
import '../../features/documents/presentation/screens/document_status_screen.dart';
import '../../features/documents/presentation/providers/document_status_provider.dart';
import '../../features/chatbot/presentation/screens/chatbot_screen.dart';
import '../../features/chatbot/presentation/providers/chatbot_provider.dart';
import '../../features/dashboard/presentation/providers/dashboard_provider.dart';
import '../../features/documents/presentation/providers/document_submission_provider.dart';
import '../cache/local_database.dart';
import '../models/profile.dart';
import '../../features/staff/presentation/screens/reception_home_screen.dart';
import '../../features/staff/presentation/screens/department_home_screen.dart';
import '../../features/staff/presentation/screens/specialist_home_screen.dart';

/// AppRouter defines the structural gating/redirection rules for the application.
class AppRouter {
  final AuthProvider authProvider;

  AppRouter(this.authProvider);

  late final router = GoRouter(
    initialLocation: '/',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final isAuthenticated = authProvider.isAuthenticated;
      final hasConsented = authProvider.hasConsented;
      final isOnboarded = authProvider.isOnboarded;
      final isLoading = authProvider.isLoading;
      final role = authProvider.profile?.role;

      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';
      final isConsenting = state.matchedLocation == '/consent';
      final isOnboarding = state.matchedLocation == '/onboarding';

      // 1. If auth is loading, do not perform redirects yet (let it show loading states)
      if (isLoading) {
        return null;
      }

      // 2. Unauthenticated User gating
      if (!isAuthenticated) {
        if (isLoggingIn || isRegistering) {
          return null; // Allow login or register screen
        }
        return '/login';
      }

      // 3. Admin Account blocking
      if (role == UserRole.admin) {
        return '/login';
      }

      // 4. Role-based routing
      if (role == UserRole.patient) {
        // Enforce Privacy Consent Gate (RA 10173)
        if (!hasConsented) {
          if (isConsenting) {
            return null; // Stay on consent screen
          }
          return '/consent';
        }

        // Onboarding Gate (Patient record check)
        if (!isOnboarded) {
          if (isOnboarding) {
            return null; // Stay on onboarding screen
          }
          return '/onboarding';
        }

        // Authenticated, Consented & Onboarded Patient redirection
        if (isLoggingIn || isRegistering || isConsenting || isOnboarding || state.matchedLocation == '/') {
          return '/patient';
        }

        // Patient trying to access staff routes is redirected to /patient
        if (state.matchedLocation.startsWith('/staff/')) {
          return '/patient';
        }

        return null; // Allow patient routes
      }

      // 5. Staff Roles (receptionist, departmentStaff, medicalSpecialist)
      if (role == UserRole.receptionist ||
          role == UserRole.departmentStaff ||
          role == UserRole.medicalSpecialist) {
        
        final isStaffPath = state.matchedLocation.startsWith('/staff/');
        final isCommonPath = isLoggingIn || isRegistering || isConsenting || isOnboarding;

        // Staff trying to access / or patient routes are routed to their home
        if (!isStaffPath && !isCommonPath) {
          if (role == UserRole.receptionist) {
            return '/staff/reception';
          } else if (role == UserRole.departmentStaff) {
            final dept = authProvider.profile?.department?.toJsonValue() ?? 'laboratory';
            return '/staff/department/$dept';
          } else if (role == UserRole.medicalSpecialist) {
            return '/staff/specialist';
          }
        }

        // Enforce staff role guards (cross-role isolation)
        if (role == UserRole.receptionist && state.matchedLocation != '/staff/reception') {
          return '/staff/reception';
        }
        if (role == UserRole.departmentStaff) {
          final dept = authProvider.profile?.department?.toJsonValue() ?? 'laboratory';
          if (state.matchedLocation != '/staff/department/$dept') {
            return '/staff/department/$dept';
          }
        }
        if (role == UserRole.medicalSpecialist && state.matchedLocation != '/staff/specialist') {
          return '/staff/specialist';
        }

        return null; // Allow staff routes
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const InitialSplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/consent',
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/staff/reception',
        builder: (context, state) => const ReceptionHomeScreen(),
      ),
      GoRoute(
        path: '/staff/department/:dept',
        builder: (context, state) {
          return const DepartmentHomeScreen();
        },
      ),
      GoRoute(
        path: '/staff/specialist',
        builder: (context, state) => const SpecialistHomeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/patient',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/submit',
            builder: (context, state) => const SubmitDocumentScreen(),
          ),
          GoRoute(
            path: '/records',
            builder: (context, state) => const RecordsScreen(),
          ),
          GoRoute(
            path: '/queue',
            builder: (context, state) => const QueueScreen(),
          ),
          GoRoute(
            path: '/documents/status',
            builder: (context, state) => const DocumentStatusScreen(),
          ),
          GoRoute(
            path: '/chatbot',
            builder: (context, state) => const ChatbotScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
}

/// AppShell serves as the persistent layout wrapper that manages the bottom navigation bar and shared DashboardProvider lifecycle.
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final localDb = Provider.of<LocalDatabase>(context, listen: false);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DashboardProvider>(
          create: (_) => DashboardProvider(localDb),
        ),
        ChangeNotifierProvider<DocumentSubmissionProvider>(
          create: (_) => DocumentSubmissionProvider(localDb),
        ),
        ChangeNotifierProvider<ChatbotProvider>(
          create: (_) => ChatbotProvider(),
        ),
        ChangeNotifierProvider<RecordsProvider>(
          create: (_) => RecordsProvider(localDb),
        ),
        ChangeNotifierProvider<QueueProvider>(
          create: (_) => QueueProvider(localDb),
        ),
        ChangeNotifierProvider<DocumentStatusProvider>(
          create: (_) => DocumentStatusProvider(localDb),
        ),
      ],
      child: Scaffold(
        body: child,
        bottomNavigationBar: const _AppBottomNavBar(),
      ),
    );
  }
}

class _AppBottomNavBar extends StatelessWidget {
  const _AppBottomNavBar();

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location == '/submit') return 1;
    if (location == '/records') return 2;
    if (location == '/chatbot') return 3;
    if (location == '/profile') return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/patient');
        break;
      case 1:
        context.go('/submit');
        break;
      case 2:
        context.go('/records');
        break;
      case 3:
        context.go('/chatbot');
        break;
      case 4:
        context.go('/profile');
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
            icon: Icon(Icons.document_scanner_outlined),
            activeIcon: Icon(Icons.document_scanner_rounded),
            label: 'Submit',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Records',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
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

/// InitialSplashScreen serves as the loader interface during startup and session evaluation.
class InitialSplashScreen extends StatelessWidget {
  const InitialSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(
                Icons.medical_services_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'KlinikAid',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connecting you to care...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
