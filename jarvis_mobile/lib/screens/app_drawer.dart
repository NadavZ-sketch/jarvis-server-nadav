import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../settings_screen.dart';
import '../history_screen.dart';
import '../transitions/slide_fade_route.dart';

class AppDrawer extends StatelessWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings>? onSettingsChanged;

  const AppDrawer({
    super.key,
    required this.settings,
    this.onSettingsChanged,
  });

  String _hebrewDate() {
    final now = DateTime.now();
    const days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    const months = [
      'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
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
                  width: 46,
                  height: 46,
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
                          color: JC.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Heebo',
                        ),
                      ),
                      Text(
                        _hebrewDate(),
                        style: const TextStyle(
                          color: JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Secondary nav ────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerTile(
                  icon: Icons.history_rounded,
                  label: 'היסטוריית שיחות',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      SlideFadeRoute(page: const HistoryScreen()),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.settings_outlined,
                  label: 'הגדרות',
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
              ],
            ),
          ),

          // ── Footer (version / branding) ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: JC.border, width: 0.8)),
            ),
            child: const Text(
              'Jarvis · העוזר האישי שלך',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JC.textMuted,
                fontSize: 12,
                fontFamily: 'Heebo',
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(icon, color: JC.textMuted, size: 22),
        title: Text(
          label,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            color: JC.textSecondary,
            fontSize: 15,
            fontFamily: 'Heebo',
          ),
        ),
        trailing: const Icon(Icons.chevron_left_rounded,
            color: JC.textMuted, size: 20),
        onTap: onTap,
      ),
    );
  }
}
