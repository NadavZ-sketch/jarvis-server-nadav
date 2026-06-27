import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/tasks/ai_advisor_sheet.dart';
import '../widgets/tasks/smart_task_card.dart';
import '../widgets/tasks/task_capture_sheet.dart';
import 'tasks/tasks_controller.dart';
import 'projects_hub_screen.dart';

/// Phase 5 — Redesigned tasks tab.
///
/// Header: large "משימות" title + avatar (left) + ✨ advisor badge (left).
/// Below header: view pills (היום / השבוע / הכל / פרויקט) + optional filter.
/// Task list: grouped per the active view (time-of-day / day / flat / project).
/// FAB (from ProductivityScreen) → opens [TaskCaptureSheet] (NL capture).
class TasksScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;
  final ValueListenable<int>? addTrigger;
  final void Function(String)? onAskJarvis;

  const TasksScreen({
    super.key,
    required this.settings,
    this.onCountUpdate,
    this.addTrigger,
    this.onAskJarvis,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final TasksController _c;
  final Set<String> _collapsed = {};

  static const _views = ['today', 'week', 'all', 'project'];
  static const _viewLabels = ['היום', 'השבוע', 'הכל', 'פרויקט'];

  @override
  void initState() {
    super.initState();
    _c = TasksController(settings: widget.settings)..start();
    _c.addListener(_pushCount);
    widget.addTrigger?.addListener(_onAddTrigger);
  }

  @override
  void dispose() {
    widget.addTrigger?.removeListener(_onAddTrigger);
    _c.removeListener(_pushCount);
    _c.dispose();
    super.dispose();
  }

  void _onAddTrigger() => _showCaptureSheet();
  void _pushCount() => widget.onCountUpdate?.call(_c.openCount);

  // ── NL capture sheet ──────────────────────────────────────────────────────

  void _showCaptureSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => TaskCaptureSheet(controller: _c),
    );
  }

  // ── AI Advisor sheet ──────────────────────────────────────────────────────

  void _showAdvisorSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAdvisorSheet(controller: _c),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (_, __) => _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildHeader(),
        _buildViewPills(),
        _buildFilterRow(),
        if (_c.loading && _c.tasks.isEmpty)
          const Expanded(child: LoadingSkeleton(itemCount: 6))
        else if (_c.error != null && _c.tasks.isEmpty)
          Expanded(
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'שגיאת טעינה',
              subtitle: _c.error!,
            ),
          )
        else
          _buildList(),
        if (_c.snack != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: JC.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: JC.blue500.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Text(_c.snack!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontFamily: 'Heebo',
                      fontSize: 13)),
            ),
          ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final initial = widget.settings.userName.isNotEmpty
        ? widget.settings.userName[0]
        : 'נ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          // Title
          Text(
            'משימות',
            style: TextStyle(
              color: JC.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              fontFamily: 'Heebo',
            ),
          ),
          const Spacer(),

          // Projects shortcut
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProjectsHubScreen(settings: widget.settings),
              ),
            ),
            child: Container(
              width: 34,
              height: 34,
              margin: const EdgeInsetsDirectional.only(end: 8),
              decoration: BoxDecoration(
                color: JC.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JC.border, width: 0.8),
              ),
              child: Icon(Icons.folder_outlined, size: 17, color: JC.textSecondary),
            ),
          ),

          // AI Advisor ✨ button with badge
          GestureDetector(
            onTap: _showAdvisorSheet,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        JC.indigo500.withValues(alpha: 0.8),
                        JC.blue500.withValues(alpha: 0.8)
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('✨', style: TextStyle(fontSize: 16)),
                  ),
                ),
                if (_c.advisorHasBadge)
                  Positioned(
                    top: -2,
                    right: 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: JC.cancelRed,
                        shape: BoxShape.circle,
                        border: Border.all(color: JC.bg, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Avatar circle
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: JC.blue500.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: JC.blue500.withValues(alpha: 0.4), width: 1),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                    color: JC.blue400,
                    fontFamily: 'Heebo',
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── View pills ────────────────────────────────────────────────────────────

  Widget _buildViewPills() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // RTL: start from right
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            for (var i = 0; i < _views.length; i++) ...[
              _ViewPill(
                label: _viewLabels[i],
                active: _c.viewMode == _views[i],
                onTap: () => _c.setViewMode(_views[i]),
              ),
              if (i < _views.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  // ── Filter row (kept for power users) ─────────────────────────────────────

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            '${_c.openCount} משימות פתוחות',
            style: TextStyle(
                color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
          ),
          const Spacer(),
          _FilterIconButton(
            active: _c.hasActiveFilters,
            onTap: () => _openFilterSheet(),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet() {
    final searchCtrl = TextEditingController(text: _c.searchQuery);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _FilterSheet(controller: _c, searchCtrl: searchCtrl),
    ).whenComplete(searchCtrl.dispose);
  }

  // ── Task list ─────────────────────────────────────────────────────────────

  Widget _buildList() {
    final sections = _c.groupedSectionsForView(_c.viewMode);
    return Expanded(
      child: RefreshIndicator(
        color: JC.blue400,
        backgroundColor: JC.surfaceAlt,
        onRefresh: _c.refresh,
        child: sections.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: _emptyTitle(),
                    subtitle: _emptySubtitle(),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 96),
                itemCount: sections.length,
                itemBuilder: (ctx, i) {
                  final s = sections[i];
                  return _TaskSection(
                    controller: _c,
                    section: s,
                    collapsed: _collapsed.contains(s.key),
                    onToggle: () => setState(() {
                      if (!_collapsed.remove(s.key)) _collapsed.add(s.key);
                    }),
                    onAskJarvis: widget.onAskJarvis,
                  );
                },
              ),
      ),
    );
  }

  String _emptyTitle() {
    if (_c.hasActiveFilters) return 'לא נמצאו תוצאות';
    return switch (_c.viewMode) {
      'today' => 'אין משימות להיום',
      'week' => 'אין משימות השבוע',
      'project' => 'אין משימות בפרויקטים',
      _ => 'אין משימות פתוחות',
    };
  }

  String _emptySubtitle() {
    if (_c.hasActiveFilters) return '';
    return 'לחץ + להוספת משימה';
  }
}

