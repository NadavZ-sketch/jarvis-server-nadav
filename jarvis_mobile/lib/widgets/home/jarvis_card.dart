import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../theme/jarvis_dimens.dart';
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// A single proactive "daily tip" from Jarvis — time-of-day aware. Deliberately
/// minimal: one insight line, a refresh, and a tap target that opens the full
/// conversation in the Chat tab (so the home card stays calm and uncluttered).
class JarvisCard extends StatelessWidget {
  final HomeController c;
  const JarvisCard(this.c, {super.key});

  void _openChat() => c.onNavigateToChat?.call(
      command: c.jarvisInsight.trim().isEmpty ? null : c.jarvisInsight.trim());

  @override
  Widget build(BuildContext context) {
    final mode = c.insightMode;
    final hasTip = c.jarvisInsight.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasTip ? _openChat : null,
        borderRadius: BorderRadius.circular(JD.rLg),
        child: Ink(
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(JD.rLg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(mode),
              Divider(color: JC.border, height: 1),
              Padding(
                padding: JD.cardPad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _body(),
                    if (hasTip) ...[
                      JD.gapMd,
                      _openChatRow(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(InsightMode mode) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(JD.lg, JD.lg, JD.md, JD.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(JD.rSm),
            ),
            child: Center(
                child: Text(mode.emoji, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: JD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mode.label,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: JD.title,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    )),
                Text(mode.subtitle,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: JD.label,
                        fontFamily: 'Heebo')),
              ],
            ),
          ),
          _iconBtn(Icons.refresh_rounded, () => c.loadJarvisInsight(fresh: true)),
        ],
      ),
    );
  }

  Widget _body() {
    if (c.insightLoading && c.jarvisInsight.trim().isEmpty) {
      return const CardSkeleton(lines: 2);
    }
    if (c.insightError != null && c.jarvisInsight.trim().isEmpty) {
      return InlineError(
          message: c.insightError!,
          onRetry: () => c.loadJarvisInsight(fresh: true));
    }
    if (c.jarvisInsight.trim().isEmpty) {
      return const EmptyState(message: 'אין תובנה כרגע');
    }
    return Text(
      c.jarvisInsight.trim(),
      style: TextStyle(
        color: JC.textSecondary,
        fontSize: JD.body + 0.5,
        height: JD.lineHeight + 0.05,
        fontFamily: 'Heebo',
      ),
      textDirection: TextDirection.rtl,
    );
  }

  Widget _openChatRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('המשך בשיחה',
            style: TextStyle(
              color: const Color(0xFF818CF8),
              fontSize: JD.label,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(width: JD.xs),
        const Icon(Icons.arrow_back_rounded,
            size: 14, color: Color(0xFF818CF8)),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.1),
          borderRadius: BorderRadius.circular(JD.sm),
        ),
        child: Icon(icon, color: const Color(0xFF6366F1), size: 14),
      ),
    );
  }
}
