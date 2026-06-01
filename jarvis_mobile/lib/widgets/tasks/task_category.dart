import 'package:flutter/material.dart';
import '../../main.dart' show JC;

/// Shared task-category metadata (label, emoji, color) used by the task card,
/// the list filter bar, and the edit sheet. Mirrors the server-side categories
/// in agents/taskAgent.js (work / personal / financial / project / general).
class TaskCategory {
  final String id;
  final String label;
  final String emoji;
  final Color Function() color;

  const TaskCategory(this.id, this.label, this.emoji, this.color);
}

final List<TaskCategory> kTaskCategories = [
  TaskCategory('work', 'עבודה', '💼', () => JC.blue400),
  TaskCategory('project', 'פרויקט', '🚀', () => JC.indigo300),
  TaskCategory('financial', 'פיננסי', '💰', () => JC.amber400),
  TaskCategory('personal', 'אישי', '👤', () => JC.green500),
  TaskCategory('general', 'כללי', '📌', () => JC.textMuted),
];

TaskCategory? categoryById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final c in kTaskCategories) {
    if (c.id == id) return c;
  }
  return null;
}
