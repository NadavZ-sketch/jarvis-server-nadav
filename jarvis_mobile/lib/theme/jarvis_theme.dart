import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Selectable visual themes. `navyDark` is the historical default and must
/// preserve the exact look the app shipped with.
enum AppTheme { navyDark, glassDark, neoDark, material3, cyberpunk, violetDark }

extension AppThemeMeta on AppTheme {
  String get hebrewLabel {
    switch (this) {
      case AppTheme.navyDark:    return 'כחול כהה';
      case AppTheme.glassDark:   return 'זכוכית';
      case AppTheme.neoDark:     return 'נאומורפי';
      case AppTheme.material3:   return 'חומר 3';
      case AppTheme.cyberpunk:   return 'סייברפאנק';
      case AppTheme.violetDark:  return '✨ סגול';
    }
  }
}

/// User-selectable appearance mode. Independent of [AppTheme]: the theme picks
/// the *palette personality*, this picks light vs dark. `system` follows the
/// platform brightness. Kept separate from Flutter's [ThemeMode] so we control
/// the Hebrew labels and resolve `system` ourselves.
enum AppBrightnessMode { system, light, dark }

extension AppBrightnessModeMeta on AppBrightnessMode {
  String get hebrewLabel {
    switch (this) {
      case AppBrightnessMode.system: return 'אוטומטי';
      case AppBrightnessMode.light:  return 'בהיר';
      case AppBrightnessMode.dark:   return 'כהה';
    }
  }
}

/// A complete set of color tokens. Every token that used to live on the old
/// `JC` constant class is present here so existing call sites keep working,
/// plus a handful of theme-specific extras (glass overlay, neo shadows...).
@immutable
class JarvisColorScheme {
  // Backgrounds
  final Color bg, surface, surfaceAlt, border;
  // Blue / accent palette
  final Color blue500, blue400, blue300;
  // Text
  final Color textPrimary, textSecondary, textMuted;
  // Chat bubbles
  final Color userBubble, jarvisBubble;
  // Actions
  final Color cancelRed, indigo500, indigo300;
  // Priority / status
  final Color amber400, green500;
  // Theme-specific extras
  final Color accentPrimary;   // headline accent for the theme
  final Color glassOverlay;    // translucent layer for glassmorphism cards
  final Color neoShadowLight;  // top-left highlight for neumorphism
  final Color neoShadowDark;   // bottom-right shadow for neumorphism
  // Semantic tokens — added so dark-assuming hardcoded colors can be migrated
  // and recolor correctly in light mode. Defaults preserve the historical dark
  // behaviour so the existing dark schemes need no edits.
  final Color onAccent;        // text/icon on a filled accent surface
  final Color scrim;           // modal/backdrop overlay
  final Color shadow;          // BoxShadow / elevation base
  final Brightness brightness; // drives ThemeData base + status-bar icons
  // Behavioural flags consumed by widgets that render differently per theme
  final bool usesGlass;
  final bool usesNeo;
  final bool isCyber;

  // TODO(theming): a future phase can add a parallel `JarvisDimens` (spacing /
  // radius / type) resolved the same theme-keyed way and exposed via a `JD`
  // shim, so the swap mechanism built here generalizes beyond color.

  const JarvisColorScheme({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.blue500,
    required this.blue400,
    required this.blue300,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.userBubble,
    required this.jarvisBubble,
    required this.cancelRed,
    required this.indigo500,
    required this.indigo300,
    required this.amber400,
    required this.green500,
    required this.accentPrimary,
    required this.glassOverlay,
    required this.neoShadowLight,
    required this.neoShadowDark,
    this.onAccent = Colors.white,
    this.scrim = const Color(0x99000000),
    this.shadow = const Color(0x66000000),
    this.brightness = Brightness.dark,
    this.usesGlass = false,
    this.usesNeo = false,
    this.isCyber = false,
  });

