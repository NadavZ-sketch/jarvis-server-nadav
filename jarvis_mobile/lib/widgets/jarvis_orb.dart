import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../main.dart' show JarvisState;

// ─── Physics constants (directly ported from OREN Three.js prototype) ─────────
const int    _kStrands    = 320;
const int    _kSegments   = 6;
const double _kBaseR      = 1.3;
const double _kMaxLen     = 1.4;
const double _kStiffness  = 0.25;
const double _kDamping    = 0.82;
const double _kFocalLen   = 6.0;   // virtual camera distance

// ─── Mutable 3-D point (zero-alloc physics loop) ──────────────────────────────
class _Pt {
  double x, y, z;
  _Pt(this.x, this.y, this.z);
  _Pt.zero() : x = 0, y = 0, z = 0;
  void copyFrom(_Pt o) { x = o.x; y = o.y; z = o.z; }
  void scaleFrom(_Pt d, double s) { x = d.x * s; y = d.y * s; z = d.z * s; }
}

// ─── One elastic strand ────────────────────────────────────────────────────────
class _Strand {
  final List<_Pt> orig;     // spring rest positions (updated every frame)
  final List<_Pt> pos;      // current positions (physics output)
  final List<_Pt> vel;      // velocities
  final double    lenMul;   // [0.75 .. 1.25]
  final double    voiceSens;// [0.5  .. 2.1 ]

  _Strand({
    required this.orig,
    required this.pos,
    required this.vel,
    required this.lenMul,
    required this.voiceSens,
  });
}

// ─── Public widget ─────────────────────────────────────────────────────────────
class JarvisOrb extends StatefulWidget {
  /// Current assistant state — controls colors, speed, breathing pattern.
  final JarvisState state;

  /// Raw mic level from speech_to_text (0..~10).  Only matters in [listening].
  final double level;

  /// Height of the widget; width fills the parent.
  final double size;

  /// Called after the explosion fires (e.g. navigate away).
  final VoidCallback? onTap;

  /// When non-null, overrides the per-state strand root colour.
  final Color? baseColorOverride;

  /// When non-null, overrides the per-state strand tip colour.
  final Color? tipColorOverride;

  /// Multiplier for how strongly strands react to voice (0.2 – 2.5).
  final double voiceSensitivity;

  /// Multiplier for drag-rotation speed (0.2 – 2.5).
  final double rotationSensitivity;

  /// When false, tapping the orb does not trigger the explosion pulse.
  final bool explosionEnabled;

  const JarvisOrb({
    super.key,
    required this.state,
    this.level = 0,
    this.size  = 200,
    this.onTap,
    this.baseColorOverride,
    this.tipColorOverride,
    this.voiceSensitivity = 1.0,
    this.rotationSensitivity = 1.0,
    this.explosionEnabled = true,
  });

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // ── 3-D geometry ──────────────────────────────────────────────────────────
  late final List<_Pt>     _dirs;    // unit Fibonacci-sphere directions
  late final List<_Strand> _strands;

  // ── Colors ────────────────────────────────────────────────────────────────
  Color _curBase = const Color(0xFF666666);
  Color _curTip  = const Color(0xFFFFFFFF);
  Color _tgtBase = const Color(0xFF666666);
  Color _tgtTip  = const Color(0xFFFFFFFF);

  static const _stateColors = <JarvisState, List<Color>>{
    JarvisState.idle:      [Color(0xFF666666), Color(0xFFFFFFFF)],
    JarvisState.listening: [Color(0xFF004488), Color(0xFF44CCFF)],
    JarvisState.thinking:  [Color(0xFF003366), Color(0xFF00FFCC)],
    JarvisState.speaking:  [Color(0xFF660033), Color(0xFFFF44AA)],
    JarvisState.complete:  [Color(0xFF0A3366), Color(0xFF38BDF8)],
  };

  // ── Rotation ──────────────────────────────────────────────────────────────
  double _rotX    = 0.0;
  double _rotY    = 0.0;
  double _velX    = 0.0003;
  double _velY    = 0.0007;
  bool   _panning = false;

