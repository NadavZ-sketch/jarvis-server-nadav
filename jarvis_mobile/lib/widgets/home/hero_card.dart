import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';
import '../markdown_lite.dart';

/// Greeting hero card. Shows: greeting + date line + optional briefing section.
/// Briefing is expanded when content is available, collapsed when empty.
/// Clock removed — no Timer.periodic, pure StatelessWidget.
class HeroCard extends StatelessWidget {
  final HomeController c;
  const HeroCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final greeting = dynamicGreeting(c.settings.userName);
    final hero = c.dashboardContext?['heroCard'] as Map<String, dynamic>?;
    final heroText = (hero?['text'] as String?)?.trim();
    final subtitle = (heroText != null && heroText.isNotEmpty)
        ? heroText
        : (c.todayMessage.isNotEmpty ? c.todayMessage : todayDateLine());

    final todayRemCount = c.remindersForOffset(0).length;
    final hasBriefing = c.briefing != null && c.briefing!.trim().isNotEmpty;
    final accent = JC.blue500;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.22),
            JC.surface.withValues(alpha: 0.95),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent.withValues(alpha: 0.28),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Greeting row ──────────────────────────────────────────────────
          Row(
            children: [
              Text(greetingEmoji(), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting,
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Heebo',
                        )),
                    const SizedBox(height: 2),
                    Text(todayDateLine(),
                        style: TextStyle(
                          color: JC.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                          fontFamily: 'Heebo',
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Stats chips ───────────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip(subtitle, JC.blue400),
              if (c.highPriorityCount > 0)
                _chip('${c.highPriorityCount} דחופות', const Color(0xFFEF4444)),
              if (todayRemCount > 0)
                _chip('$todayRemCount תזכורות היום', const Color(0xFFF59E0B)),
            ],
          ),
          // ── Briefing section (AnimatedSize) ───────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: hasBriefing || c.briefingLoading
                ? _BriefingSection(
                    text: c.briefing,
                    loading: c.briefingLoading,
                    onRefresh: () => c.refreshBriefing(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            )),
      ]),
    );
  }
}

class _BriefingSection extends StatelessWidget {
  final String? text;
  final bool loading;
  final VoidCallback onRefresh;
  const _BriefingSection({required this.text, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: JC.blue500.withValues(alpha: 0.15),
            width: 0.6,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: loading
                  ? Text('מכין סיכום יומי...',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo'))
                  : MarkdownLite(
                      text: text ?? '',
                      textDirection: TextDirection.rtl,
                      baseStyle: TextStyle(
                        color: JC.textSecondary,
                        fontSize: 12,
                        height: 1.6,
                        fontFamily: 'Heebo',
                      ),
                    ),
            ),
            if (!loading)
              GestureDetector(
                onTap: onRefresh,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.refresh_rounded, size: 14, color: JC.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
