import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart' show JC, ChatScreen;
import 'app_settings.dart';
import 'screens/app_drawer.dart';
import 'screens/progress_map_screen.dart';
import 'screens/productivity_screen.dart';
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
  final _chatScreenKey = GlobalKey<State>();

  // Start on Chat tab (index 1)
  int _selectedIndex = 1;
  AppSettings _settings = AppSettings();

  Timer? _notifPollTimer;
  int    _notifId = 10000;
  String? _pendingChatCommand;

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
    _checkFiredReminders();
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

  Future<void> _onTabTapped(int i) async {
    if (i == _selectedIndex) return;
    // Archive chat before switching away from it
    if (_selectedIndex == 1) {
      final chatState = _chatScreenKey.currentState as dynamic;
      await chatState?.archiveCurrentSession();
    }
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = i);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  static const int _tabCount = 4;

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
      _onTabTapped(1);
      return false;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('יציאה מג׳רביס',
            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
        content: const Text('האם לצאת מהאפליקציה?',
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ביטול',
                style: TextStyle(color: JC.blue400, fontFamily: 'Heebo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('יציאה',
                style: TextStyle(
                    color: Color(0xFFEF4444), fontFamily: 'Heebo')),
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
            settings: _settings,
            onSettingsChanged: _onSettingsChanged,
          ),
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              // 0 — Progress Map
              ProgressMapScreen(
                settings: _settings,
                onSwitchToChat: (cmd) => setState(() {
                  _pendingChatCommand = cmd;
                  _selectedIndex = 1;
                }),
              ),
              // 1 — Chat (main screen)
              ChatScreen(
                key: _chatScreenKey,
                initialSettings: _settings,
                onSettingsChanged: _onSettingsChanged,
                onOpenDrawer: _openDrawer,
                pendingCommand: _pendingChatCommand,
                onCommandConsumed: () => setState(() => _pendingChatCommand = null),
              ),
              // 2 — Productivity (Tasks + Reminders + Calendar)
              ProductivityScreen(settings: _settings),
              // 3 — Lists (Shopping + Notes + Contacts)
              ListsScreen(settings: _settings),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: JC.surface,
          border: Border(top: BorderSide(color: JC.border, width: 0.6)),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: JC.surface,
              indicatorColor: JC.blue500.withOpacity(0.18),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? JC.blue400 : JC.textMuted,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: selected ? JC.blue400 : JC.textMuted,
                  size: 24,
                );
              }),
            ),
            child: NavigationBar(
              height: 64,
              elevation: 0,
              backgroundColor: JC.surface,
              labelBehavior:
                  NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onTabTapped,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map_rounded),
                  label: 'מפה',
                ),
                NavigationDestination(
                  icon: Icon(Icons.mic_none_rounded),
                  selectedIcon: Icon(Icons.mic_rounded),
                  label: 'שיחה',
                ),
                NavigationDestination(
                  icon: Icon(Icons.task_alt_outlined),
                  selectedIcon: Icon(Icons.task_alt_rounded),
                  label: 'משימות',
                ),
                NavigationDestination(
                  icon: Icon(Icons.list_alt_outlined),
                  selectedIcon: Icon(Icons.list_alt_rounded),
                  label: 'רשימות',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
