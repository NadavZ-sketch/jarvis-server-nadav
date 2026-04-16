import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart' show JC, ChatScreen;
import 'app_settings.dart';
import 'screens/app_drawer.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/lists_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // Start on Chat tab (index 1)
  int _selectedIndex = 1;
  AppSettings _settings = AppSettings();

  int _taskCount     = 0;
  int _reminderCount = 0;

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  void _onSettingsChanged(AppSettings updated) {
    setState(() => _settings = updated);
  }

  void _onTabTapped(int i) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = i);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: JC.bg,
      endDrawer: AppDrawer(
        selectedIndex: _selectedIndex,
        onNavigate: _onTabTapped,
        settings: _settings,
        onSettingsChanged: _onSettingsChanged,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // 0 — Dashboard
          DashboardScreen(
            settings: _settings,
            onNavigate: _onTabTapped,
          ),
          // 1 — Chat (main screen)
          ChatScreen(
            initialSettings: _settings,
            onSettingsChanged: _onSettingsChanged,
            onOpenDrawer: _openDrawer,
          ),
          // 2 — Tasks
          TasksScreen(
            settings: _settings,
            onCountUpdate: (c) => setState(() => _taskCount = c),
          ),
          // 3 — Reminders
          RemindersScreen(
            settings: _settings,
            onCountUpdate: (c) => setState(() => _reminderCount = c),
          ),
          // 4 — Lists (Shopping + Notes)
          ListsScreen(settings: _settings),
        ],
      ),
    );
  }
}
