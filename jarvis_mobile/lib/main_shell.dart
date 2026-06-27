import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart' show JC;
import 'screens/chat/chat_screen.dart' show ChatScreen;
import 'app_settings.dart';
import 'widgets/animated_indexed_stack.dart';
import 'screens/app_drawer.dart';
import 'screens/smart_productivity_preview_screen.dart';
import 'screens/productivity_screen.dart';
import 'screens/progress_map_screen.dart';
import 'screens/notes_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Future<void> Function()? _archiveChatFn;

  // Start on the Dashboard home tab (index 0)
  int _selectedIndex = 0;
  AppSettings _settings = AppSettings();

  Timer? _notifPollTimer;
  String? _pendingChatCommand;

  // Drives the Productivity tab's inner sub-tab (0=tasks, 1=reminders, 2=calendar) when the
  // chat sends the user there via an inline navigate button.
  final ValueNotifier<int> _productivityTab = ValueNotifier<int>(0);

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
      const Duration(minutes: 1),
      (_) => _checkFiredReminders(),
    );
  }

  Future<void> _checkFiredReminders() async {
    if (_settings.serverUrl.isEmpty) return;
    if (_settings.isInQuietHours()) return;
    try {
      final api = ApiService(_settings);
      final fired = await api.checkFiredReminders();
      for (final r in fired) {
        final text = r['text']?.toString() ?? '';
        if (text.isEmpty) continue;
        final notifId = (r['id']?.toString() ?? text).hashCode.abs() % 100000;
        await NotificationService.showNow(notifId, text);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _notifPollTimer?.cancel();
    _productivityTab.dispose();
    super.dispose();
  }

  // Navigate the user to the right place when the chat returns a navigate action.
  void _navigateFromChat(String target) {
    if (target == 'notes') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: JC.bg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: Text('הערות',
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo')),
              centerTitle: true,
              iconTheme: IconThemeData(color: JC.textSecondary),
            ),
            body: NotesScreen(settings: _settings),
          ),
        ),
      );
      return;
    }
    // tasks/reminders live inside the Productivity tab (index 2).
    final subTab = target == 'reminders' ? 1 : 0;
    _productivityTab.value = subTab;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = 2);
  }

  void _onSettingsChanged(AppSettings updated) {
    setState(() => _settings = updated);
  }

  Future<void> _onTabTapped(int i) async {
    if (i == _selectedIndex) return;
    // Archive chat before switching away from it
    if (_selectedIndex == 1) {
      await _archiveChatFn?.call();
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
    if (_selectedIndex != 0) {
      _onTabTapped(0);
      return false;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('יציאה מג׳רביס',
            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
        content: Text('האם לצאת מהאפליקציה?',
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
            onSwitchToChat: (cmd) => setState(() {
              _pendingChatCommand = cmd;
              _selectedIndex = 1;
            }),
          ),
          floatingActionButton: _settings.quickSettingsEnabled
              ? _QuickSettingsFab(
                  settings: _settings,
                  onChanged: (updated) {
                    setState(() => _settings = updated);
                    updated.save();
                  },
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          body: AnimatedIndexedStack(
            index: _selectedIndex,
            enabled: _settings.animationsEnabled,
            children: [
              // 0 — Smart Day Manager (home)
              SmartProductivityPreviewScreen(
                settings: _settings,
                onNavigateToChat: ({command}) {
                  if (command != null && command.isNotEmpty) {
                    setState(() => _pendingChatCommand = command);
                  }
                  _onTabTapped(1);
                },
                onNavigateToCalendar: () {
                  _productivityTab.value = 2;
                  HapticFeedback.selectionClick();
                  setState(() => _selectedIndex = 2);
                },
              ),
              // 1 — Chat (main screen)
              ChatScreen(
                onRegisterArchive: (fn) => _archiveChatFn = fn,
                initialSettings: _settings,
                onSettingsChanged: _onSettingsChanged,
                onOpenDrawer: _openDrawer,
                pendingCommand: _pendingChatCommand,
                onCommandConsumed: () => setState(() => _pendingChatCommand = null),
                onNavigate: _navigateFromChat,
              ),
              // 2 — Productivity (Tasks + Reminders + Calendar)
              ProductivityScreen(
                settings: _settings,
                onOpenDrawer: _openDrawer,
                jumpToTab: _productivityTab,
                onAskJarvis: (msg) {
                  setState(() {
                    _pendingChatCommand = msg;
                    _selectedIndex = 1;
                  });
                },
              ),
              // 3 — Control Center (unified status + control area)
              ProgressMapScreen(
                settings: _settings,
                onSwitchToChat: (cmd) {
                  setState(() => _pendingChatCommand = cmd);
                  _onTabTapped(1);
                },
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final accent = JC.blue400;
    final accentGlow = JC.blue500.withValues(alpha: 0.22);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: JC.surface,
          border: Border(top: BorderSide(color: JC.border.withValues(alpha: 0.6), width: 0.6)),
          boxShadow: [
            BoxShadow(
              color: JC.blue500.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: accentGlow,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? accent : JC.textMuted,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  color: selected ? accent : JC.textMuted,
                  size: selected ? 25 : 23,
                );
              }),
            ),
            child: NavigationBar(
              height: 64,
              elevation: 0,
              backgroundColor: Colors.transparent,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onTabTapped,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'בית',
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
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub_rounded),
                  label: 'מרכז שליטה',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Quick Settings FAB ───────────────────────────────────────────────────────

class _QuickSettingsFab extends StatelessWidget {
  final AppSettings settings;
  final void Function(AppSettings) onChanged;

  const _QuickSettingsFab({required this.settings, required this.onChanged});

  static const _personalities = ['friendly', 'formal', 'concise', 'humorous'];
  static const _personalityHe = {
    'friendly': 'ידידותי', 'formal': 'רשמי',
    'concise': 'קצר ולעניין', 'humorous': 'הומוריסטי',
  };

  void _show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickSettingsSheet(settings: settings, onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      backgroundColor: JC.blue500,
      foregroundColor: Colors.white,
      tooltip: 'הגדרות מהירות',
      onPressed: () => _show(context),
      child: const Icon(Icons.tune_rounded, size: 20),
    );
  }
}

class _QuickSettingsSheet extends StatefulWidget {
  final AppSettings settings;
  final void Function(AppSettings) onChanged;
  const _QuickSettingsSheet({required this.settings, required this.onChanged});

  @override
  State<_QuickSettingsSheet> createState() => _QuickSettingsSheetState();
}

class _QuickSettingsSheetState extends State<_QuickSettingsSheet> {
  late AppSettings _s;

  static const _personalities = ['friendly', 'formal', 'concise', 'humorous'];
  static const _personalityHe = {
    'friendly': 'ידידותי', 'formal': 'רשמי',
    'concise': 'קצר ולעניין', 'humorous': 'הומוריסטי',
  };

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
  }

  void _update(AppSettings updated) {
    setState(() => _s = updated);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: JC.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('הגדרות מהירות',
                style: TextStyle(color: JC.textPrimary, fontSize: 16,
                    fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
            const SizedBox(height: 16),

            // ── Personality ────────────────────────────────────────────────
            Text('אופי', style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
            const SizedBox(height: 8),
            Row(
              children: _personalities.map((p) {
                final selected = _s.personality == p;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final updated = AppSettings(
                        assistantName: _s.assistantName, gender: _s.gender,
                        personality: p, voiceEnabled: _s.voiceEnabled,
                        userName: _s.userName, useLocalModel: _s.useLocalModel,
                        useLocalServer: _s.useLocalServer, localServerUrl: _s.localServerUrl,
                        obsidianAutoSync: _s.obsidianAutoSync, telemetryConsent: _s.telemetryConsent,
                        bargeInEnabled: _s.bargeInEnabled, selectedTheme: _s.selectedTheme,
                        animationsEnabled: _s.animationsEnabled, ttsSpeed: _s.ttsSpeed,
                        ttsPitch: _s.ttsPitch, ttsLanguage: _s.ttsLanguage, ttsVoiceName: _s.ttsVoiceName,
                        cloudProvider: _s.cloudProvider, localModelName: _s.localModelName,
                        temperature: _s.temperature, responseLength: _s.responseLength,
                        notificationsEnabled: _s.notificationsEnabled,
                        quietHoursStart: _s.quietHoursStart, quietHoursEnd: _s.quietHoursEnd,
                        homeCardOrder: _s.homeCardOrder, homeCardsHidden: _s.homeCardsHidden,
                      );
                      _update(updated);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? JC.blue500 : JC.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? JC.blue500 : JC.border, width: 1),
                      ),
                      child: Text(
                        _personalityHe[p] ?? p,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : JC.textSecondary,
                          fontSize: 11, fontFamily: 'Heebo',
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Voice toggle ───────────────────────────────────────────────
            _toggleRow(
              icon: _s.voiceEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              label: 'קול',
              subtitle: _s.voiceEnabled ? 'ג\'רוויס מדבר בקול' : 'ג\'רוויס כותב בלבד',
              value: _s.voiceEnabled,
              onChanged: (v) {
                _s.voiceEnabled = v;
                _update(_s);
              },
            ),
            const Divider(height: 1),

            // ── Server toggle ──────────────────────────────────────────────
            _toggleRow(
              icon: _s.useLocalServer ? Icons.home_rounded : Icons.cloud_outlined,
              label: 'שרת',
              subtitle: _s.useLocalServer ? 'מקומי (${_s.localServerUrl})' : 'ענן',
              value: _s.useLocalServer,
              onChanged: (v) {
                _s.useLocalServer = v;
                _update(_s);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: JC.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: JC.textPrimary, fontSize: 14, fontFamily: 'Heebo')),
                  Text(subtitle, style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: JC.blue400,
            ),
          ],
        ),
      );
}
