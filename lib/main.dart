import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/supabase/supabase_client.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'core/routing/app_router.dart';
import 'core/cache/local_database.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/session_activity_service.dart';
import 'features/auth/data/session_lifecycle_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase using default credentials from env.dart
  await SupabaseService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthProvider _authProvider;
  late final AppRouter _appRouter;
  late final LocalDatabase _localDatabase;
  late final SessionActivityService _sessionActivityService;
  late final SessionLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _localDatabase = LocalDatabase();
    _sessionActivityService = SessionActivityService();
    _authProvider = AuthProvider(activityService: _sessionActivityService);
    _appRouter = AppRouter(_authProvider);
    _lifecycleObserver = SessionLifecycleObserver(_sessionActivityService, _authProvider);
    
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _sessionActivityService.stopMonitoring();
    _authProvider.dispose();
    _localDatabase.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: _localDatabase),
        Provider<SessionActivityService>.value(value: _sessionActivityService),
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
      ],
      child: Builder(
        builder: (context) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (_) => context.read<SessionActivityService>().recordActivity(),
            onPanDown: (_) => context.read<SessionActivityService>().recordActivity(),
            onScaleStart: (_) => context.read<SessionActivityService>().recordActivity(),
            child: MaterialApp.router(
              title: 'KlinikAid',
              debugShowCheckedModeBanner: false,
              themeMode: ThemeMode.light,
              theme: AppTheme.lightTheme,
              routerConfig: _appRouter.router,
            ),
          );
        },
      ),
    );
  }
}

