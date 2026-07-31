import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_strings.dart';
import '../identity/identity_session.dart';
import '../screens/auth_screen.dart';
import '../screens/home_shell.dart';
import 'app_controller.dart';
import 'app_dependencies.dart';

typedef SignedOutScreenBuilder =
    Widget Function(BuildContext context, AppController controller);

class TongxingzheApp extends StatefulWidget {
  const TongxingzheApp({
    super.key,
    required this.dependencies,
    this.signedOutScreenBuilder,
  });

  final AppDependencies dependencies;

  /// 只有 `main_demo.dart` 会注入 legacy 登录页；正式入口保持为 `null`。
  final SignedOutScreenBuilder? signedOutScreenBuilder;

  @override
  State<TongxingzheApp> createState() => _TongxingzheAppState();
}

class _TongxingzheAppState extends State<TongxingzheApp> {
  late final Future<AppStartupResult> _startup;
  AppController? _controller;
  IdentitySession? _identitySession;

  @override
  void initState() {
    super.initState();
    _startup = _start();
  }

  Future<AppStartupResult> _start() async {
    final result = await widget.dependencies.start();
    if (result case AppStartupReady(
      :final controller,
      :final identitySession,
    )) {
      _controller = controller;
      _identitySession = identitySession;
    }
    return result;
  }

  @override
  void dispose() {
    unawaited(_identitySession?.close());
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppStartupResult>(
      future: _startup,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        return switch (snapshot.requireData) {
          AppStartupReady(:final controller) => _ReadyApp(
            controller: controller,
            signedOutScreenBuilder: widget.signedOutScreenBuilder,
          ),
          AppStartupFailed(:final failure) => _StartupFailureApp(
            failure: failure,
          ),
        };
      },
    );
  }
}

class _ReadyApp extends StatelessWidget {
  const _ReadyApp({
    required this.controller,
    required this.signedOutScreenBuilder,
  });

  final AppController controller;
  final SignedOutScreenBuilder? signedOutScreenBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final locale = Locale(controller.localeCode);
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
          themeMode: controller.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: controller.isLoggedIn
              ? HomeShell(controller: controller)
              : signedOutScreenBuilder?.call(context, controller) ??
                    AuthScreen(controller: controller),
        );
      },
    );
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.failure});

  final AppStartupFailure failure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 40),
                const SizedBox(height: 16),
                const Text(
                  '本地数据库启动失败 / Local database startup failed',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText(failure.code),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
