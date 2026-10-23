import 'dart:async';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';

class _OfflineHttpClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Live HTTP is forbidden in tests. Use an intercepted client.',
  );
}

class _OfflineHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _OfflineHttpClient();
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await HttpOverrides.runWithHttpOverrides(
    () async => await testMain(),
    _OfflineHttpOverrides(),
  );
}
