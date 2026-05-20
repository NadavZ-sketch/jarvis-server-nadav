import 'package:flutter/material.dart';
import '../main.dart' show JC;

/// Sticky bottom banner that identifies a screen as a Preview / lab feature.
class PreviewBanner extends StatelessWidget {
  const PreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0B1929),
        border: Border(top: BorderSide(color: JC.border, width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        textDirection: TextDirection.rtl,
        children: const [
          Icon(Icons.science_outlined, size: 14, color: JC.blue400),
          SizedBox(width: 6),
          Text(
            'מעבדת Jarvis · גרסת ניסיון בלבד',
            style: TextStyle(
              color: JC.textMuted,
              fontSize: 11,
              fontFamily: 'Heebo',
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline chip that marks a specific card/section as using demo data.
class DemoChip extends StatelessWidget {
  const DemoChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E4A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JC.blue500, width: 0.6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: 10, color: JC.blue400),
          SizedBox(width: 4),
          Text(
            'דמו',
            style: TextStyle(
              color: JC.blue400,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
