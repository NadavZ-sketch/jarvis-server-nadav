import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import 'today_tab.dart';
import 'tasks_screen.dart';
import 'reminders_screen.dart';

class ProductivityScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onTasksCountUpdate;
  final ValueChanged<int>? onRemindersCountUpdate;
  final VoidCallback? onOpenDrawer;

  const ProductivityScreen({
    super.key,
    required this.settings,
    this.onTasksCountUpdate,
    this.onRemindersCountUpdate,
    this.onOpenDrawer,
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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'פרודקטיביות',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: JC.blue400,
          unselectedLabelColor: JC.textMuted,
          indicatorColor: JC.blue400,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: JC.border,
          labelStyle: const TextStyle(
              fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontFamily: 'Heebo', fontSize: 14),
          tabs: const [
            Tab(text: 'היום ☀️'),
            Tab(text: 'משימות ✅'),
            Tab(text: 'תזכורות 🔔'),
          ],
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
        ],
      ),
    );
  }
}
