import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../theme/jarvis_theme.dart';

/// Horizontal row of theme preview cards. Tapping one calls [onSelected] with
/// the chosen [AppTheme]; the caller is responsible for applying it live and
/// persisting it.
class ThemePicker extends StatelessWidget {
  final AppTheme selected;
  final ValueChanged<AppTheme> onSelected;

  const ThemePicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: AppTheme.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final theme = AppTheme.values[i];
          final scheme = JarvisThemeData.schemeFor(theme);
          final active = theme == selected;
          return GestureDetector(
            onTap: () => onSelected(theme),
            child: AnimatedScale(
              scale: active ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 92,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? JC.blue400 : scheme.border,
                    width: active ? 1.8 : 0.8,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: JC.blue500.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _swatch(scheme.bg),
                        _swatch(scheme.surfaceAlt),
                        _swatch(scheme.accentPrimary),
                      ],
                    ),
                    Text(
                      theme.hebrewLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? JC.blue400 : scheme.textSecondary,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontFamily: 'Heebo',
                      ),
                    ),
                    if (active)
                      Icon(Icons.check_circle_rounded,
                          color: JC.blue400, size: 16)
                    else
                      const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _swatch(Color c) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.8),
        ),
      );
}
