import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Daily AI productivity tip, grounded in the user's load, with interactive
/// actions: regenerate, steer by topic, turn into a task, continue in chat,
/// and 👍/👎 feedback.
class InsightCard extends StatelessWidget {
  final HomeController c;
  const InsightCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final hasInsight = !c.insightLoading &&
        c.insightError == null &&
        c.jarvisInsight.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Center(child: Text('✨', style: TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('תובנה מג׳רוויס',
                          style: TextStyle(
                            color: JC.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Heebo',
                          )),
                      Text('טיפ יומי לפרודוקטיביות',
                          style: TextStyle(
                              color: JC.textMuted,
                              fontSize: 11,
                              fontFamily: 'Heebo')),
                    ],
                  ),
                ),
                _iconBtn(Icons.refresh_rounded, c.loadJarvisInsight),
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topicChips(),
                const SizedBox(height: 10),
                if (c.insightLoading)
                  const CardSkeleton(lines: 2)
                else if (c.insightError != null)
                  InlineError(
                      message: c.insightError!, onRetry: c.loadJarvisInsight)
                else
                  Text(
                    c.jarvisInsight.isNotEmpty
                        ? c.jarvisInsight
                        : 'לא ניתן לטעון תובנה כרגע',
                    style: const TextStyle(
                      color: Color(0xFF818CF8),
                      fontSize: 13.5,
                      height: 1.55,
                      fontFamily: 'Heebo',
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (hasInsight) ...[
                  const SizedBox(height: 12),
                  _actions(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topicChips() {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: kInsightTopics.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            return _chip('כללי', c.insightTopic == null,
                () => c.setInsightTopic(null));
          }
          final topic = kInsightTopics[i - 1];
          return _chip(topic, c.insightTopic == topic,
              () => c.setInsightTopic(topic));
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6366F1).withOpacity(0.2)
              : const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF6366F1)
                : JC.border.withOpacity(0.7),
            width: 0.8,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? const Color(0xFF818CF8) : JC.textSecondary,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _action(Icons.add_task_rounded, 'הפוך למשימה', c.insightToTask),
        _action(Icons.chat_bubble_outline_rounded, 'המשך בצ׳אט', () {
          c.onNavigateToChat?.call(
              command: 'בוא נדבר על התובנה הזו: ${c.jarvisInsight}');
        }),
        _action(Icons.thumb_up_alt_outlined, '', () {
          c.showSnack('תודה על המשוב 🙏');
        }),
        _action(Icons.thumb_down_alt_outlined, '', () {
          c.showSnack('תודה, אנסה משהו אחר');
          c.loadJarvisInsight();
        }),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 8 : 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: JC.border.withOpacity(0.7), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: JC.textSecondary),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  color: JC.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600,
                )),
          ],
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.refresh_rounded,
            color: Color(0xFF6366F1), size: 14),
      ),
    );
  }
}