  // ── Physics scalars ───────────────────────────────────────────────────────
  double _voice      = 0.0;  // smoothed amplitude 0..1
  double _expl       = 0.0;  // explosion spring force (decays)
  double _explFlash  = 0.0;  // visual brightness flash (decays)
  double _time       = 0.0;  // seconds since init
  double _completeT  = 0.0;  // seconds inside 'complete' state (for checkmark)

  Duration? _prev;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _buildStrands();
    _applyStateColors(widget.state, instant: true);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant JarvisOrb old) {
    super.didUpdateWidget(old);
    final colorsChanged = old.baseColorOverride != widget.baseColorOverride ||
        old.tipColorOverride != widget.tipColorOverride;
    if (old.state != widget.state || colorsChanged) {
      _applyStateColors(widget.state);
      if (old.state != widget.state &&
          widget.state == JarvisState.listening) {
        _triggerExplosion();
      }
      if (widget.state == JarvisState.complete) _completeT = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────

  void _applyStateColors(JarvisState s, {bool instant = false}) {
    final c = _stateColors[s]!;
    _tgtBase = widget.baseColorOverride ?? c[0];
    _tgtTip  = widget.tipColorOverride ?? c[1];
    if (instant) { _curBase = _tgtBase; _curTip = _tgtTip; }
  }

  void _triggerExplosion() {
    if (!widget.explosionEnabled) return;
    _expl      = 1.5;
    _explFlash = 1.0;
  }

  // ── Fibonacci sphere distribution ─────────────────────────────────────────
  void _buildStrands() {
    final rnd = math.Random(42);
    _dirs = List.generate(_kStrands, (i) {
      final phi   = math.acos(1 - 2 * (i + 0.5) / _kStrands);
      final theta = math.pi * (1 + math.sqrt(5)) * (i + 0.5);
      return _Pt(
        math.sin(phi) * math.cos(theta),
        math.sin(phi) * math.sin(theta),
        math.cos(phi),
      );
    });

    _strands = List.generate(_kStrands, (i) {
      final d = _dirs[i];
      return _Strand(
        lenMul:   0.75 + rnd.nextDouble() * 0.5,
        voiceSens: 0.5 + rnd.nextDouble() * 1.6,
        orig: List.generate(_kSegments, (j) {
          final l = _kBaseR + _kMaxLen * j / (_kSegments - 1);
          return _Pt(d.x * l, d.y * l, d.z * l);
        }),
        pos: List.generate(_kSegments, (j) {
          final l = _kBaseR + _kMaxLen * j / (_kSegments - 1);
          return _Pt(d.x * l, d.y * l, d.z * l);
        }),
        vel: List.generate(_kSegments, (_) => _Pt.zero()),
      );
    });
  }

  // ── Ticker callback ───────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    if (_prev == null) { _prev = elapsed; return; }
    final dt = (elapsed - _prev!).inMilliseconds / 1000.0;
    _prev = elapsed;
    _time += dt;

    // Color lerp
    _curBase = Color.lerp(_curBase, _tgtBase, 0.08)!;
    _curTip  = Color.lerp(_curTip,  _tgtTip,  0.08)!;

    // Complete timer
    if (widget.state == JarvisState.complete) _completeT += dt;

    // Voice amplitude target
    double vTarget = 0;
    if (widget.state == JarvisState.listening) {
      vTarget = widget.level.clamp(0.0, 10.0) / 10.0;
    } else if (widget.state == JarvisState.speaking) {
      vTarget = math.max(
        0,
        math.sin(_time * 8.0) * math.cos(_time * 3.0) * 0.8 + 0.2,
      );
    }
    _voice += (vTarget - _voice) * 0.15;

    // Explosion decay
    if (_expl > 0)      { _expl      *= 0.92; if (_expl < 0.01)      _expl = 0; }
    if (_explFlash > 0) { _explFlash -= 0.02; if (_explFlash < 0)  _explFlash = 0; }

    // Rotation auto-spin (state-aware speed)
    if (!_panning) {
      _velX *= 0.985; _velY *= 0.985;
      final tx = widget.state == JarvisState.thinking ? 0.002 :
                 widget.state == JarvisState.listening ? 0.0001 : 0.0003;
      final ty = widget.state == JarvisState.thinking ? 0.005 :
                 widget.state == JarvisState.listening ? 0.0002 : 0.0007;
      if (_velX.abs() < tx) _velX = tx;
      if (_velY.abs() < ty) _velY = ty;
    }
    _rotX += _velX;
    _rotY += _velY;

    // Spring physics
    _stepPhysics();

    if (mounted) setState(() {});
  }

  // ── Spring physics (direct port from OREN JS) ─────────────────────────────
  void _stepPhysics() {
    for (var i = 0; i < _kStrands; i++) {
      final st = _strands[i];
      final d  = _dirs[i];

      // Breathing pattern per state
      double breath = 0;
      switch (widget.state) {
        case JarvisState.idle:
          breath = math.sin(_time * 2.5 + i * 0.1) * 0.08;
          break;
        case JarvisState.listening:
          breath = math.sin(_time * 4.0 + i * 0.1) * 0.03;
          break;
        case JarvisState.thinking:
          breath = math.sin(_time * 12.0 + i * 0.5) * 0.07;
          break;
        default:
          breath = math.sin(_time * 2.5 + i * 0.1) * 0.08;
      }

      final voiceR = (widget.state == JarvisState.speaking ||
                      widget.state == JarvisState.listening)
          ? _voice * st.voiceSens * 2.2 * widget.voiceSensitivity
          : 0.0;

      final dynLen = _kMaxLen * st.lenMul * (0.9 + breath + voiceR + _expl);

      for (var j = 1; j < _kSegments; j++) {
        final ratio = j / (_kSegments - 1);
        st.orig[j].scaleFrom(d, _kBaseR + dynLen * ratio);

        // Spring: F = k*(target - current)
        final fx = st.orig[j].x - st.pos[j].x;
        final fy = st.orig[j].y - st.pos[j].y;
        final fz = st.orig[j].z - st.pos[j].z;

        st.vel[j].x = (st.vel[j].x + fx * _kStiffness) * _kDamping;
        st.vel[j].y = (st.vel[j].y + fy * _kStiffness) * _kDamping;
        st.vel[j].z = (st.vel[j].z + fz * _kStiffness) * _kDamping;

        st.pos[j].x += st.vel[j].x;
        st.pos[j].y += st.vel[j].y;
        st.pos[j].z += st.vel[j].z;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) {
        _panning = true;
        _velX = d.delta.dy * 0.005 * widget.rotationSensitivity;
        _velY = d.delta.dx * 0.005 * widget.rotationSensitivity;
      },
      onPanEnd: (_) {
        _panning = false;
        _velX *= 0.5;
        _velY *= 0.5;
      },
      onTap: () {
        _triggerExplosion();
        widget.onTap?.call();
      },
      child: RepaintBoundary(
        child: SizedBox(
          width: double.infinity,
          height: widget.size,
          child: CustomPaint(
            painter: _OrbPainter(
              strands:    _strands,
              rotX:       _rotX,
              rotY:       _rotY,
              curBase:    _curBase,
              curTip:     _curTip,
              voiceAmp:   _voice,
              explFlash:  _explFlash,
              state:      widget.state,
              completeT:  _completeT,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CustomPainter ─────────────────────────────────────────────────────────────
class _OrbPainter extends CustomPainter {
  final List<_Strand> strands;
  final double rotX, rotY;
  final Color  curBase, curTip;
  final double voiceAmp, explFlash;
  final JarvisState state;
  final double completeT;

  const _OrbPainter({
    required this.strands,
    required this.rotX,
    required this.rotY,
    required this.curBase,
    required this.curTip,
    required this.voiceAmp,
    required this.explFlash,
    required this.state,
    required this.completeT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx  = size.width  / 2;
    final cy  = size.height / 2;
    // Scale: pixels per unit. Make the orb fill ~80% of the shorter dimension.
    final sc  = math.min(size.width, size.height) * 0.40;

    // Pre-compute rotation trig (shared by all 320×6 points)
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final cosY = math.cos(rotY), sinY = math.sin(rotY);

    // Pre-compute one color per segment position (5 steps, reused for every strand)
    const seg = _kSegments;
    final segColors = List.generate(seg - 1, (j) {
      final r = (j + 0.5) / (seg - 1);
      Color c = Color.lerp(curBase, curTip, r)!;
      if (explFlash > 0) {
        c = Color.lerp(c, const Color(0xFFFFFFFF), explFlash * 0.6)!;
      }
      if (voiceAmp > 0.05) {
        final boost = (voiceAmp * 0.3 * r).clamp(0.0, 0.35);
        c = c.withValues(alpha: (c.alpha / 255.0 + boost).clamp(0.0, 1.0));
      }
      return c.withValues(alpha: 0.88);
    });

    final paint = Paint()
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..blendMode   = BlendMode.plus;  // additive — strands sum to bright center

    for (final st in strands) {
      for (var j = 0; j < seg - 1; j++) {
        final pa = st.pos[j];
        final pb = st.pos[j + 1];

        // ── Rotate A (Y then X) ───────────────────────────────────────────
        final axY = pa.x * cosY + pa.z * sinY;
        final ayY = pa.y;
        final azY = -pa.x * sinY + pa.z * cosY;
        final aFx = axY;
        final aFy = ayY * cosX - azY * sinX;
        final aFz = ayY * sinX + azY * cosX; // z in camera space
        final dA  = _kFocalLen - aFz;        // depth (camera at +kFocalLen)
        if (dA < 0.1) continue;
        final sA  = _kFocalLen / dA * sc;
        final ax  = cx + aFx * sA;
        final ay  = cy - aFy * sA;

        // ── Rotate B ────────────────────────────────────────────────────
        final bxY = pb.x * cosY + pb.z * sinY;
        final byY = pb.y;
        final bzY = -pb.x * sinY + pb.z * cosY;
        final bFx = bxY;
        final bFy = byY * cosX - bzY * sinX;
        final bFz = byY * sinX + bzY * cosX;
        final dB  = _kFocalLen - bFz;
        if (dB < 0.1) continue;
        final sB  = _kFocalLen / dB * sc;
        final bx  = cx + bFx * sB;
        final by  = cy - bFy * sB;

        paint.color = segColors[j];
        canvas.drawLine(Offset(ax, ay), Offset(bx, by), paint);
      }
    }

    // ── Checkmark overlay for 'complete' state ─────────────────────────────
    if (state == JarvisState.complete) {
      _paintCheck(canvas, Offset(cx, cy), sc * 0.3, completeT);
    }
  }

  void _paintCheck(Canvas canvas, Offset c, double r, double t) {
    final prog = (t / 0.55).clamp(0.0, 1.0);
    if (prog <= 0) return;

    // Expanding ring
    final rProg = (t / 0.85).clamp(0.0, 1.0);
    if (rProg < 1.0) {
      canvas.drawCircle(
        c,
        r * rProg,
        Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..blendMode   = BlendMode.srcOver
          ..color       = const Color(0xFF38BDF8).withValues(alpha: (1 - rProg) * 0.55),
      );
    }

    final s  = r * 0.6;
    final p1 = Offset(c.dx - s * 0.80, c.dy + s * 0.05);
    final p2 = Offset(c.dx - s * 0.18, c.dy + s * 0.60);
    final p3 = Offset(c.dx + s * 0.88, c.dy - s * 0.52);

    final path = Path()..moveTo(p1.dx, p1.dy);
    if (prog < 0.5) {
      final f = prog / 0.5;
      path.lineTo(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);
    } else {
      path.lineTo(p2.dx, p2.dy);
      final f = (prog - 0.5) / 0.5;
      path.lineTo(p2.dx + (p3.dx - p2.dx) * f, p2.dy + (p3.dy - p2.dy) * f);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round
        ..blendMode   = BlendMode.srcOver
        ..color       = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => true;
}
