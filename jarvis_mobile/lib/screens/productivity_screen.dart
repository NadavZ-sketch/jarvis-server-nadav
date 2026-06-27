import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../widgets/productivity/productivity_fab.dart';
import 'tasks_screen.dart';
import 'reminders_screen.dart';
import 'calendar_screen.dart';

class ProductivityScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onTasksCountUpdate;
  final ValueChanged<int>? onRemindersCountUpdate;
  final VoidCallback? onOpenDrawer;
  final ValueListenable<int>? jumpToTab;
  final void Function(String)? onAskJarvis;

  const ProductivityScreen({
    super.key,
    required this.settings,
    this.onTasksCountUpdate,
    this.onRemindersCountUpdate,
    this.onOpenDrawer,
    this.jumpToTab,
    this.onAskJarvis,
  });

  @override
  State<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends State<ProductivityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  // Notifiers that child screens listen to for triggering their add sheets
  final ValueNotifier<int> _addTaskNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _addReminderNotifier = ValueNotifier<int>(0);

  static const _tabs = [
    _TabDef('משימות', Icons.check_circle_rounded,
        Icons.check_circle_outline_rounded),
    _TabDef('תזכורות', Icons.notifications_rounded,
        Icons.notifications_outlined),
    _TabDef('לוח שנה', Icons.calendar_month_rounded,
        Icons.calendar_month_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging ||
          _tabController.index != _currentTab) {
        setState(() => _currentTab = _tabController.index);
      }
    });
    widget.jumpToTab?.addListener(_onJumpToTab);
  }

  void _onJumpToTab() {
    final i = widget.jumpToTab?.value ?? 0;
    if (i >= 0 && i < _tabController.length) _tabController.animateTo(i);
  }

  @override
  void dispose() {
    widget.jumpToTab?.removeListener(_onJumpToTab);
    _tabController.dispose();
    _addTaskNotifier.dispose();
    _addReminderNotifier.dispose();
    super.dispose();
  }

  // ─── FAB actions ──────────────────────────────────────────────────────────

  void _showAddTask() => _addTaskNotifier.value++;

  void _showAddReminder() => _addReminderNotifier.value++;

  void _showAddEvent() {
    // Navigate to Calendar tab — it owns event creation via its own FAB
    _tabController.animateTo(2);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      floatingActionButton: ProductivityFAB(
        currentTab: _currentTab,
        onAddTask: _showAddTask,
        onAddReminder: _showAddReminder,
        onAddEvent: _showAddEvent,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: AppBar(
        backgroundColor: JC.surface.withOpacity(0.95),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        title: Text(
          'פרודקטיביות',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Heebo',
          ),
          textDirection: TextDirection.rtl,
        ),
        centerTitle: true,
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: Icon(Icons.menu_rounded,
                    color: JC.textSecondary, size: 22),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: JC.border.withOpacity(0.4),
                  width: 0.6,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: JC.blue400,
              unselectedLabelColor: JC.textMuted,
              indicator: _PillIndicator(color: JC.blue500),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5),
              unselectedLabelStyle:
                  const TextStyle(fontFamily: 'Heebo', fontSize: 11.5),
              tabs: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final active = _currentTab == i;
                return Tab(
                  height: 52,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          active ? tab.activeIcon : tab.icon,
                          key: ValueKey(active),
                          size: 20,
                          color: active ? JC.blue400 : JC.textMuted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: TextStyle(
                          color: active ? JC.blue400 : JC.textMuted,
                          fontFamily: 'Heebo',
                          fontSize: 11,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TasksScreen(
            settings: widget.settings,
            onCountUpdate: widget.onTasksCountUpdate,
            addTrigger: _addTaskNotifier,
            onAskJarvis: widget.onAskJarvis,
          ),
          RemindersScreen(
            settings: widget.settings,
            onCountUpdate: widget.onRemindersCountUpdate,
            addTrigger: _addReminderNotifier,
          ),
          CalendarScreen(settings: widget.settings),
        ],
      ),
    );
  }
}

// ─── Tab definition ───────────────────────────────────────────────────────────

class _TabDef {
  final String label;
  final IconData activeIcon;
  final IconData icon;
  const _TabDef(this.label, this.activeIcon, this.icon);
}

// ─── Pill indicator ───────────────────────────────────────────────────────────

class _PillIndicator extends Decoration {
  final Color color;
  const _PillIndicator({required this.color});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PillPainter(color: color);
}

class _PillPainter extends BoxPainter {
  final Color color;
  _PillPainter({required this.color});

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = offset & size;
    final paint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    const radius = Radius.circular(10);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);

    final linePaint = Paint()
      ..color = color.withOpacity(0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final lineWidth = size.width * 0.45;
    final lineY = offset.dy + size.height - 2;
    final lineX = offset.dx + (size.width - lineWidth) / 2;
    canvas.drawLine(
      Offset(lineX, lineY),
      Offset(lineX + lineWidth, lineY),
      linePaint,
    );
  }
}
