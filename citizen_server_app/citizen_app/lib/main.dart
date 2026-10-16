import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_state.dart';
import 'app/router.dart';
import 'core/network/api_client.dart';
import 'core/storage/local_store.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(ApiClient(), LocalStore());
  await state.initialize();
  runApp(ChangeNotifierProvider.value(value: state, child: const CitizenApp()));

  // Network availability must not hold the launch screen hostage. On a phone,
  // the emulator-only default host (10.0.2.2) is unreachable; refresh cached
  // account data after the first frame and let the app show its offline state.
  if (state.initialized && state.signedIn) unawaited(state.refreshAll());
}

class CitizenApp extends StatelessWidget {
  const CitizenApp({super.key});
  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return MaterialApp(
      title: 'InfraVision Citizen',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(dark: true),
      themeMode: switch (st.themePreference) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      locale: Locale(st.lang),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          child ?? const SizedBox.shrink(),
          IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: Theme.of(context).brightness == Brightness.dark
                    ? .04
                    : .055,
                child: Image.asset('assets/images/app_icon.png',
                    width: 250, height: 250, fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
      // Always show the branded welcome screen when the desktop app opens.
      initialRoute: '/splash',
      onGenerateRoute: onGenerateRoute,
    );
  }
}
