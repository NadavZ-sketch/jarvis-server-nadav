import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../main.dart' show JarvisState;

/// Premium AI-core orb for Jarvis.
///
/// Visual language: plasma sine waves span the FULL width of the widget
/// and pass through a central sphere made of thin concentric rings.
/// A bright central star sits at the convergence point.
/// Width fills the parent; only [size] (height) is specified by the caller.
///
/// States:
///  idle      — gentle, slow waves; slow breathing rings; subtle particle drift.
///  listening — waves expand in response to [level]; star brightens.
///  thinking  — rings rotate as dashed arcs; particles orbit inward.
///  speaking  — fast, sharper wave with rhythmic amplitude pulses.
///  complete  — calm core + animated checkmark.
class JarvisOrb extends StatefulWidget {
  final JarvisState state;

  /// Raw mic level from speech_to_text (0..~10). Only relevant in [listening].
  final double level;

  /// Height of the widget. Width fills the available parent space.
  final double size;

  const JarvisOrb({
    super.key,
    required this.state,
    this.level = 0,
    this.size = 200,
  });

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  late final List<_Particle> _particles;

  double _amp = 0;
  double _completeT = 0;
  JarvisState _prevState = JarvisState.idle;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    final rnd = math.Random(42);
    _particles = List.generate(32, (i) => _Particle(
      x:       rnd.nextDouble(),
      y:       0.08 + rnd.nextDouble() * 0.84,
      size:    0.6 + rnd.nextDouble() * 1.8,
      speed:   0.08 + rnd.nextDouble() * 0.28,
      phase:   rnd.nextDouble() * math.pi * 2,
      twinkle: rnd.nextDouble() * math.pi * 2,
    ));

