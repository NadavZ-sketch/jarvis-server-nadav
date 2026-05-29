import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../main.dart' show JarvisState;

/// A premium, abstract AI-core orb for the Jarvis voice assistant.
///
/// It is fully custom-painted: a glowing central core, thin concentric
/// "neural" rings, a horizontal audio waveform passing through the center,
/// soft drifting particles, and an outer ambient glow — all on a dark,
/// glassmorphic backdrop.
///
/// Behaviour per [JarvisState]:
///  * idle      — calm core, slow breathing rings, subtle particle drift.
///  * listening — waveform expands with [level]; the core glows brighter.
///  * thinking  — rings rotate, particles pull inward toward the core.
///  * speaking  — sharp rhythmic waveform + soft light pulses moving outward.
///  * complete  — stable calm core with a single confirmation pulse + check.
class JarvisOrb extends StatefulWidget {
  /// Current assistant state.
  final JarvisState state;

  /// Live microphone amplitude. Accepts the raw 0..~10 range reported by
  /// `speech_to_text`; values are clamped/normalised internally.
  final double level;

  /// Diameter of the orb (the painted core fits inside this).
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
  late final AnimationController _clock; // continuous time base (loops)
  late final List<_Particle> _particles;

  // Smoothed amplitude (0..1) so the waveform reacts gently, never jumpy.
  double _amp = 0;

  // Tracks how long we've been in the `complete` state for the check pulse.
  double _completeT = 0;
  JarvisState _prevState = JarvisState.idle;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    final rnd = math.Random(42);
    _particles = List.generate(26, (i) {
      return _Particle(
        angle: rnd.nextDouble() * math.pi * 2,
        radius: 0.42 + rnd.nextDouble() * 0.55, // fraction of orb radius
        size: 0.6 + rnd.nextDouble() * 1.7,
        speed: 0.15 + rnd.nextDouble() * 0.5,
        phase: rnd.nextDouble(),
        twinkle: rnd.nextDouble() * math.pi * 2,
      );
    });

