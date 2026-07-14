import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/consent_screen.dart';
import '../../features/auth/presentation/screens/verification_code_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/profile_screen.dart';
import '../../features/documents/presentation/screens/submit_document_screen.dart';
import '../../features/records/presentation/screens/records_screen.dart';
import '../../features/patient/templates/presentation/screens/template_picker_screen.dart';
import '../../features/patient/templates/presentation/screens/template_form_renderer_screen.dart';
import '../../features/patient/templates/presentation/providers/templates_provider.dart';
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
import '../../features/staff/presentation/screens/specialist_home_screen.dart';
import '../../features/auth/presentation/screens/totp_verify_screen.dart';
import '../../features/reception/presentation/reception_shell.dart';
import '../../features/reception/presentation/screens/reception_queue_screen.dart';
import '../../features/reception/presentation/screens/document_validation_screen.dart';
import '../../features/reception/presentation/screens/reception_dashboard_screen.dart';
import '../../features/department/presentation/department_shell.dart';
import '../../features/department/presentation/screens/department_queue_screen.dart';
import '../../features/department/presentation/screens/department_records_screen.dart';
import '../../features/department/presentation/screens/result_entry_screen.dart';
import '../../features/department/data/department_repository.dart';
import '../../features/specialist/presentation/specialist_shell.dart';
import '../../features/specialist/presentation/screens/specialist_dashboard_screen.dart';
import '../../features/specialist/presentation/screens/specialist_directory_screen.dart';
import '../../features/specialist/presentation/providers/specialist_provider.dart';
import '../../features/specialist/presentation/providers/record_entry_provider.dart';
import '../../features/specialist/presentation/screens/record_entry_screen.dart';
import '../../features/specialist/presentation/providers/analytics_provider.dart';
import '../../features/specialist/presentation/screens/analytics_screen.dart';
import '../../features/admin/presentation/admin_shell.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/admin/presentation/screens/admin_staff_screen.dart';
import '../../features/admin/presentation/screens/admin_queue_screen.dart';
import '../../features/admin/presentation/screens/admin_records_screen.dart';
import '../../features/admin/presentation/screens/admin_logs_screen.dart';
import '../../features/admin/presentation/screens/admin_rag_screen.dart';

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
      final isLoading = authProvider.isLoading;
      final role = authProvider.profile?.role;

      final isLoggingIn = state.matchedLocation == '/login';
      final isRegistering = state.matchedLocation == '/register';
      final isConsenting = state.matchedLocation == '/consent';

      // 1. If auth is loading, do not perform redirects yet (let it show loading states)
      if (isLoading) {
        return null;
      }

      // 1b. Block deactivated users immediately
      if (isAuthenticated && authProvider.profile?.isActive == false) {
        authProvider.signOut();
        return '/login';
      }

      // 2. Unauthenticated User gating
      if (!isAuthenticated) {
        if (isLoggingIn || isRegistering || state.matchedLocation == '/forgot-password') {
          return null; // Allow login, register, or forgot password screen
        }
        return '/login';
      }

      // 2b. MFA Step-up gating
      if (authProvider.isAal1Pending) {
        if (role == UserRole.departmentStaff) {
          final dept = authProvider.profile?.department;
          if (dept == null) {
            authProvider.signOut();
            return '/login';
          }
        }
        if (state.matchedLocation == '/mfa-verify') {
          return null;
        }
        return '/mfa-verify';
      }

      // Prevent non-pending users from accessing /mfa-verify
      if (state.matchedLocation == '/mfa-verify') {
        if (role == UserRole.patient) {
          return '/patient';
        } else if (role == UserRole.receptionist) {
          return '/reception/queue';
        } else if (role == UserRole.departmentStaff) {
          return '/department/queue';
        } else if (role == UserRole.medicalSpecialist) {
          return '/staff/specialist';
        } else if (role == UserRole.admin && authProvider.isAal2) {
          return '/admin/dashboard';
        }
        return null;
      }

      // 3. Admin Routing & AAL2 Guarding
      if (role == UserRole.admin) {
        if (!authProvider.isAal2) {
          return '/mfa-verify';
        }

        // Redirect admins trying to access non-admin paths to dashboard
        final isAdminPath = state.matchedLocation.startsWith('/admin/');
        if (!isAdminPath && state.matchedLocation != '/login') {
          return '/admin/dashboard';
        }
        return null;
      }

      // 4. Role-based routing
      if (role == UserRole.patient) {
        // Enforce Email OTP Verification Gate
        if (authProvider.profile?.emailVerifiedAt == null) {
          if (state.matchedLocation == '/verify') {
            return null; // Stay on verify screen
          }
          return '/verify';
        }

        // If verified patient attempts to visit verify screen, redirect them away
        if (state.matchedLocation == '/verify') {
          return '/patient';
        }

        // Enforce Privacy Consent Gate (RA 10173)
        if (!hasConsented) {
          if (isConsenting) {
            return null; // Stay on consent screen
          }
          return '/consent';
        }

        // Authenticated & Consented Patient redirection
        if (isLoggingIn || isRegistering || isConsenting || state.matchedLocation == '/' || state.matchedLocation == '/verify') {
          return '/patient';
        }

        // Patient trying to access staff/admin routes is redirected to /patient
        if (state.matchedLocation.startsWith('/staff/') || 
            state.matchedLocation.startsWith('/reception/') ||
            state.matchedLocation.startsWith('/department/') ||
            state.matchedLocation.startsWith('/admin/')) {
          return '/patient';
        }

        return null; // Allow patient routes
      }

      // 5. Staff Roles (receptionist, departmentStaff, medicalSpecialist)
      if (role == UserRole.receptionist ||
          role == UserRole.departmentStaff ||
          role == UserRole.medicalSpecialist) {
        
        // Block other staff roles from admin paths
        if (state.matchedLocation.startsWith('/admin/')) {
          if (role == UserRole.receptionist) {
            return '/reception/queue';
          } else if (role == UserRole.departmentStaff) {
            return '/department/queue';
          } else if (role == UserRole.medicalSpecialist) {
            return '/specialist/dashboard';
          }
        }

        final isStaffPath = state.matchedLocation.startsWith('/staff/') || 
                            state.matchedLocation.startsWith('/reception/') ||
                            state.matchedLocation.startsWith('/department/') ||
                            state.matchedLocation.startsWith('/specialist/');
        final isCommonPath = isLoggingIn || isRegistering || isConsenting;

        // Staff trying to access / or patient routes are routed to their home
        if (!isStaffPath && !isCommonPath) {
          if (role == UserRole.receptionist) {
            return '/reception/queue';
          } else if (role == UserRole.departmentStaff) {
            return '/department/queue';
          } else if (role == UserRole.medicalSpecialist) {
            return '/specialist/dashboard';
          }
        }

        // Enforce staff role guards (cross-role isolation)
        if (role == UserRole.receptionist) {
          if (!state.matchedLocation.startsWith('/reception/')) {
            return '/reception/queue';
          }
        }
        if (role == UserRole.departmentStaff) {
          final dept = authProvider.profile?.department;
          if (dept == null) {
            authProvider.signOut();
            return '/login';
          }
          if (!state.matchedLocation.startsWith('/department/')) {
            return '/department/queue';
          }
        }
        if (role == UserRole.medicalSpecialist) {
          if (!state.matchedLocation.startsWith('/specialist/')) {
            return '/specialist/dashboard';
          }
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
        path: '/mfa-verify',
        builder: (context, state) => const TotpVerifyScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/consent',
        builder: (context, state) => const ConsentScreen(),
      ),

      GoRoute(
        path: '/verify',
        builder: (context, state) => const VerificationCodeScreen(),
      ),
      GoRoute(
        path: '/staff/reception',
        builder: (context, state) => const ReceptionHomeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return DepartmentShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/department/queue',
            builder: (context, state) => const DepartmentQueueScreen(),
          ),
          GoRoute(
            path: '/department/records',
            builder: (context, state) => const DepartmentRecordsScreen(),
          ),
          GoRoute(
            path: '/department/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/department/result-entry/:patientId',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          DepartmentRepository? repo;
          try {
            repo = Provider.of<DepartmentRepository>(context, listen: false);
          } catch (_) {}
          return ResultEntryScreen(patientId: patientId, repo: repo);
        },
      ),
      GoRoute(
        path: '/admin/department/result-entry/:patientId',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          final dept = state.uri.queryParameters['dept'];
          DepartmentRepository? repo;
          try {
            repo = Provider.of<DepartmentRepository>(context, listen: false);
          } catch (_) {}
          return ResultEntryScreen(
            patientId: patientId,
            repo: repo,
            departmentOverride: dept,
          );
        },
      ),
      GoRoute(
        path: '/staff/specialist',
        builder: (context, state) => const SpecialistHomeScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return SpecialistShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/specialist/dashboard',
            builder: (context, state) => const SpecialistDashboardScreen(),
          ),
          GoRoute(
            path: '/specialist/patients',
            builder: (context, state) => const SpecialistDirectoryScreen(),
          ),
          GoRoute(
            path: '/specialist/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/specialist/record-entry/:patientId',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          SpecialistProvider? parentProvider;
          try {
            parentProvider = Provider.of<SpecialistProvider>(context, listen: false);
          } catch (_) {}

          return MultiProvider(
            providers: [
              if (parentProvider != null)
                ChangeNotifierProvider<SpecialistProvider>.value(value: parentProvider)
              else
                ChangeNotifierProvider<SpecialistProvider>(create: (context) => SpecialistProvider()),
              ChangeNotifierProvider<RecordEntryProvider>(
                create: (context) => RecordEntryProvider(
                  repository: Provider.of<SpecialistProvider>(context, listen: false).repository,
                ),
              ),
            ],
            child: RecordEntryScreen(patientId: patientId),
          );
        },
      ),
      GoRoute(
        path: '/specialist/analytics/:patientId',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId']!;
          SpecialistProvider? parentProvider;
          try {
            parentProvider = Provider.of<SpecialistProvider>(context, listen: false);
          } catch (_) {}

          return MultiProvider(
            providers: [
              if (parentProvider != null)
                ChangeNotifierProvider<SpecialistProvider>.value(value: parentProvider)
              else
                ChangeNotifierProvider<SpecialistProvider>(create: (context) => SpecialistProvider()),
              ChangeNotifierProvider<AnalyticsProvider>(
                create: (context) => AnalyticsProvider(
                  repository: Provider.of<SpecialistProvider>(context, listen: false).repository,
                ),
              ),
            ],
            child: AnalyticsScreen(patientId: patientId),
          );
        },
      ),
      GoRoute(
        path: '/reception/document/:submissionId',
        builder: (context, state) {
          final submissionId = state.pathParameters['submissionId']!;
          return DocumentValidationScreen(submissionId: submissionId);
        },
      ),
      GoRoute(
        path: '/admin/document/:submissionId',
        builder: (context, state) {
          final submissionId = state.pathParameters['submissionId']!;
          return DocumentValidationScreen(submissionId: submissionId);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          return ReceptionShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/reception/dashboard',
            builder: (context, state) => const ReceptionDashboardScreen(),
          ),
          GoRoute(
            path: '/reception/queue',
            builder: (context, state) => const ReceptionQueueScreen(),
          ),
          GoRoute(
            path: '/reception/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AdminShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/admin/dashboard',
            builder: (context, state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: '/admin/staff',
            builder: (context, state) => const AdminStaffScreen(),
          ),
          GoRoute(
            path: '/admin/queue',
            builder: (context, state) => const AdminQueueScreen(),
          ),
          GoRoute(
            path: '/admin/records',
            builder: (context, state) => const AdminRecordsScreen(),
          ),
          GoRoute(
            path: '/admin/logs',
            builder: (context, state) => const AdminLogsScreen(),
          ),
          GoRoute(
            path: '/admin/rag',
            builder: (context, state) => const AdminRagScreen(),
          ),
          GoRoute(
            path: '/admin/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
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
            path: '/patient/templates',
            builder: (context, state) => const TemplatePickerScreen(),
          ),
          GoRoute(
            path: '/patient/templates/:templateId',
            builder: (context, state) {
              final templateId = state.pathParameters['templateId']!;
              return TemplateFormRendererScreen(templateId: templateId);
            },
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
        ChangeNotifierProvider<TemplatesProvider>(
          create: (_) => TemplatesProvider(),
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
