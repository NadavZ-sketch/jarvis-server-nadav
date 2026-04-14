import 'package:flutter/material.dart';
import '../main.dart' show JC;

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JC.surfaceAlt,
                border: Border.all(color: JC.border, width: 1),
              ),
              child: Icon(icon, size: 32, color: JC.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: JC.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Heebo',
              ),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: JC.textMuted,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
