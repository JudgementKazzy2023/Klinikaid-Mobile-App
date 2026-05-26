import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/consent_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';

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

      // 3. Authenticated User gating: Data Privacy Consent Gate (RA 10173)
      if (!hasConsented) {
        if (isConsenting) {
          return null; // Stay on consent screen
        }
        return '/consent';
      }

      // 4. Onboarding Gate (Patient record check)
      if (!isOnboarded) {
        if (isOnboarding) {
          return null; // Stay on onboarding screen
        }
        return '/onboarding';
      }

      // 5. Authenticated, Consented & Onboarded User redirection
      if (isLoggingIn || isRegistering || isConsenting || isOnboarding) {
        return '/'; // Go to home/dashboard
      }

      return null; // Allow navigation to target route
    },
    routes: [
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
        path: '/',
        builder: (context, state) => const DashboardPlaceholderScreen(),
      ),
    ],
  );
}

/// Temporary placeholder for the Dashboard (implemented in Phase 3)
class DashboardPlaceholderScreen extends StatelessWidget {
  const DashboardPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text('Klinikaid Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F131D),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () {
              // Access AuthProvider and call signOut
              GoRouter.of(context).read<AuthProvider>().signOut();
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E5BFF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.dashboard_customize_outlined, size: 64, color: Color(0xFF2E5BFF)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to KlinikAid!',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your account is authenticated, consented, and onboarded. The full dashboard features will unlock in Phase 3.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on GoRouter {
  T read<T>() {
    final context = routerDelegate.navigatorKey.currentContext!;
    return GoRouterHelper(context).read<T>();
  }
}

class GoRouterHelper {
  final BuildContext context;
  GoRouterHelper(this.context);
  T read<T>() => Navigator.of(context).context.read<T>();
}

// Simple extension helper to avoid importing provider direct in GoRouter helper extension
extension on BuildContext {
  T read<T>() => WatchContext(this).read<T>();
}

class WatchContext {
  final BuildContext context;
  WatchContext(this.context);
  T read<T>() => watchProvider<T>(context);
}

// Top level method to resolve provider using flutter widgets tree context safely
T watchProvider<T>(BuildContext context) {
  try {
    return WatchContextHelper.dependOn<T>(context);
  } catch (_) {
    throw Exception('Provider<$T> not found in context.');
  }
}

class WatchContextHelper {
  static T dependOn<T>(BuildContext context) {
    // Uses context.read<T>() under the hood, but resolves dependency dynamically
    // to bypass direct import warnings if provider is imported via other wrappers.
    // Provider package exports 'read' extension method.
    // We can resolve it by casting context to dynamic.
    return (context as dynamic).read<T>();
  }
}
