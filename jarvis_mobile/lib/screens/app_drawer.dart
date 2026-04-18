import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../settings_screen.dart';
import '../transitions/slide_fade_route.dart';

class AppDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onNavigate;
  final AppSettings settings;
  final ValueChanged<AppSettings>? onSettingsChanged;

  const AppDrawer({
    super.key,
    required this.selectedIndex,
    required this.onNavigate,
    required this.settings,
    this.onSettingsChanged,
  });

  String _hebrewDate() {
    final now = DateTime.now();
    const days   = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    const months = ['ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
                    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'];
    return 'יום ${days[now.weekday % 7]}, ${now.day} ב${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: JC.surface,
      child: Column(
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 20,
              right: 20,
              left: 20,
            ),
            decoration: const BoxDecoration(
              color: JC.surfaceAlt,
              border: Border(bottom: BorderSide(color: JC.border, width: 0.8)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [JC.blue400, JC.blue500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        settings.userName.isEmpty ? 'ג׳רביס' : settings.userName,
                        style: const TextStyle(
                          color: JC.textPrimary, fontSize: 16,
                          fontWeight: FontWeight.w600, fontFamily: 'Heebo',
                        ),
                      ),
                      Text(
                        _hebrewDate(),
                        style: const TextStyle(
                          color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Nav items ────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.mic_rounded,
                  label: 'שיחה',
                  selected: selectedIndex == 1,
                  onTap: () { Navigator.pop(context); onNavigate(1); },
                ),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'לוח בקרה',
                  selected: selectedIndex == 0,
                  onTap: () { Navigator.pop(context); onNavigate(0); },
                ),
                _NavItem(
                  icon: Icons.checklist_rounded,
                  label: 'משימות',
                  selected: selectedIndex == 2,
                  onTap: () { Navigator.pop(context); onNavigate(2); },
                ),
                _NavItem(
                  icon: Icons.notifications_rounded,
                  label: 'תזכורות',
                  selected: selectedIndex == 3,
                  onTap: () { Navigator.pop(context); onNavigate(3); },
                ),
                _NavItem(
                  icon: Icons.list_alt_rounded,
                  label: 'רשימות',
                  selected: selectedIndex == 4,
                  onTap: () { Navigator.pop(context); onNavigate(4); },
                ),
              ],
            ),
          ),

          // ── Settings footer ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: JC.border, width: 0.8)),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: const Icon(Icons.settings_outlined,
                  color: JC.textMuted, size: 22),
              title: const Text(
                'הגדרות',
                style: TextStyle(
                    color: JC.textSecondary,
                    fontSize: 15,
                    fontFamily: 'Heebo'),
                textDirection: TextDirection.rtl,
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SlideFadeRoute(
                    page: SettingsScreen(
                      settings: settings,
                      onSave: (updated) async {
                        await updated.save();
                        onSettingsChanged?.call(updated);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? JC.blue500.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(icon,
            color: selected ? JC.blue400 : JC.textMuted, size: 22),
        title: Text(
          label,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: selected ? JC.blue400 : JC.textSecondary,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            fontFamily: 'Heebo',
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
