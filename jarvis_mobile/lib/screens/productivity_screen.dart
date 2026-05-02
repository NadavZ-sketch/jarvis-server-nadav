import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import 'tasks_screen.dart';
import 'reminders_screen.dart';
import 'calendar_screen.dart';

class ProductivityScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onTasksCountUpdate;
  final ValueChanged<int>? onRemindersCountUpdate;

  const ProductivityScreen({
    super.key,
    required this.settings,
    this.onTasksCountUpdate,
    this.onRemindersCountUpdate,
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
        title: const Text(
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
            Tab(text: 'משימות ✅'),
            Tab(text: 'תזכורות 🔔'),
            Tab(text: 'לוח שנה 📅'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
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
