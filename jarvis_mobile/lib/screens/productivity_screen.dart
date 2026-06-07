import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import 'today_tab.dart';
import 'tasks_screen.dart';
import 'reminders_screen.dart';
import 'calendar_screen.dart';

class ProductivityScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onTasksCountUpdate;
  final ValueChanged<int>? onRemindersCountUpdate;
  final VoidCallback? onOpenDrawer;
  final ValueListenable<int>? jumpToTab;

  const ProductivityScreen({
    super.key,
    required this.settings,
    this.onTasksCountUpdate,
    this.onRemindersCountUpdate,
    this.onOpenDrawer,
    this.jumpToTab,
  });

  @override
  State<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends State<ProductivityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: JC.surface.withOpacity(0.92),
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
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: JC.border.withOpacity(0.5),
                  width: 0.6,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: JC.blue400,
              unselectedLabelColor: JC.textMuted,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: JC.blue500.withOpacity(0.15),
                border: Border.all(
                  color: JC.blue400.withOpacity(0.45),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: JC.blue500.withOpacity(0.2),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 5),
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Heebo', fontSize: 13.5),
              tabs: const [
                Tab(text: 'היום ☀️'),
                Tab(text: 'משימות ✅'),
                Tab(text: 'תזכורות 🔔'),
                Tab(text: 'לוח שנה 📅'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TodayTab(settings: widget.settings),
          TasksScreen(
            settings: widget.settings,
            onCountUpdate: widget.onTasksCountUpdate,
          ),
          RemindersScreen(
            settings: widget.settings,
            onCountUpdate: widget.onRemindersCountUpdate,
          ),
          CalendarScreen(settings: widget.settings),
        ],
      ),
    );
  }
}