// ─── View pill ────────────────────────────────────────────────────────────────

class _ViewPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ViewPill(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? JC.blue500.withValues(alpha: 0.18) : JC.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? JC.blue500 : JC.border,
            width: active ? 1.3 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? JC.blue400 : JC.textSecondary,
            fontFamily: 'Heebo',
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─── Filter icon button ───────────────────────────────────────────────────────

class _FilterIconButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _FilterIconButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? JC.blue500.withValues(alpha: 0.18) : JC.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? JC.blue500 : JC.border,
              width: active ? 1.2 : 0.8),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.tune_rounded,
                size: 16, color: active ? JC.blue400 : JC.textSecondary),
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

// ─── Filter sheet (kept from Phase 1) ────────────────────────────────────────

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
                      color: JC.border, borderRadius: BorderRadius.circular(2)),
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
              TextField(
                controller: widget.searchCtrl,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                onChanged: (v) { _c.setSearchQuery(v); setState(() {}); },
                decoration: InputDecoration(
                  hintText: 'חיפוש משימות...',
                  hintStyle: TextStyle(
                      color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: JC.textMuted, size: 18),
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
              GestureDetector(
                onTap: () => _set(_c.toggleShowDone),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
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

  void _set(VoidCallback action) { action(); setState(() {}); }

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
              color: active ? color : JC.border,
              width: active ? 1.2 : 0.8),
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

// ─── Task section ─────────────────────────────────────────────────────────────

class _TaskSection extends StatelessWidget {
  final TasksController controller;
  final TaskSection section;
  final bool collapsed;
  final VoidCallback onToggle;
  final void Function(String)? onAskJarvis;

  const _TaskSection({
    required this.controller,
    required this.section,
    required this.collapsed,
    required this.onToggle,
    this.onAskJarvis,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = section.tasks;
    final isOverdue = section.key == 'overdue';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(2, 12, 2, 6),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Text(
                  section.label,
                  style: TextStyle(
                    color: isOverdue ? JC.cancelRed : JC.textPrimary,
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? JC.cancelRed.withValues(alpha: 0.15)
                        : JC.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${tasks.length}',
                      style: TextStyle(
                          color: isOverdue ? JC.cancelRed : JC.textMuted,
                          fontFamily: 'Heebo',
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: JC.textMuted),
                ),
              ],
            ),
          ),
        ),
        if (!collapsed)
          for (var i = 0; i < tasks.length; i++)
            AnimatedListItem(
              index: i,
              child: SmartTaskCard(
                controller: controller,
                task: tasks[i],
                onAskJarvis: onAskJarvis,
              ),
            ),
      ],
    );
  }
}
