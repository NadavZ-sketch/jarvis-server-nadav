import 'package:flutter/material.dart';
import 'main.dart' show JC, ChatScreen;
import 'app_settings.dart';
import 'screens/tasks_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/contacts_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  AppSettings _settings = AppSettings();

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

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline_rounded),
      selectedIcon: Icon(Icons.chat_bubble_rounded),
      label: 'צ׳אט',
    ),
    NavigationDestination(
      icon: Icon(Icons.checklist_outlined),
      selectedIcon: Icon(Icons.checklist_rounded),
      label: 'משימות',
    ),
    NavigationDestination(
      icon: Icon(Icons.notifications_none_rounded),
      selectedIcon: Icon(Icons.notifications_rounded),
      label: 'תזכורות',
    ),
    NavigationDestination(
      icon: Icon(Icons.contacts_outlined),
      selectedIcon: Icon(Icons.contacts_rounded),
      label: 'אנשי קשר',
    ),
  ];

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
          TasksScreen(settings: _settings),
          RemindersScreen(settings: _settings),
          ContactsScreen(settings: _settings),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: JC.surfaceAlt,
        indicatorColor: JC.blue500.withOpacity(0.25),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        animationDuration: const Duration(milliseconds: 300),
        destinations: _destinations,
      ),
    );
  }
}
