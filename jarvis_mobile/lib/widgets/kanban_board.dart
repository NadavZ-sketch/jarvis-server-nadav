import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';

class KanbanBoard extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;
  final String projectId;
  final AppSettings settings;
  final ValueChanged<Map<String, dynamic>>? onTaskUpdated;

  const KanbanBoard({
    super.key,
    required this.tasks,
    required this.projectId,
    required this.settings,
    this.onTaskUpdated,
  });

  @override
  State<KanbanBoard> createState() => _KanbanBoardState();
}

class _KanbanBoardState extends State<KanbanBoard> {
  late List<Map<String, dynamic>> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = widget.tasks
        .map((t) => Map<String, dynamic>.from(t))
        .toList();
  }

  @override
  void didUpdateWidget(KanbanBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      setState(() {
        _tasks = widget.tasks
            .map((t) => Map<String, dynamic>.from(t))
            .toList();
      });
    }
  }

  // ─── WIP warning ────────────────────────────────────────────────────────────

  bool _shouldWarnWip(String col) {
    final counts = <String, int>{
      'todo': 0,
      'in_progress': 0,
      'review': 0,
      'done': 0,
    };
    for (final t in _tasks) {
      final key = t['kanban_column']?.toString() ?? 'todo';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final colCount = counts[col] ?? 0;
    if (colCount == 0) return false;
    final hasEmpty = counts.values.any((c) => c == 0);
    return hasEmpty && colCount > _tasks.length / 2;
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Color _priorityColor(String? p) {
    switch (p) {
      case 'critical':
      case 'high':
        return JC.cancelRed;
      case 'medium':
        return JC.amber400;
      default:
        return JC.green500;
    }
  }

  String _priorityLabel(String? p) {
    switch (p) {
      case 'critical':
        return 'קריטי';
      case 'high':
        return 'גבוה';
      case 'medium':
        return 'בינוני';
      case 'low':
        return 'נמוך';
      default:
        return 'בינוני';
    }
  }

  String _shortDate(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return '';
    return '${d.day}.${d.month}';
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildColumn('todo', 'לביצוע', JC.textMuted),
          _buildColumn('in_progress', 'בתהליך', JC.blue500),
          _buildColumn('review', 'בבדיקה', JC.amber400),
          _buildColumn('done', 'הושלם', JC.green500),
        ],
      ),
    );
  }

  Widget _buildColumn(String key, String label, Color color) {
    final colWidth = MediaQuery.of(context).size.width * 0.75;
    final colTasks = _tasks
        .where((t) => (t['kanban_column']?.toString() ?? 'todo') == key)
        .toList();
    final count = colTasks.length;

    return Container(
      width: colWidth,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Column header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.25), width: 1),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Heebo',
                    color: JC.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // WIP warning banner
          if (_shouldWarnWip(key))
            Container(
              margin: const EdgeInsets.only(top: 6, left: 4, right: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: JC.amber400.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: JC.amber400.withOpacity(0.3)),
              ),
              child: Text(
                '⚠️ הרבה משימות — שקול לאזן',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 10.5,
                  fontFamily: 'Heebo',
                  color: JC.amber400,
                ),
              ),
            ),

          const SizedBox(height: 6),

          // Task cards
          ...colTasks.map((t) => _buildTaskCard(t)),

          // Add task button
          TextButton.icon(
            icon: Icon(Icons.add, size: 16, color: JC.textMuted),
            label: Text(
              'הוסף משימה',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Heebo',
                color: JC.textMuted,
              ),
            ),
            onPressed: () => _showAddTaskSheet(key),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final priority = task['priority']?.toString();
    final dueDate = task['due_date']?.toString();
    final storyPoints = task['story_points'];

    return GestureDetector(
      onTap: () => _showTaskSheet(task),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            right: BorderSide(color: _priorityColor(priority), width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          textDirection: TextDirection.rtl,
          children: [
            Text(
              task['content']?.toString() ?? '',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Heebo',
                color: JC.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              textDirection: TextDirection.rtl,
              children: [
                _priorityBadge(priority),
                const Spacer(),
                if (dueDate != null && dueDate.isNotEmpty)
                  Text(
                    _shortDate(dueDate),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'Heebo',
                      color: JC.textMuted,
                    ),
                  ),
                if (storyPoints != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: JC.indigo500.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${storyPoints}נק׳',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontFamily: 'Heebo',
                        color: JC.indigo300,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityBadge(String? priority) {
    final color = _priorityColor(priority);
    final label = _priorityLabel(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'Heebo',
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ─── Task detail sheet ───────────────────────────────────────────────────────

  void _showTaskSheet(Map<String, dynamic> task) {
    final columns = [
      ('todo', 'לביצוע', JC.textMuted),
      ('in_progress', 'בתהליך', JC.blue500),
      ('review', 'בבדיקה', JC.amber400),
      ('done', 'הושלם', JC.green500),
    ];
    String currentCol =
        task['kanban_column']?.toString() ?? 'todo';
    bool isDone = task['done'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: JC.textMuted.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      task['content']?.toString() ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Move to column
                    Text(
                      'העבר לעמודה:',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Heebo',
                        color: JC.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: columns.map((col) {
                        final (colKey, colLabel, colColor) = col;
                        final selected = currentCol == colKey;
                        return ChoiceChip(
                          label: Text(
                            colLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'Heebo',
                              color: selected
                                  ? JC.onAccent
                                  : JC.textSecondary,
                            ),
                          ),
                          selected: selected,
                          selectedColor: colColor,
                          backgroundColor: JC.surface,
                          side: BorderSide(
                            color: selected
                                ? colColor
                                : JC.textMuted.withOpacity(0.3),
                          ),
                          onSelected: (v) async {
                            if (!v || currentCol == colKey) return;
                            final previousCol = currentCol;
                            setSheetState(() => currentCol = colKey);
                            // Optimistic update
                            setState(() {
                              final idx = _tasks.indexWhere(
                                  (t) => t['id'] == task['id']);
                              if (idx != -1) {
                                _tasks[idx]['kanban_column'] = colKey;
                              }
                              task['kanban_column'] = colKey;
                            });
                            try {
                              final api = ApiService(widget.settings);
                              final taskId =
                                  task['id']?.toString() ?? '';
                              if (taskId.isNotEmpty) {
                                await api.updateTaskKanban(
                                    taskId, colKey);
                                widget.onTaskUpdated?.call(task);
                              }
                            } catch (_) {
                              // Rollback on error
                              setSheetState(
                                  () => currentCol = previousCol);
                              setState(() {
                                final idx = _tasks.indexWhere(
                                    (t) => t['id'] == task['id']);
                                if (idx != -1) {
                                  _tasks[idx]['kanban_column'] =
                                      previousCol;
                                }
                                task['kanban_column'] = previousCol;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Done toggle
                    Row(
                      children: [
                        Text(
                          'סמן כהושלם',
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'Heebo',
                            color: JC.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Switch(
                          value: isDone,
                          activeColor: JC.green500,
                          onChanged: (v) async {
                            setSheetState(() => isDone = v);
                            setState(() {
                              final idx = _tasks.indexWhere(
                                  (t) => t['id'] == task['id']);
                              if (idx != -1) _tasks[idx]['done'] = v;
                              task['done'] = v;
                            });
                            try {
                              final api = ApiService(widget.settings);
                              final taskId =
                                  task['id']?.toString() ?? '';
                              if (taskId.isNotEmpty) {
                                await api.updateTask(taskId, done: v);
                                widget.onTaskUpdated?.call(task);
                              }
                            } catch (_) {
                              // Rollback
                              setSheetState(
                                  () => isDone = !v);
                              setState(() {
                                final idx = _tasks.indexWhere(
                                    (t) => t['id'] == task['id']);
                                if (idx != -1) _tasks[idx]['done'] = !v;
                                task['done'] = !v;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Edit + Delete row
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.edit_outlined,
                                size: 16, color: JC.blue400),
                            label: Text(
                              'ערוך',
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'Heebo',
                                color: JC.blue400,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: JC.blue400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditTaskSheet(task);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _deleteTask(task);
                          },
                          child: Text(
                            'מחק',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              color: JC.cancelRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Edit task sheet ─────────────────────────────────────────────────────────

  void _showEditTaskSheet(Map<String, dynamic> task) {
    final contentCtrl =
        TextEditingController(text: task['content']?.toString() ?? '');
    String selectedPriority =
        task['priority']?.toString() ?? 'medium';

    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: JC.textMuted.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'עריכת משימה',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: contentCtrl,
                      textDirection: TextDirection.rtl,
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Heebo',
                          color: JC.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'תוכן המשימה',
                        hintStyle: TextStyle(
                            fontFamily: 'Heebo', color: JC.textMuted),
                        filled: true,
                        fillColor: JC.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'עדיפות',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Heebo',
                          color: JC.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['low', 'medium', 'high', 'critical']
                          .map((p) => ChoiceChip(
                                label: Text(
                                  _priorityLabel(p),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Heebo',
                                    color: selectedPriority == p
                                        ? JC.onAccent
                                        : JC.textSecondary,
                                  ),
                                ),
                                selected: selectedPriority == p,
                                selectedColor: _priorityColor(p),
                                backgroundColor: JC.surface,
                                side: BorderSide(
                                  color: selectedPriority == p
                                      ? _priorityColor(p)
                                      : JC.textMuted.withOpacity(0.3),
                                ),
                                onSelected: (v) {
                                  if (v) {
                                    setSheetState(
                                        () => selectedPriority = p);
                                  }
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: JC.blue500,
                          foregroundColor: JC.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final newContent = contentCtrl.text.trim();
                          if (newContent.isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            final api = ApiService(widget.settings);
                            final taskId =
                                task['id']?.toString() ?? '';
                            if (taskId.isNotEmpty) {
                              await api.updateTask(taskId,
                                  content: newContent,
                                  priority: selectedPriority);
                              setState(() {
                                final idx = _tasks.indexWhere(
                                    (t) => t['id'] == task['id']);
                                if (idx != -1) {
                                  _tasks[idx]['content'] = newContent;
                                  _tasks[idx]['priority'] =
                                      selectedPriority;
                                }
                                task['content'] = newContent;
                                task['priority'] = selectedPriority;
                              });
                              widget.onTaskUpdated?.call(task);
                            }
                          } catch (_) {}
                        },
                        child: const Text(
                          'שמור',
                          style: TextStyle(
                            fontSize: 15,
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Add task sheet ──────────────────────────────────────────────────────────

  void _showAddTaskSheet(String column) {
    final contentCtrl = TextEditingController();
    String selectedPriority = 'medium';

    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: JC.textMuted.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'משימה חדשה',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: contentCtrl,
                      textDirection: TextDirection.rtl,
                      autofocus: true,
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'Heebo',
                          color: JC.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'תאר את המשימה...',
                        hintStyle: TextStyle(
                            fontFamily: 'Heebo', color: JC.textMuted),
                        filled: true,
                        fillColor: JC.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'עדיפות',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Heebo',
                          color: JC.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['low', 'medium', 'high', 'critical']
                          .map((p) => ChoiceChip(
                                label: Text(
                                  _priorityLabel(p),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'Heebo',
                                    color: selectedPriority == p
                                        ? JC.onAccent
                                        : JC.textSecondary,
                                  ),
                                ),
                                selected: selectedPriority == p,
                                selectedColor: _priorityColor(p),
                                backgroundColor: JC.surface,
                                side: BorderSide(
                                  color: selectedPriority == p
                                      ? _priorityColor(p)
                                      : JC.textMuted.withOpacity(0.3),
                                ),
                                onSelected: (v) {
                                  if (v) {
                                    setSheetState(
                                        () => selectedPriority = p);
                                  }
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: JC.blue500,
                          foregroundColor: JC.onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          final content = contentCtrl.text.trim();
                          if (content.isEmpty) return;
                          Navigator.pop(ctx);
                          await _createTask(content, selectedPriority, column);
                        },
                        child: const Text(
                          'הוסף',
                          style: TextStyle(
                            fontSize: 15,
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── CRUD helpers ────────────────────────────────────────────────────────────

  Future<void> _createTask(
      String content, String priority, String column) async {
    try {
      final api = ApiService(widget.settings);
      final result = await api.addTask(content,
          priority: priority,
          projectId: widget.projectId,
          kanbanColumn: column);
      // The /tasks POST returns either {task:{...}} or the task directly
      Map<String, dynamic> newTask;
      if (result['task'] is Map) {
        newTask = Map<String, dynamic>.from(
            result['task'] as Map<String, dynamic>);
      } else {
        newTask = Map<String, dynamic>.from(result);
      }
      newTask['kanban_column'] = column;

      final taskId = newTask['id']?.toString() ?? '';
      if (taskId.isNotEmpty) {
        // Set kanban column on server
        await api.updateTask(taskId, kanbanColumn: column);
      }
      if (mounted) {
        setState(() => _tasks.add(newTask));
        widget.onTaskUpdated?.call(newTask);
      }
    } catch (_) {
      // Silent failure — user can retry via the regular tasks screen
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final taskId = task['id']?.toString() ?? '';
    setState(() => _tasks.removeWhere((t) => t['id'] == task['id']));
    try {
      if (taskId.isNotEmpty) {
        await ApiService(widget.settings).deleteTask(taskId);
      }
    } catch (_) {
      // Restore on failure
      if (mounted) setState(() => _tasks.add(task));
    }
  }
}