  // ── navyDark — exact legacy values ──────────────────────────────────────
  static const navyDark = JarvisColorScheme(
    bg:            Color(0xFF05090E),
    surface:       Color(0xFF0B1422),
    surfaceAlt:    Color(0xFF0F1929),
    border:        Color(0xFF1A2E4A),
    blue500:       Color(0xFF3B82F6),
    blue400:       Color(0xFF60A5FA),
    blue300:       Color(0xFF93C5FD),
    textPrimary:   Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted:     Color(0xFF475569),
    userBubble:    Color(0xFF11284A),
    jarvisBubble:  Color(0xFF0B1929),
    cancelRed:     Color(0xFFEF4444),
    indigo500:     Color(0xFF6366F1),
    indigo300:     Color(0xFFA5B4FC),
    amber400:      Color(0xFFF59E0B),
    green500:      Color(0xFF22C55E),
    accentPrimary: Color(0xFF60A5FA),
    glassOverlay:  Color(0x14FFFFFF),
    neoShadowLight: Color(0xFF13243E),
    neoShadowDark:  Color(0xFF03070D),
  );

  // ── glassDark — lighter translucent surfaces, blur-friendly ─────────────
  static const glassDark = JarvisColorScheme(
    bg:            Color(0xFF070C16),
    surface:       Color(0xFF101D33),
    surfaceAlt:    Color(0xFF15233D),
    border:        Color(0xFF2A4060),
    blue500:       Color(0xFF3B82F6),
    blue400:       Color(0xFF7CB0FF),
    blue300:       Color(0xFFA9CCFF),
    textPrimary:   Color(0xFFF4F8FF),
    textSecondary: Color(0xFFA6B6CE),
    textMuted:     Color(0xFF5A6E8C),
    userBubble:    Color(0xFF1C3A66),
    jarvisBubble:  Color(0xFF13233F),
    cancelRed:     Color(0xFFFF6B6B),
    indigo500:     Color(0xFF7C7FF5),
    indigo300:     Color(0xFFB8C0FF),
    amber400:      Color(0xFFFFB23E),
    green500:      Color(0xFF35D67F),
    accentPrimary: Color(0xFF7CB0FF),
    glassOverlay:  Color(0x26FFFFFF),
    neoShadowLight: Color(0xFF1B3052),
    neoShadowDark:  Color(0xFF050A14),
    usesGlass: true,
  );

  // ── neoDark — flat base, shadows do the work ────────────────────────────
  static const neoDark = JarvisColorScheme(
    bg:            Color(0xFF0B1422),
    surface:       Color(0xFF0B1422),
    surfaceAlt:    Color(0xFF0E1827),
    border:        Color(0xFF15233A),
    blue500:       Color(0xFF3B82F6),
    blue400:       Color(0xFF60A5FA),
    blue300:       Color(0xFF93C5FD),
    textPrimary:   Color(0xFFEEF3FA),
    textSecondary: Color(0xFF93A3BC),
    textMuted:     Color(0xFF52627D),
    userBubble:    Color(0xFF11284A),
    jarvisBubble:  Color(0xFF0E1827),
    cancelRed:     Color(0xFFEF4444),
    indigo500:     Color(0xFF6366F1),
    indigo300:     Color(0xFFA5B4FC),
    amber400:      Color(0xFFF59E0B),
    green500:      Color(0xFF22C55E),
    accentPrimary: Color(0xFF60A5FA),
    glassOverlay:  Color(0x10FFFFFF),
    neoShadowLight: Color(0xFF16253E),
    neoShadowDark:  Color(0xFF03070D),
    usesNeo: true,
  );

