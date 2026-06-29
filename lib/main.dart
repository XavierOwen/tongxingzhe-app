import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_controller.dart';
import 'l10n/app_strings.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const TongxingzheApp());
}

class TongxingzheApp extends StatefulWidget {
  const TongxingzheApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<TongxingzheApp> createState() => _TongxingzheAppState();
}

class _TongxingzheAppState extends State<TongxingzheApp> {
  late final AppController _controller;
  late final Future<void> _boot;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AppController();
    _boot = _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _boot,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final locale = Locale(_controller.localeCode);
            final text = AppStrings(locale.languageCode);

            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: text.t('appTitle'),
              locale: locale,
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              themeMode: _controller.themeMode,
              theme: _theme(Brightness.light),
              darkTheme: _theme(Brightness.dark),
              home: _controller.isLoggedIn
                  ? HomeShell(controller: _controller)
                  : AuthScreen(controller: _controller),
            );
          },
        );
      },
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF14746F),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
