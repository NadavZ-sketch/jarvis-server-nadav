import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_settings.dart';
import 'theme/jarvis_theme.dart';
import 'theme/theme_notifier.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const JarvisApp());
}

// ─── Design Tokens ────────────────────────────────────────────────────────────
// `JC` is a runtime-swappable palette shim. Call [JC.apply] when the selected
// theme changes; every getter reads from the active [JarvisColorScheme] so the
// whole UI recolors on the next rebuild.
class JC {
  static JarvisColorScheme _scheme = JarvisColorScheme.navyDark;
  static AppTheme _theme = AppTheme.navyDark;
  static Brightness _brightness = Brightness.dark;

  static void apply(AppTheme t, [Brightness b = Brightness.dark]) {
    _theme = t;
    _brightness = b;
    _scheme = JarvisThemeData.schemeFor(t, b);
  }

  static AppTheme get theme => _theme;
  static Brightness get brightness => _brightness;
  static JarvisColorScheme get scheme => _scheme;

  // Backgrounds
  static Color get bg         => _scheme.bg;
  static Color get surface    => _scheme.surface;
  static Color get surfaceAlt => _scheme.surfaceAlt;
  static Color get border     => _scheme.border;

  // Blue / accent palette
  static Color get blue500 => _scheme.blue500;
  static Color get blue400 => _scheme.blue400;
  static Color get blue300 => _scheme.blue300;

  // Text
  static Color get textPrimary   => _scheme.textPrimary;
  static Color get textSecondary => _scheme.textSecondary;
  static Color get textMuted     => _scheme.textMuted;

  // Bubbles
  static Color get userBubble   => _scheme.userBubble;
  static Color get jarvisBubble => _scheme.jarvisBubble;

  // Actions
  static Color get cancelRed => _scheme.cancelRed;
  static Color get indigo500 => _scheme.indigo500;
  static Color get indigo300 => _scheme.indigo300;

  // Priority colors
  static Color get amber400 => _scheme.amber400;
  static Color get green500 => _scheme.green500;

  // Theme-specific extras
  static Color get accentPrimary  => _scheme.accentPrimary;
  static Color get glassOverlay   => _scheme.glassOverlay;
  static Color get neoShadowLight => _scheme.neoShadowLight;
  static Color get neoShadowDark  => _scheme.neoShadowDark;

  // Semantic tokens
  static Color get onAccent => _scheme.onAccent;
  static Color get scrim    => _scheme.scrim;
  static Color get shadow   => _scheme.shadow;
}

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  final ValueNotifier<AppTheme> _themeNotifier =
      ValueNotifier<AppTheme>(AppTheme.navyDark);
  final ValueNotifier<AppBrightnessMode> _modeNotifier =
      ValueNotifier<AppBrightnessMode>(AppBrightnessMode.dark);

  /// Resolves an [AppBrightnessMode] to a concrete [Brightness]. `system`
  /// reads the live platform brightness.
  Brightness _resolve(AppBrightnessMode m) {
    switch (m) {
      case AppBrightnessMode.light: return Brightness.light;
      case AppBrightnessMode.dark:  return Brightness.dark;
      case AppBrightnessMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  void _onPlatformBrightnessChanged() {
    // Only the system mode follows the OS; force a rebuild so the resolved
    // brightness is re-applied.
    if (_modeNotifier.value == AppBrightnessMode.system && mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        _onPlatformBrightnessChanged;
    AppSettings.load().then((s) {
      _themeNotifier.value = s.selectedTheme;
      _modeNotifier.value = s.brightnessMode;
      JC.apply(s.selectedTheme, _resolve(s.brightnessMode));
    });
  }

  @override
  void dispose() {
    if (WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged ==
        _onPlatformBrightnessChanged) {
      WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
          null;
    }
    _themeNotifier.dispose();
    _modeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeNotifier(
      notifier: _themeNotifier,
      child: BrightnessNotifier(
        notifier: _modeNotifier,
        child: ValueListenableBuilder<AppTheme>(
          valueListenable: _themeNotifier,
          builder: (context, theme, _) {
            return ValueListenableBuilder<AppBrightnessMode>(
              valueListenable: _modeNotifier,
              builder: (context, mode, _) {
                final b = _resolve(mode);
                JC.apply(theme, b);
                return MaterialApp(
                  debugShowCheckedModeBanner: false,
                  title: 'ג׳רביס',
                  locale: const Locale('he', 'IL'),
                  localizationsDelegates: const [
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [Locale('he', 'IL')],
                  theme: JarvisThemeData.themeDataFor(theme, b),
                  home: const SplashScreen(),
                  builder: (context, child) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

enum JarvisState { idle, listening, thinking, speaking, complete }