    _clock.addListener(_tick);
  }

  void _tick() {
    final target = widget.state == JarvisState.listening
        ? (widget.level.clamp(0.0, 10.0) / 10.0)
        : (widget.state == JarvisState.speaking ? 0.60 : 0.0);

    if (widget.state != _prevState) {
      if (widget.state == JarvisState.complete) _completeT = 0;
      _prevState = widget.state;
    }
    if (widget.state == JarvisState.complete) {
      _completeT = (_completeT + 0.016).clamp(0.0, 2.0);
    }

    setState(() => _amp = _amp + (target - _amp) * 0.15);
  }

  @override
  void dispose() {
    _clock
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: widget.size,
        child: CustomPaint(
          painter: _OrbPainter(
            t: _clock.value,
            state: widget.state,
            amp: _amp,
            particles: _particles,
            completeT: _completeT,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Particle {
  final double x, y, size, speed, phase, twinkle;
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.twinkle,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class _OrbPainter extends CustomPainter {
  final double t;
  final JarvisState state;
  final double amp;
  final List<_Particle> particles;
  final double completeT;

  const _OrbPainter({
    required this.t,
    required this.state,
    required this.amp,
    required this.particles,
    required this.completeT,
  });

  // ── Palette: white / icy-blue / soft-cyan / electric-blue ─────────────────
  static const _white    = Color(0xFFFFFFFF);
  static const _icy      = Color(0xFFBAE6FD);
  static const _cyan     = Color(0xFF67E8F9);
  static const _electric = Color(0xFF38BDF8);
  static const _indigo   = Color(0xFF818CF8);
  static const _deep     = Color(0xFF0F172A); // near-black navy for glow base

  Color get _accent {
    switch (state) {
      case JarvisState.listening: return _icy;
      case JarvisState.thinking:  return _indigo;
      case JarvisState.speaking:  return _cyan;
      case JarvisState.complete:  return _electric;
      default:                    return _electric;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width  / 2;
    final cy     = size.height / 2;
    final center = Offset(cx, cy);
    final time   = t * math.pi * 2;              // 0..2π per loop
    final accent = _accent;
    final breath = 0.5 + 0.5 * math.sin(time * 0.8);

    // Orb radius (for the rings / star / check — NOT the waves)
    final orbR = math.min(cx, cy) * 0.90;

    _paintAmbientGlow(canvas, center, orbR, accent, breath);
    _paintRings(canvas, center, orbR, accent, time, breath);
    _paintParticles(canvas, size, center, orbR, accent, time);
    _paintPlasmaWaves(canvas, size, center, accent, time);
    _paintCentralStar(canvas, center, accent, breath, time);
    if (state == JarvisState.complete) {
      _paintCheck(canvas, center, orbR * 0.52, accent);
    }
  }

  // ── Ambient glow ────────────────────────────────────────────────────────────
  void _paintAmbientGlow(
      Canvas canvas, Offset c, double r, Color accent, double breath) {
    final glowR = r * (1.55 + 0.12 * breath);
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = ui.Gradient.radial(c, glowR, [
          accent.withValues(alpha: 0.18),
          accent.withValues(alpha: 0.04),
          accent.withValues(alpha: 0.0),
        ], [0.0, 0.55, 1.0]),
    );
  }

  // ── Concentric rings ────────────────────────────────────────────────────────
  void _paintRings(Canvas canvas, Offset c, double r, Color accent,
      double time, double breath) {
    const radFractions = [0.50, 0.75, 1.00];
    const alphas       = [0.40, 0.24, 0.14];
    final isThinking   = state == JarvisState.thinking;

    for (var i = 0; i < radFractions.length; i++) {
      final rad = r * radFractions[i] *
          (state == JarvisState.idle ? (1 + 0.018 * math.sin(time + i)) : 1.0);

      final paint = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color       = accent.withValues(alpha: alphas[i]);

      if (isThinking) {
        final dir   = i.isEven ? 1.0 : -1.0;
        final start = time * (0.55 + i * 0.2) * dir;
        for (var s = 0; s < 3; s++) {
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: rad),
            start + s * math.pi * 2 / 3,
            math.pi * 2 / 3 * 0.58,
            false,
            paint,
          );
        }
      } else {
        canvas.drawCircle(c, rad, paint);
      }
    }
  }

  // ── Particles / stars ───────────────────────────────────────────────────────
  void _paintParticles(Canvas canvas, Size size, Offset c, double r,
      Color accent, double time) {
    final isThinking = state == JarvisState.thinking;

    for (final p in particles) {
      double px, py;

      if (isThinking) {
        // Orbit inward
        final cycle = (time * p.speed + p.phase) % (math.pi * 2);
        final rad   = r * (0.30 + 0.70 * (0.5 + 0.5 * math.cos(cycle)));
        final angle = p.phase * math.pi * 2 + time * p.speed * 1.6;
        px = c.dx + math.cos(angle) * rad;
        py = c.dy + math.sin(angle) * rad * 0.58;
      } else {
        // Gentle drift
        px = p.x * size.width  + math.sin(time * p.speed       + p.phase) * 9;
        py = p.y * size.height + math.cos(time * p.speed * 0.7 + p.phase) * 6;
      }

      // Particles near the horizontal center line are brighter white
      final nearCenter = (py - c.dy).abs() / (size.height / 2);
      final twinkle =
          0.25 + 0.55 * (0.5 + 0.5 * math.sin(time * 1.6 + p.twinkle));
      final color = nearCenter < 0.3 ? _white : accent;

      canvas.drawCircle(
        Offset(px, py),
        p.size,
        Paint()
          ..color      = color.withValues(alpha: twinkle * 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  // ── Plasma waves — the KEY element; spans full width ───────────────────────
  void _paintPlasmaWaves(
      Canvas canvas, Size size, Offset c, Color accent, double time) {
    // Determine amplitude & speed from state
    double baseAmp;
    double speed;
    switch (state) {
      case JarvisState.listening:
        baseAmp = 0.065 + amp * 0.30;
        speed   = 2.8;
        break;
      case JarvisState.speaking:
        baseAmp = 0.13 + 0.07 * (0.5 + 0.5 * math.sin(time * 5));
        speed   = 4.5;
        break;
      case JarvisState.thinking:
        baseAmp = 0.045;
        speed   = 0.9;
        break;
      case JarvisState.complete:
        baseAmp = 0.035;
        speed   = 1.1;
        break;
      default: // idle
        baseAmp = 0.038;
        speed   = 1.4;
    }

    final h = size.height;

    // Each row: [phaseOffset, freqMul, ampScale, alpha, strokeW, blurSigma]
    // Drawn back-to-front: blurry background layers first, crisp front last.
    final layers = <List<double>>[
      [-0.7, 0.65, 0.65, 0.12, 2.0, 4.5],
      [ 1.2, 1.50, 0.55, 0.15, 1.8, 3.5],
      [-0.2, 0.85, 0.80, 0.28, 2.0, 2.5],
      [ 0.5, 1.20, 0.90, 0.45, 2.0, 1.4],
      [ 0.0, 1.00, 1.00, 0.92, 2.5, 0.5],  // foreground
    ];

    for (final layer in layers) {
      final phaseOff = layer[0];
      final freqMul  = layer[1];
      final ampScale = layer[2];
      final alpha    = layer[3];
      final strokeW  = layer[4];
      final blur     = layer[5];

      final ampPx = baseAmp * h * ampScale;

      final path = Path();
      const steps = 140;
      for (var i = 0; i <= steps; i++) {
        final fx = i / steps;                         // 0..1
        final x  = fx * size.width;

        // Bell-curve envelope: tallest at centre, falls off toward edges.
        // Using a smooth raised cosine so the fade is gradual.
        final env = math.sin(fx * math.pi);

        final y = c.dy +
            math.sin(fx * 5 * math.pi * freqMul - time * speed + phaseOff) *
                ampPx *
                env;

        if (i == 0) path.moveTo(x, y);
        else        path.lineTo(x, y);
      }

      // Foreground layers are whiter; background layers lean toward accent.
      final waveColor =
          Color.lerp(_white, accent, alpha > 0.7 ? 0.10 : 0.45)!;

      canvas.drawPath(
        path,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap   = StrokeCap.round
          ..strokeJoin  = StrokeJoin.round
          ..color       = waveColor.withValues(alpha: alpha)
          ..maskFilter  = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }
  }

  // ── Central bright star ─────────────────────────────────────────────────────
  void _paintCentralStar(
      Canvas canvas, Offset c, Color accent, double breath, double time) {
    final isActive = state == JarvisState.listening ||
        state == JarvisState.speaking;
    final brightness = isActive ? 1.0 : (0.65 + 0.35 * breath);

    // Large outer bloom
    final bloomR = 48.0 + 10 * breath;
    canvas.drawCircle(
      c,
      bloomR,
      Paint()
        ..shader = ui.Gradient.radial(c, bloomR, [
          accent.withValues(alpha: 0.50 * brightness),
          accent.withValues(alpha: 0.12 * brightness),
          accent.withValues(alpha: 0.0),
        ], [0.0, 0.45, 1.0]),
    );

    // Inner soft halo
    canvas.drawCircle(
      c,
      20,
      Paint()
        ..shader = ui.Gradient.radial(c, 20, [
          _white.withValues(alpha: 0.88 * brightness),
          accent.withValues(alpha: 0.65 * brightness),
        ])
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // Sharp bright core
    canvas.drawCircle(
      c,
      7,
      Paint()..color = _white.withValues(alpha: brightness),
    );

    // Starburst: 4 major rays + 4 minor diagonal rays
    final rayPaint = Paint()
      ..style    = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 8; i++) {
      final angle   = i * math.pi / 4;
      final isMajor = i % 2 == 0;
      final inner   = 9.0;
      final outer   = isMajor ? 26.0 + 6 * breath : 17.0 + 3 * breath;
      final a       = (isMajor ? 0.90 : 0.45) * brightness;

      rayPaint
        ..strokeWidth = isMajor ? 1.6 : 1.0
        ..color       = _white.withValues(alpha: a)
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 0.8);

      canvas.drawLine(
        Offset(c.dx + math.cos(angle) * inner, c.dy + math.sin(angle) * inner),
        Offset(c.dx + math.cos(angle) * outer, c.dy + math.sin(angle) * outer),
        rayPaint,
      );
    }
  }

  // ── Complete-state checkmark ─────────────────────────────────────────────────
  void _paintCheck(Canvas canvas, Offset c, double r, Color accent) {
    final prog = (completeT / 0.55).clamp(0.0, 1.0);
    if (prog <= 0) return;

    // Expanding confirmation ring
    final ringProg = (completeT / 0.9).clamp(0.0, 1.0);
    if (ringProg < 1.0) {
      canvas.drawCircle(
        c,
        r * ringProg,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color       = _electric.withValues(alpha: (1 - ringProg) * 0.55),
      );
    }

    final s  = r * 0.48;
    final p1 = Offset(c.dx - s * 0.80, c.dy + s * 0.05);
    final p2 = Offset(c.dx - s * 0.18, c.dy + s * 0.60);
    final p3 = Offset(c.dx + s * 0.88, c.dy - s * 0.52);

    final paint = Paint()
      ..style      = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap  = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color      = _white.withValues(alpha: 0.95);

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (prog < 0.5) {
      final f = prog / 0.5;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final f = (prog - 0.5) / 0.5;
      path.lineTo(p2.dx + (p3.dx - p2.dx) * f, p2.dy + (p3.dy - p2.dy) * f);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