  // ── material3 — MD3-flavoured dark ──────────────────────────────────────
  static const material3 = JarvisColorScheme(
    bg:            Color(0xFF101418),
    surface:       Color(0xFF1A1F26),
    surfaceAlt:    Color(0xFF222831),
    border:        Color(0xFF2E353F),
    blue500:       Color(0xFF8AB4F8),
    blue400:       Color(0xFFA8C7FA),
    blue300:       Color(0xFFC2D7FB),
    textPrimary:   Color(0xFFE3E8EF),
    textSecondary: Color(0xFFB0BAC6),
    textMuted:     Color(0xFF6B7682),
    userBubble:    Color(0xFF2B3A52),
    jarvisBubble:  Color(0xFF1E242D),
    cancelRed:     Color(0xFFF2B8B5),
    indigo500:     Color(0xFFB0A6F5),
    indigo300:     Color(0xFFCFC8FB),
    amber400:      Color(0xFFF7C56B),
    green500:      Color(0xFF7FD99A),
    accentPrimary: Color(0xFFA8C7FA),
    glassOverlay:  Color(0x14FFFFFF),
    neoShadowLight: Color(0xFF262D38),
    neoShadowDark:  Color(0xFF0A0D11),
  );

  // ── cyberpunk — neon cyan + electric purple ─────────────────────────────
  static const cyberpunk = JarvisColorScheme(
    bg:            Color(0xFF04070F),
    surface:       Color(0xFF0A0E1A),
    surfaceAlt:    Color(0xFF0E1424),
    border:        Color(0xFF1B2B4D),
    blue500:       Color(0xFF7B2FFF),
    blue400:       Color(0xFF00F5FF),
    blue300:       Color(0xFF66FCFF),
    textPrimary:   Color(0xFFEAFBFF),
    textSecondary: Color(0xFF8FB6C9),
    textMuted:     Color(0xFF4D6A82),
    userBubble:    Color(0xFF1A1145),
    jarvisBubble:  Color(0xFF071326),
    cancelRed:     Color(0xFFFF3D71),
    indigo500:     Color(0xFF9D4EFF),
    indigo300:     Color(0xFFC9A0FF),
    amber400:      Color(0xFFFFC400),
    green500:      Color(0xFF2BFFB3),
    accentPrimary: Color(0xFF00F5FF),
    glassOverlay:  Color(0x1A00F5FF),
    neoShadowLight: Color(0xFF12233F),
    neoShadowDark:  Color(0xFF020308),
    isCyber: true,
  );

  // ── violetDark — Premium Dark AI: deep violet accent, glassmorphism ────
  static const violetDark = JarvisColorScheme(
    bg:            Color(0xFF070B12),
    surface:       Color(0xFF0C1018),
    surfaceAlt:    Color(0xFF0F1724),
    border:        Color(0xFF1C2236),
    blue500:       Color(0xFF7C3AED),
    blue400:       Color(0xFFA78BFA),
    blue300:       Color(0xFFC4B5FD),
    textPrimary:   Color(0xFFE8EAF0),
    textSecondary: Color(0xFF8892A4),
    textMuted:     Color(0xFF4A5568),
    userBubble:    Color(0xFF1E1245),
    jarvisBubble:  Color(0xFF0A0D1A),
    cancelRed:     Color(0xFFEF4444),
    indigo500:     Color(0xFF7C3AED),
    indigo300:     Color(0xFFA78BFA),
    amber400:      Color(0xFFF59E0B),
    green500:      Color(0xFF22C55E),
    accentPrimary: Color(0xFF7C3AED),
    glassOverlay:  Color(0x0D7C3AED),
    neoShadowLight: Color(0xFF1A1245),
    neoShadowDark:  Color(0xFF020308),
    usesGlass: true,
  );

  // ── light — the canonical light foundation ──────────────────────────────
  // Phase-1 fallback: one well-crafted light palette shared by ALL themes when
  // the user picks light mode. Per-theme light *personalities* (glass/neo/cyber
  // light variants) are intentionally deferred to a later visual-refresh phase;
  // `schemeFor` currently returns this for every theme in light mode.
  static const light = JarvisColorScheme(
    bg:            Color(0xFFF7F8FA),
    surface:       Color(0xFFFFFFFF),
    surfaceAlt:    Color(0xFFEEF1F5),
    border:        Color(0xFFD8DEE6),
    blue500:       Color(0xFF2563EB),
    blue400:       Color(0xFF3B82F6),
    blue300:       Color(0xFF60A5FA),
    textPrimary:   Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted:     Color(0xFF94A3B8),
    userBubble:    Color(0xFFDBEAFE),
    jarvisBubble:  Color(0xFFEEF1F5),
    cancelRed:     Color(0xFFDC2626),
    indigo500:     Color(0xFF6366F1),
    indigo300:     Color(0xFF818CF8),
    amber400:      Color(0xFFD97706),
    green500:      Color(0xFF16A34A),
    accentPrimary: Color(0xFF2563EB),
    glassOverlay:  Color(0x0A000000),
    neoShadowLight: Color(0xFFFFFFFF),
    neoShadowDark:  Color(0xFFD1D9E6),
    onAccent:      Colors.white,
    scrim:         Color(0x66000000),
    shadow:        Color(0x1F000000),
    brightness:    Brightness.light,
  );
}

/// Builds [JarvisColorScheme] and [ThemeData] for a given [AppTheme].
class JarvisThemeData {
  static JarvisColorScheme schemeFor(AppTheme t, [Brightness b = Brightness.dark]) {
    if (b == Brightness.light) {
      // Phase-1 fallback: every theme shares the generic light foundation.
      // Later phases can switch(t) here for per-theme light variants.
      return JarvisColorScheme.light;
    }
    switch (t) {
      case AppTheme.navyDark:   return JarvisColorScheme.navyDark;
      case AppTheme.glassDark:  return JarvisColorScheme.glassDark;
      case AppTheme.neoDark:    return JarvisColorScheme.neoDark;
      case AppTheme.material3:  return JarvisColorScheme.material3;
      case AppTheme.cyberpunk:  return JarvisColorScheme.cyberpunk;
      case AppTheme.violetDark: return JarvisColorScheme.violetDark;
    }
  }

  static ThemeData themeDataFor(AppTheme t, [Brightness b = Brightness.dark]) {
    final c = schemeFor(t, b);
    final isLight = b == Brightness.light;
    final base = isLight ? ThemeData.light() : ThemeData.dark();
    final colorScheme = (isLight
            ? ColorScheme.light(
                primary: c.blue500,
                surface: c.surface,
                surfaceContainerHighest: c.surfaceAlt,
                outline: c.border,
                onSurface: c.textPrimary,
                onSurfaceVariant: c.textMuted,
              )
            : ColorScheme.dark(
                primary: c.blue500,
                surface: c.surface,
                surfaceContainerHighest: c.surfaceAlt,
                outline: c.border,
                onSurface: c.textSecondary,
                onSurfaceVariant: c.textMuted,
              ))
        .copyWith(onPrimary: c.onAccent);
    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      colorScheme: colorScheme,
      // Centralized Hebrew-first typography. 'Heebo' is the intended brand font
      // (bundle it under pubspec `fonts:` to activate); until then the fallback
      // chain keeps Hebrew rendering clean on every platform instead of silently
      // dropping to Latin-optimized defaults. Inline TextStyles still override.
      fontFamily: 'Heebo',
      fontFamilyFallback: const [
        'Rubik', 'Assistant', 'Arial Hebrew', 'Noto Sans Hebrew', 'Arial', 'sans-serif',
      ],
      textTheme: base.textTheme.apply(
        fontFamily: 'Heebo',
        fontFamilyFallback: const [
          'Rubik', 'Assistant', 'Arial Hebrew', 'Noto Sans Hebrew', 'Arial', 'sans-serif',
        ],
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle:
            isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceAlt,
        contentTextStyle: TextStyle(color: c.textPrimary, fontFamily: 'Heebo'),
        actionTextColor: c.blue400,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
