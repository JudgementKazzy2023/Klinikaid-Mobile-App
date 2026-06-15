import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/supabase/supabase_client.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'core/routing/app_router.dart';
import 'core/cache/local_database.dart';
import 'core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _localDatabase = LocalDatabase();
    _authProvider = AuthProvider();
    _appRouter = AppRouter(_authProvider);
  }

  @override
  void dispose() {
    _authProvider.dispose();
    _localDatabase.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: _localDatabase),
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
      ],
      child: MaterialApp.router(
        title: 'KlinikAid',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: AppTheme.lightTheme,
        routerConfig: _appRouter.router,
      ),
    );
  }
}
