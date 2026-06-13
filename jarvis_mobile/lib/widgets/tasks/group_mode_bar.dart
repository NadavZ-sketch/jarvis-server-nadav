import 'package:flutter/material.dart';
import '../../main.dart' show JC;

/// Horizontal chip bar that lets the user pick how the single task list is
/// grouped: by time, priority, category, or flat ("all").
class GroupModeBar extends StatelessWidget {
  final String current; // 'time' | 'priority' | 'category' | 'flat'
  final ValueChanged<String> onChange;
  const GroupModeBar({super.key, required this.current, required this.onChange});

  static const _options = [
    ('time', 'זמן', Icons.schedule_rounded),
    ('priority', 'עדיפות', Icons.flag_rounded),
    ('category', 'קטגוריה', Icons.folder_open_rounded),
    ('flat', 'הכל', Icons.list_alt_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _options)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: GestureDetector(
                onTap: () => onChange(o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: current == o.$1
                        ? JC.blue500.withValues(alpha: 0.18)
                        : JC.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: current == o.$1 ? JC.blue500 : JC.border,
                      width: current == o.$1 ? 1.2 : 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(o.$3,
                          size: 14,
                          color: current == o.$1
                              ? JC.blue400
                              : JC.textSecondary),
                      const SizedBox(width: 5),
                      Text(o.$2,
                          style: TextStyle(
                            color: current == o.$1
                                ? JC.blue400
                                : JC.textSecondary,
                            fontSize: 12.5,
                            fontFamily: 'Heebo',
                            fontWeight: current == o.$1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
