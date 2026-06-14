import 'package:flutter/material.dart';

/// `JD` — shared spacing / radius / typography tokens for a consistent visual
/// rhythm across the home screen (and beyond). Colors live in [JC]; this is the
/// dimensional counterpart hinted at by the `TODO(theming)` in jarvis_theme.dart.
///
/// Spacing is theme-agnostic (the same 4/8/12/16/20 step regardless of palette),
/// so these are plain compile-time constants rather than a swappable shim.
class JD {
  JD._();

  // ── Spacing scale (logical pixels) ──
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  // ── Corner radii ──
  static const double rSm = 10;
  static const double rMd = 12;
  static const double rLg = 16;

  // ── Typography sizes ──
  static const double display = 22; // hero greeting
  static const double title = 14; // card titles
  static const double body = 13; // primary body text
  static const double label = 12; // chips / captions
  static const double lineHeight = 1.5;

  // ── Convenience EdgeInsets (directional-safe; symmetric values) ──
  /// Default padding inside a card body.
  static const EdgeInsets cardPad = EdgeInsets.all(lg);

  /// Gap between stacked sections within a card.
  static const SizedBox gapMd = SizedBox(height: md);
  static const SizedBox gapSm = SizedBox(height: sm);
  static const SizedBox gapLg = SizedBox(height: lg);
}
