import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../main.dart' show JC;

/// Half-circle gauge that visualises the day's load (0–100).
class LoadGauge extends StatelessWidget {
  final double value; // 0–100
  final String? peakWindow;

  const LoadGauge({super.key, required this.value, this.peakWindow});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          SizedBox(
            width: 84,
            height: 48,
            child: CustomPaint(
              painter: _GaugePainter(value: value, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('עומס היום: ${value.round()}%',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        color: JC.textPrimary,
                        fontFamily: 'Heebo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_loadLabel(value),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        color: color,
                        fontFamily: 'Heebo',
                        fontSize: 11.5)),
                if (peakWindow != null && peakWindow!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.bolt_rounded,
                          size: 12, color: JC.amber400),
                      const SizedBox(width: 3),
                      Text('שיא: $peakWindow',
                          style: TextStyle(
                              color: JC.textMuted,
                              fontFamily: 'Heebo',
                              fontSize: 11)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(double v) {
    if (v < 40) return JC.green500;
    if (v < 75) return JC.amber400;
    return JC.cancelRed;
  }

  static String _loadLabel(double v) {
    if (v < 30) return 'יום קליל';
    if (v < 60) return 'עומס סביר';
    if (v < 85) return 'יום עמוס';
    return 'עומס יתר — שקול לדחות משימות';
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;

  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;
    final radius = size.width / 2 - 4;

    final bg = Paint()
      ..color = JC.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        math.pi, math.pi, false, bg);

    final sweep = math.pi * (value / 100).clamp(0, 1);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        math.pi, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color;
}
