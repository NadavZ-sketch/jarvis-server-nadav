import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Proactive "what to do now" card built from /day-plan: a load gauge, the top
/// urgent+important item, and the AI narrative as a tip.
class NextActionCard extends StatelessWidget {
  final HomeController c;
  const NextActionCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final plan = c.dayPlan;

    Widget body;
    if (c.dayPlanLoading && plan == null) {
      body = const CardSkeleton(lines: 3);
    } else if (plan == null) {
      body = const EmptyState(message: 'לא ניתן לבנות תוכנית יום כרגע');
    } else {
      body = _buildPlan(plan);
    }

    return SectionCard(
      title: 'מה עכשיו',
      icon: Icons.bolt_rounded,
      iconColor: const Color(0xFF3B82F6),
      child: body,
    );
  }

  Widget _buildPlan(Map<String, dynamic> plan) {
    final load = plan['load'] as Map<String, dynamic>?;
    final status = (load?['status'] ?? '').toString();
    final ratio = (load?['ratio'] as num?)?.toDouble() ?? 0.0;
    final quadrants = plan['quadrants'] as Map<String, dynamic>?;
    final now = (quadrants?['now'] as List?) ?? const [];
    final narrative = (plan['narrative'] as String?)?.trim() ?? '';
    final topItem = now.isNotEmpty ? now.first as Map<String, dynamic> : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _loadGauge(status, ratio),
        if (topItem != null) ...[
          const SizedBox(height: 12),
          _topItem(topItem),
        ],
        if (narrative.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(narrative,
              style: TextStyle(
                color: JC.textSecondary,
                fontSize: 12.5,
                height: 1.55,
                fontFamily: 'Heebo',
              )),
        ],
      ],
    );
  }

  Widget _loadGauge(String status, double ratio) {
    final color = _statusColor(status);
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('עומס היום: ${_statusLabel(status)}',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo')),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(children: [
                Container(height: 6, color: JC.track),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(height: 6, color: color),
                ),
              ]),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _topItem(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? '—';
    final priority = item['priority'] as String?;
    final isReminder = (item['type'] ?? '') == 'reminder';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          right: BorderSide(color: Color(0xFF3B82F6), width: 3),
        ),
      ),
      child: Row(children: [
        Icon(isReminder ? Icons.notifications_active_rounded : Icons.flag_rounded,
            color: const Color(0xFF3B82F6), size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: JC.textPrimary,
                fontSize: 13,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600,
              )),
        ),
        if (!isReminder) ...[
          const SizedBox(width: 8),
          PriorityBadge(priority),
        ],
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'overloaded':
      case 'heavy':
        return const Color(0xFFEF4444);
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'empty':
        return JC.textMuted;
      default:
        return const Color(0xFF22C55E);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'overloaded':
        return 'עמוס מאוד';
      case 'heavy':
        return 'כבד';
      case 'moderate':
        return 'בינוני';
      case 'light':
        return 'קל';
      case 'empty':
        return 'פנוי';
      default:
        return status;
    }
  }
}
