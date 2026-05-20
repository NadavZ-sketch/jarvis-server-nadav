import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import 'contacts_screen.dart';
import 'calendar_screen.dart';

/// Unified "people & schedule" screen — contacts and calendar under one roof.
class PeopleScheduleScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onContactsCountUpdate;

  const PeopleScheduleScreen({
    super.key,
    required this.settings,
    this.onContactsCountUpdate,
  });

  @override
  State<PeopleScheduleScreen> createState() => _PeopleScheduleScreenState();
}

class _PeopleScheduleScreenState extends State<PeopleScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
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
            Tab(text: 'אנשי קשר 👤'),
            Tab(text: 'לוח שנה 📅'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ContactsScreen(
                settings: widget.settings,
                onCountUpdate: widget.onContactsCountUpdate,
              ),
              CalendarScreen(settings: widget.settings),
            ],
          ),
        ),
      ],
    );
  }
}
