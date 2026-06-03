import 'package:flutter/material.dart';
import '../../../main.dart' show JC;
import '../../../widgets/animated_list_item.dart';
import '../../../widgets/delete_snackbar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/jarvis_search_bar.dart';
import '../../../widgets/tasks/smart_task_card.dart';
import '../../../widgets/tasks/task_category.dart';
import '../tasks_controller.dart';

class TasksListView extends StatefulWidget {
  final TasksController controller;
  const TasksListView({super.key, required this.controller});

  @override
  State<TasksListView> createState() => _TasksListViewState();
}

class _TasksListViewState extends State<TasksListView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String _filter = 'all'; // all|high|medium|low
  String _catFilter = 'all'; // all|work|personal|financial|project|general
  String _sort = 'priority'; // priority|due_date|created
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _po(String? p) =>
      switch (p) { 'high' => 0, 'medium' => 1, 'low' => 2, _ => 1 };

  List<Map<String, dynamic>> get _items {
    var src = List<Map<String, dynamic>>.from(widget.controller.tasks);
    if (_filter != 'all') {
      src = src.where((t) => t['priority'] == _filter).toList();
    }
    if (_catFilter != 'all') {
      src = src.where((t) {
        final c = t['category']?.toString();
        // 'general' also matches tasks with no category set.
        if (_catFilter == 'general') return c == null || c.isEmpty || c == 'general';
        return c == _catFilter;
      }).toList();
    }
    final active = src.where((t) => t['done'] != true).toList();
    final done = src.where((t) => t['done'] == true).toList();
    active.sort((a, b) {
      if (_sort == 'priority') {
        final pc = _po(a['priority']?.toString())
            .compareTo(_po(b['priority']?.toString()));
        if (pc != 0) return pc;
      }
      if (_sort == 'due_date' || _sort == 'priority') {
        final ad = a['due_date'] as String?;
        final bd = b['due_date'] as String?;
        if (ad != null && bd != null) return ad.compareTo(bd);
        if (ad != null) return -1;
        if (bd != null) return 1;
      }
      return (b['created_at'] as String? ?? '')
          .compareTo(a['created_at'] as String? ?? '');
    });
    final all = _showDone ? [...active, ...done] : active;
    if (_query.isEmpty) return all;
    return all
        .where((t) =>
            (t['content']?.toString() ?? '').toLowerCase().contains(_query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.controller.tasks;
    final doneCount = tasks.where((t) => t['done'] == true).length;
    final filtered = _items;

    return Column(
      children: [
        if (tasks.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
            child:
                JarvisSearchBar(controller: _searchCtrl, hint: 'חיפוש במשימות...'),
          ),
        if (tasks.isNotEmpty)
          _FilterBar(
            filter: _filter,
            sort: _sort,
            catFilter: _catFilter,
            onFilter: (v) => setState(() => _filter = v),
            onSort: (v) => setState(() => _sort = v),
            onCatFilter: (v) => setState(() => _catFilter = v),
          ),
        if (doneCount > 0)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => setState(() => _showDone = !_showDone),
                child: Text(
                  _showDone ? 'הסתר בוצעו' : 'הצג בוצעו ($doneCount)',
                  style: TextStyle(
                      color: JC.blue400, fontFamily: 'Heebo', fontSize: 13),
                ),
              ),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: _query.isEmpty
                      ? 'אין משימות פתוחות'
                      : 'לא נמצאו תוצאות',
                  subtitle: _query.isEmpty ? 'לחץ + להוספת משימה' : '',
                )
              : ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final task = filtered[i];
                    return AnimatedListItem(
                      index: i,
                      child: Dismissible(
                        key: ValueKey(task['id']),
                        direction: DismissDirection.endToStart,
                        background: _dismissBg(),
                        onDismissed: (_) {
                          final idx = widget.controller.removeLocal(task);
                          showDeleteSnackbar(
                            context,
                            message: 'המשימה הוסרה',
                            onUndo: () =>
                                widget.controller.restoreTask(task, idx),
                            onClosed: (wasUndone) {
                              if (!wasUndone) {
                                widget.controller.commitDelete(task);
                              }
                            },
                          );
                        },
                        child: SmartTaskCard(
                            controller: widget.controller, task: task),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String filter;
  final String sort;
  final String catFilter;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onSort;
  final ValueChanged<String> onCatFilter;
  const _FilterBar({
    required this.filter,
    required this.sort,
    required this.catFilter,
    required this.onFilter,
    required this.onSort,
    required this.onCatFilter,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
        child: Row(
          children: [
            // Priority filter chips
            _chip('הכל', filter == 'all', JC.blue400, () => onFilter('all')),
            const SizedBox(width: 6),
            _chip('🔴 גבוה', filter == 'high', JC.cancelRed,
                () => onFilter('high')),
            const SizedBox(width: 6),
            _chip('🟡 בינוני', filter == 'medium', JC.amber400,
                () => onFilter('medium')),
            const SizedBox(width: 6),
            _chip('🟢 נמוך', filter == 'low', JC.green500,
                () => onFilter('low')),
            // Separator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Container(
                width: 1,
                height: 16,
                color: JC.border.withValues(alpha: 0.5),
              ),
            ),
            // Category filter chips
            _chip('הכל', catFilter == 'all', JC.indigo300,
                () => onCatFilter('all')),
            for (final c in kTaskCategories) ...[
              const SizedBox(width: 6),
              _chip('${c.emoji} ${c.label}', catFilter == c.id, c.color(),
                  () => onCatFilter(c.id)),
            ],
            const SizedBox(width: 8),
            // Sort button
            PopupMenuButton<String>(
              onSelected: onSort,
              color: JC.surfaceAlt,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: JC.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: JC.border, width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort_rounded, size: 14, color: JC.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      switch (sort) {
                        'due_date' => 'תאריך',
                        'created' => 'יצירה',
                        _ => 'עדיפות'
                      },
                      style: TextStyle(
                          color: JC.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Heebo'),
                    ),
                  ],
                ),
              ),
              itemBuilder: (_) => [
                _menu('priority', 'לפי עדיפות', sort),
                _menu('due_date', 'לפי תאריך', sort),
                _menu('created', 'לפי יצירה', sort),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : JC.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? color : JC.border, width: active ? 1.2 : 0.8),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? color : JC.textMuted,
              fontSize: 12,
              fontFamily: 'Heebo',
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
    );
  }

  PopupMenuItem<String> _menu(String value, String label, String cur) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            if (cur == value)
              Icon(Icons.check_rounded, size: 14, color: JC.blue400),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontFamily: 'Heebo',
                    fontSize: 13)),
          ],
        ),
      );
}

Widget _dismissBg() => Container(
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsetsDirectional.only(start: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );
