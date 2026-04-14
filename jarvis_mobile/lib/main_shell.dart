import 'package:flutter/material.dart';
import 'main.dart' show JC, ChatScreen;
import 'app_settings.dart';
import 'screens/tasks_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/lists_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  AppSettings _settings = AppSettings();

  // Badge counts (updated via onCountUpdate callbacks from screens)
  int _taskCount     = 0;
  int _reminderCount = 0;
  int _listCount     = 0; // shopping + notes combined

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ChatScreen(
            initialSettings: _settings,
            onSettingsChanged: _onSettingsChanged,
          ),
          TasksScreen(
            settings: _settings,
            onCountUpdate: (c) => setState(() => _taskCount = c),
          ),
          RemindersScreen(
            settings: _settings,
            onCountUpdate: (c) => setState(() => _reminderCount = c),
          ),
          ContactsScreen(settings: _settings),
          ListsScreen(
            settings: _settings,
            onShoppingCountUpdate: (c) =>
                setState(() => _listCount = _listCount + c),
            onNotesCountUpdate: (c) =>
                setState(() => _listCount = _listCount + c),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: JC.surfaceAlt,
        indicatorColor: JC.blue500.withOpacity(0.25),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: const Duration(milliseconds: 300),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'צ׳אט',
          ),
          NavigationDestination(
            icon: _badgeIcon(
              Icons.checklist_outlined,
              _taskCount,
            ),
            selectedIcon: _badgeIcon(
              Icons.checklist_rounded,
              _taskCount,
            ),
            label: 'משימות',
          ),
          NavigationDestination(
            icon: _badgeIcon(
              Icons.notifications_none_rounded,
              _reminderCount,
            ),
            selectedIcon: _badgeIcon(
              Icons.notifications_rounded,
              _reminderCount,
            ),
            label: 'תזכורות',
          ),
          const NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts_rounded),
            label: 'אנשי קשר',
          ),
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt_rounded),
            label: 'רשימות',
          ),
        ],
      ),
    );
  }

  static Widget _badgeIcon(IconData icon, int count) {
    if (count == 0) return Icon(icon);
    return Badge(
      label: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 10, fontFamily: 'Heebo'),
      ),
      backgroundColor: JC.blue500,
      child: Icon(icon),
    );
  }
}
