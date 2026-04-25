import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart' show JC, ChatScreen;
import 'app_settings.dart';
import 'screens/app_drawer.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/lists_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

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

  Timer? _notifPollTimer;
  int    _notifId = 10000;

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((s) {
      if (mounted) {
        setState(() => _settings = s);
        _startNotificationPolling();
      }
    });
  }

  void _startNotificationPolling() {
    _checkFiredReminders(); // immediate check on app start
    _notifPollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkFiredReminders(),
    );
  }

  Future<void> _checkFiredReminders() async {
    if (_settings.serverUrl.isEmpty) return;
    try {
      final api = ApiService(_settings);
      final fired = await api.checkFiredReminders();
      for (final r in fired) {
        final text = r['text']?.toString() ?? '';
        if (text.isEmpty) continue;
        await NotificationService.showNow(_notifId++, text);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _notifPollTimer?.cancel();
    super.dispose();
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

  static const int _tabCount = 5;

  void _swipeToTab(DragEndDetails details) {
    const threshold = 300.0;
    final v = details.primaryVelocity ?? 0;
    if (v < -threshold && _selectedIndex < _tabCount - 1) {
      _onTabTapped(_selectedIndex + 1);
    } else if (v > threshold && _selectedIndex > 0) {
      _onTabTapped(_selectedIndex - 1);
    }
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 1) {
      _onTabTapped(1); // חזור למסך הצ'אט
      return false;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('יציאה מג׳רביס', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
        content: const Text('האם לצאת מהאפליקציה?', style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ביטול', style: TextStyle(color: JC.blue400, fontFamily: 'Heebo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('יציאה', style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
    return exit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: GestureDetector(
        onHorizontalDragEnd: _swipeToTab,
        child: Scaffold(
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
        ),
      ),
    );
  }
}
