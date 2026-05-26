import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/supabase/supabase_client.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'core/routing/app_router.dart';

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

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _appRouter = AppRouter(_authProvider);
  }

  @override
  void dispose() {
    _authProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: _authProvider,
      child: MaterialApp.router(
        title: 'KlinikAid',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark, // Default to premium dark theme
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0E14),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF2E5BFF),
            secondary: Color(0xFF00C1D4),
            surface: Color(0xFF0F131D),
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Outfit'),
            bodyMedium: TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
          ),
        ),
        routerConfig: _appRouter.router,
      ),
    );
  }
}
