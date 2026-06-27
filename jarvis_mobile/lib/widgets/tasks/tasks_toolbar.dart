import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../screens/projects_hub_screen.dart';
import '../../screens/tasks/tasks_controller.dart';
import 'group_mode_bar.dart';
import 'task_category.dart';

/// Single compact control row for the tasks screen: the group-mode segmented
/// control (the primary, list-shaping control) plus one trailing button that
/// opens a bottom sheet holding everything secondary — search, priority filter,
/// category filter, sort and show-done. This collapses what used to be three
/// stacked bars (search + group bar + filter bar) into one row, so the task
/// list is the hero.
class TasksToolbar extends StatelessWidget {
  final TasksController controller;
  final String groupMode;
  final ValueChanged<String> onGroupChange;
  final AppSettings settings;

  const TasksToolbar({
    super.key,
    required this.controller,
    required this.groupMode,
    required this.onGroupChange,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 12, 2),
      child: Row(
        children: [
          Expanded(
            child: GroupModeBar(current: groupMode, onChange: onGroupChange),
          ),
          _ProjectsButton(settings: settings),
          const SizedBox(width: 6),
          _FilterButton(
            active: controller.hasActiveFilters,
            onTap: () => _openFilterSheet(context),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    final searchCtrl = TextEditingController(text: controller.searchQuery);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _FilterSheet(
        controller: controller,
        searchCtrl: searchCtrl,
      ),
    ).whenComplete(searchCtrl.dispose);
  }
}

// ─── Projects shortcut button ────────────────────────────────────────────────

class _ProjectsButton extends StatelessWidget {
  final AppSettings settings;
  const _ProjectsButton({required this.settings});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProjectsHubScreen(settings: settings),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: Icon(Icons.folder_outlined, size: 18, color: JC.textSecondary),
      ),
    );
  }
}

// ─── Trailing filter button (with active dot) ────────────────────────────────

class _FilterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _FilterButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? JC.blue500.withValues(alpha: 0.18) : JC.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? JC.blue500 : JC.border,
              width: active ? 1.2 : 0.8),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.tune_rounded,
                size: 18, color: active ? JC.blue400 : JC.textSecondary),
            if (active)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: JC.blue400,
                    shape: BoxShape.circle,
                    border: Border.all(color: JC.surfaceAlt, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter / sort / search bottom sheet ─────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final TasksController controller;
  final TextEditingController searchCtrl;
  const _FilterSheet({required this.controller, required this.searchCtrl});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  TasksController get _c => widget.controller;

  static const _sortOptions = [
    ('priority', 'עדיפות'),
    ('due_date', 'תאריך'),
    ('created', 'יצירה'),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: JC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('סינון ומיון',
                      style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Heebo')),
                  const Spacer(),
                  if (_c.hasActiveFilters)
                    GestureDetector(
                      onTap: () {
                        widget.searchCtrl.clear();
                        _c.clearFilters();
                        setState(() {});
                      },
                      child: Text('נקה הכל',
                          style: TextStyle(
                              color: JC.blue400,
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Search ───────────────────────────────────────────────────
              TextField(
                controller: widget.searchCtrl,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                onChanged: (v) {
                  _c.setSearchQuery(v);
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'חיפוש משימות...',
                  hintStyle: TextStyle(
                      color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                  prefixIcon:
                      Icon(Icons.search_rounded, color: JC.textMuted, size: 18),
                  filled: true,
                  fillColor: JC.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.blue500)),
                ),
              ),
              const SizedBox(height: 16),

              // ── Priority ─────────────────────────────────────────────────
              _label('עדיפות'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('הכל', _c.filterPriority == 'all', JC.blue400,
                      () => _set(() => _c.setFilterPriority('all'))),
                  _chip('🔴 גבוה', _c.filterPriority == 'high', JC.cancelRed,
                      () => _set(() => _c.setFilterPriority('high'))),
                  _chip('🟡 בינוני', _c.filterPriority == 'medium', JC.amber400,
                      () => _set(() => _c.setFilterPriority('medium'))),
                  _chip('🟢 נמוך', _c.filterPriority == 'low', JC.green500,
                      () => _set(() => _c.setFilterPriority('low'))),
                ],
              ),
              const SizedBox(height: 16),

              // ── Category ─────────────────────────────────────────────────
              _label('קטגוריה'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip('הכל', _c.filterCategory == 'all', JC.indigo300,
                      () => _set(() => _c.setFilterCategory('all'))),
                  for (final cat in kTaskCategories)
                    _chip('${cat.emoji} ${cat.label}',
                        _c.filterCategory == cat.id, cat.color(),
                        () => _set(() => _c.setFilterCategory(cat.id))),
                ],
              ),
              const SizedBox(height: 16),

              // ── Sort ─────────────────────────────────────────────────────
              _label('מיון לפי'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final opt in _sortOptions)
                    _chip(opt.$2, _c.filterSort == opt.$1, JC.blue400,
                        () => _set(() => _c.setFilterSort(opt.$1))),
                ],
              ),
              const SizedBox(height: 16),

              // ── Show done ────────────────────────────────────────────────
              GestureDetector(
                onTap: () => _set(_c.toggleShowDone),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: JC.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _c.showDone ? JC.green500 : JC.border,
                        width: _c.showDone ? 1.2 : 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _c.showDone
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 18,
                        color: _c.showDone ? JC.green500 : JC.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Text('הצג משימות שהושלמו (${_c.doneCount})',
                          style: TextStyle(
                              color: JC.textPrimary,
                              fontSize: 14,
                              fontFamily: 'Heebo')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('סגור',
                      style: TextStyle(
                          fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Run a controller mutation then refresh the sheet so chip states update.
  void _set(VoidCallback action) {
    action();
    setState(() {});
  }

  Widget _label(String text) => Align(
        alignment: Alignment.centerRight,
        child: Text(text,
            style: TextStyle(
                color: JC.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Heebo')),
      );

  Widget _chip(String label, bool active, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : JC.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? color : JC.border, width: active ? 1.2 : 0.8),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? color : JC.textMuted,
              fontSize: 12.5,
              fontFamily: 'Heebo',
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
    );
  }
}
