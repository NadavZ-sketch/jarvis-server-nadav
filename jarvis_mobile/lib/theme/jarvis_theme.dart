import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Selectable visual themes. `navyDark` is the historical default and must
/// preserve the exact look the app shipped with.
enum AppTheme { navyDark, glassDark, neoDark, material3, cyberpunk }

extension AppThemeMeta on AppTheme {
  String get hebrewLabel {
    switch (this) {
      case AppTheme.navyDark:   return 'כחול כהה';
      case AppTheme.glassDark:  return 'זכוכית';
      case AppTheme.neoDark:    return 'נאומורפי';
      case AppTheme.material3:  return 'חומר 3';
      case AppTheme.cyberpunk:  return 'סייברפאנק';
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
  // Behavioural flags consumed by widgets that render differently per theme
  final bool usesGlass;
  final bool usesNeo;
  final bool isCyber;

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
}

/// Builds [JarvisColorScheme] and [ThemeData] for a given [AppTheme].
class JarvisThemeData {
  static JarvisColorScheme schemeFor(AppTheme t) {
    switch (t) {
      case AppTheme.navyDark:   return JarvisColorScheme.navyDark;
      case AppTheme.glassDark:  return JarvisColorScheme.glassDark;
      case AppTheme.neoDark:    return JarvisColorScheme.neoDark;
      case AppTheme.material3:  return JarvisColorScheme.material3;
      case AppTheme.cyberpunk:  return JarvisColorScheme.cyberpunk;
    }
  }

  static ThemeData themeDataFor(AppTheme t) {
    final c = schemeFor(t);
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: c.bg,
      colorScheme: ColorScheme.dark(
        primary: c.blue500,
        onPrimary: Colors.white,
        surface: c.surface,
        surfaceContainerHighest: c.surfaceAlt,
        outline: c.border,
        onSurface: c.textSecondary,
        onSurfaceVariant: c.textMuted,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
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