    _clock.addListener(_tick);
  }

  void _tick() {
    // Normalise mic level (0..~10) → 0..1, then ease toward it.
    final target = widget.state == JarvisState.listening
        ? (widget.level.clamp(0.0, 10.0) / 10.0)
        : (widget.state == JarvisState.speaking ? 0.55 : 0.0);
    final next = _amp + (target - _amp) * 0.18;

    if (widget.state == JarvisState.complete) {
      _completeT = (_completeT + 1 / 60).clamp(0.0, 2.0);
    }
    if (widget.state != _prevState) {
      if (widget.state == JarvisState.complete) _completeT = 0;
      _prevState = widget.state;
    }

    if ((next - _amp).abs() > 0.001 ||
        true /* keep repainting for time-driven motion */) {
      setState(() => _amp = next);
    }
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
        width: widget.size,
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

class _Particle {
  final double angle; // base angle around the core
  final double radius; // base distance (fraction of orb radius)
  final double size; // px
  final double speed; // angular drift speed
  final double phase; // 0..1 inward-pull phase offset
  final double twinkle; // brightness oscillation offset
  const _Particle({
    required this.angle,
    required this.radius,
    required this.size,
    required this.speed,
    required this.phase,
    required this.twinkle,
  });
}

class _OrbPainter extends CustomPainter {
  final double t; // 0..1 looping clock
  final JarvisState state;
  final double amp; // smoothed amplitude 0..1
  final List<_Particle> particles;
  final double completeT; // seconds inside complete state

  _OrbPainter({
    required this.t,
    required this.state,
    required this.amp,
    required this.particles,
    required this.completeT,
  });

  // ── Palette: white / icy blue / soft cyan / electric blue ──────────────────
  static const _white = Color(0xFFFFFFFF);
  static const _icy = Color(0xFFBAE6FD);
  static const _cyan = Color(0xFF67E8F9);
  static const _electric = Color(0xFF38BDF8);
  static const _indigo = Color(0xFFA5B4FC);

  Color get _accent {
    switch (state) {
      case JarvisState.listening:
        return _icy;
      case JarvisState.thinking:
        return _indigo;
      case JarvisState.speaking:
        return _cyan;
      case JarvisState.complete:
        return _electric;
      default:
        return _electric;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final R = size.width / 2;
    final time = t * math.pi * 2; // 0..2π over the loop
    final accent = _accent;

    // Breathing factor for the idle/calm core.
    final breath = 0.5 + 0.5 * math.sin(time * 0.9);
    final pulse = state == JarvisState.speaking
        ? (0.5 + 0.5 * math.sin(time * 4))
        : 0.0;

    _paintAmbientGlow(canvas, center, R, accent, breath);
    _paintParticles(canvas, center, R, accent, time);
    _paintRings(canvas, center, R, accent, time, breath);
    _paintOutwardPulses(canvas, center, R, accent, time);
    _paintCore(canvas, center, R, accent, breath, pulse);
    _paintWaveform(canvas, center, R, accent, time);
    if (state == JarvisState.complete) {
      _paintCheck(canvas, center, R, accent);
    }
  }

  void _paintAmbientGlow(
      Canvas canvas, Offset c, double R, Color accent, double breath) {
    final glowR = R * (0.95 + 0.05 * breath);
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        c,
        glowR,
        [
          accent.withValues(alpha: 0.22),
          accent.withValues(alpha: 0.06),
          accent.withValues(alpha: 0.0),
        ],
        [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(c, glowR, paint);
  }

  void _paintParticles(
      Canvas canvas, Offset c, double R, Color accent, double time) {
    final pullIn = state == JarvisState.thinking;
    for (final p in particles) {
      // Slow orbital drift; thinking pulls particles inward rhythmically.
      final a = p.angle + time * p.speed * (pullIn ? 1.6 : 0.5);
      double rad = p.radius;
      if (pullIn) {
        final cycle = (time * 0.5 + p.phase * math.pi * 2) % (math.pi * 2);
        rad = 0.30 + (p.radius - 0.30) * (0.5 + 0.5 * math.cos(cycle));
      } else {
        rad = p.radius + 0.03 * math.sin(time + p.phase * 6);
      }
      final pos = Offset(
        c.dx + math.cos(a) * rad * R,
        c.dy + math.sin(a) * rad * R,
      );
      final twinkle = 0.35 + 0.45 * (0.5 + 0.5 * math.sin(time * 2 + p.twinkle));
      final paint = Paint()
        ..color = (rad > 0.85 ? accent : _white).withValues(alpha: twinkle)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawCircle(pos, p.size, paint);
    }
  }

  void _paintRings(Canvas canvas, Offset c, double R, Color accent, double time,
      double breath) {
    final rotate = state == JarvisState.thinking;
    final ringSpecs = <List<double>>[
      // [radiusFraction, baseAlpha, dashStart]
      [0.55, 0.30, 0.0],
      [0.72, 0.20, 1.2],
      [0.88, 0.13, 2.4],
    ];
    for (var i = 0; i < ringSpecs.length; i++) {
      final spec = ringSpecs[i];
      final breathe = state == JarvisState.idle
          ? (1 + 0.015 * math.sin(time * 0.9 + i))
          : 1.0;
      final radius = spec[0] * R * breathe;
      final alpha = spec[1] * (0.7 + 0.3 * breath);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = accent.withValues(alpha: alpha);

      if (rotate) {
        // Draw rotating dashed arcs for a "radar / neural field" feel.
        final dir = i.isEven ? 1.0 : -1.0;
        final start = time * (0.8 + i * 0.3) * dir + spec[2];
        const segs = 3;
        final sweep = math.pi * 2 / segs * 0.62;
        for (var s = 0; s < segs; s++) {
          final a0 = start + s * (math.pi * 2 / segs);
          canvas.drawArc(
            Rect.fromCircle(center: c, radius: radius),
            a0,
            sweep,
            false,
            paint,
          );
        }
      } else {
        canvas.drawCircle(c, radius, paint);
      }
    }
  }

  void _paintOutwardPulses(
      Canvas canvas, Offset c, double R, Color accent, double time) {
    final emit = state == JarvisState.speaking ||
        (state == JarvisState.complete && completeT < 1.2);
    if (!emit) return;
    const count = 2;
    for (var i = 0; i < count; i++) {
      var prog = (time * 0.5 / math.pi + i / count) % 1.0;
      if (state == JarvisState.complete) {
        // single expanding confirmation ring
        prog = (completeT / 1.2).clamp(0.0, 1.0);
        if (i > 0) continue;
      }
      final radius = R * (0.35 + prog * 0.6);
      final alpha = (1 - prog) * 0.28;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = accent.withValues(alpha: alpha);
      canvas.drawCircle(c, radius, paint);
    }
  }

  void _paintCore(Canvas canvas, Offset c, double R, Color accent, double breath,
      double pulse) {
    final isActive = state == JarvisState.listening ||
        state == JarvisState.speaking ||
        state == JarvisState.thinking;
    final brightness = isActive
        ? 0.85 + 0.15 * (state == JarvisState.speaking ? pulse : breath)
        : 0.6 + 0.25 * breath;

    final coreR = R * (0.34 + 0.02 * breath + (amp * 0.05));

    // Soft halo behind the core.
    canvas.drawCircle(
      c,
      coreR * 1.7,
      Paint()
        ..shader = ui.Gradient.radial(c, coreR * 1.7, [
          accent.withValues(alpha: 0.45 * brightness),
          accent.withValues(alpha: 0.0),
        ]),
    );

    // The glowing core: white-hot center fading to the accent.
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(c.dx - coreR * 0.18, c.dy - coreR * 0.22),
          coreR,
          [
            _white.withValues(alpha: brightness),
            Color.lerp(_white, accent, 0.6)!.withValues(alpha: brightness),
            accent.withValues(alpha: 0.85 * brightness),
          ],
          [0.0, 0.45, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    // Specular highlight for a glassy, dimensional look.
    canvas.drawCircle(
      Offset(c.dx - coreR * 0.32, c.dy - coreR * 0.38),
      coreR * 0.28,
      Paint()..color = _white.withValues(alpha: 0.5 * brightness),
    );
  }

  void _paintWaveform(
      Canvas canvas, Offset c, double R, Color accent, double time) {
    // Base amplitude: tiny in idle, driven by mic in listening, rhythmic when
    // speaking.
    double baseAmp;
    double freq;
    switch (state) {
      case JarvisState.listening:
        baseAmp = 0.06 + amp * 0.30;
        freq = 7;
        break;
      case JarvisState.speaking:
        baseAmp = 0.10 + 0.14 * (0.5 + 0.5 * math.sin(time * 4));
        freq = 9;
        break;
      case JarvisState.idle:
        baseAmp = 0.025;
        freq = 5;
        break;
      default:
        baseAmp = 0.04;
        freq = 6;
    }

    final width = R * 1.3;
    final amplitudePx = baseAmp * R;
    final path = Path();
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final fx = i / steps; // 0..1
      final x = c.dx - width / 2 + fx * width;
      // Envelope: taper toward the edges so it fades into the rings.
      final env = math.sin(fx * math.pi);
      final y = c.dy +
          math.sin(fx * freq * math.pi * 2 - time * 3) * amplitudePx * env;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        Offset(c.dx - width / 2, c.dy),
        Offset(c.dx + width / 2, c.dy),
        [
          accent.withValues(alpha: 0.0),
          _white.withValues(alpha: 0.9),
          accent.withValues(alpha: 0.0),
        ],
        [0.0, 0.5, 1.0],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    canvas.drawPath(path, paint);
  }

  void _paintCheck(Canvas canvas, Offset c, double R, Color accent) {
    final prog = (completeT / 0.6).clamp(0.0, 1.0);
    if (prog <= 0) return;
    final s = R * 0.22;
    // Checkmark anchor points.
    final p1 = Offset(c.dx - s * 0.9, c.dy + s * 0.05);
    final p2 = Offset(c.dx - s * 0.25, c.dy + s * 0.6);
    final p3 = Offset(c.dx + s * 0.95, c.dy - s * 0.55);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _white.withValues(alpha: 0.95);

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (prog < 0.5) {
      final f = prog / 0.5;
      path.lineTo(
          ui.lerpDouble(p1.dx, p2.dx, f)!, ui.lerpDouble(p1.dy, p2.dy, f)!);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final f = (prog - 0.5) / 0.5;
      path.lineTo(
          ui.lerpDouble(p2.dx, p3.dx, f)!, ui.lerpDouble(p2.dy, p3.dy, f)!);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
