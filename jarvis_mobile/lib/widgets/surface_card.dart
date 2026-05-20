import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart' show JC;

/// A surface container that adapts to the active theme: frosted glass blur for
/// glassmorphism themes, soft dual-shadow for neumorphism, and a plain bordered
/// card otherwise. Use anywhere a themed "card" surface is wanted.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = JC.scheme;
    final br = BorderRadius.circular(radius);
    final base = color ?? JC.surfaceAlt;

    if (scheme.usesGlass) {
      return Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: br,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: base.withValues(alpha: 0.55),
                borderRadius: br,
                border: Border.all(color: scheme.glassOverlay, width: 1.0),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    if (scheme.usesNeo) {
      return Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: base,
          borderRadius: br,
          boxShadow: [
            BoxShadow(
              color: scheme.neoShadowDark,
              offset: const Offset(5, 5),
              blurRadius: 12,
            ),
            BoxShadow(
              color: scheme.neoShadowLight,
              offset: const Offset(-5, -5),
              blurRadius: 12,
            ),
          ],
        ),
        child: child,
      );
    }

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: base,
        borderRadius: br,
        border: Border.all(color: JC.border.withValues(alpha: 0.7), width: 0.8),
      ),
      child: child,
    );
  }
}
