import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Daily AI productivity tip, grounded in the user's current load.
class InsightCard extends StatelessWidget {
  final HomeController c;
  const InsightCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
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
                  child: const Center(child: Text('✨', style: TextStyle(fontSize: 18))),
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
                GestureDetector(
                  onTap: c.loadJarvisInsight,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        color: Color(0xFF6366F1), size: 14),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: c.insightLoading
                ? const CardSkeleton(lines: 2)
                : c.insightError != null
                    ? InlineError(
                        message: c.insightError!, onRetry: c.loadJarvisInsight)
                    : Text(
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
          ),
        ],
      ),
    );
  }
}
