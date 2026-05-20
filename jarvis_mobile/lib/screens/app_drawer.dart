import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../settings_screen.dart';
import '../history_screen.dart';
import '../transitions/slide_fade_route.dart';
import 'control_center_preview_screen.dart';
import 'smart_productivity_preview_screen.dart';

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

  Future<void> _confirmExit(BuildContext context) async {
    Navigator.pop(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('יציאה מהאפליקציה', style: TextStyle(fontFamily: 'Heebo')),
          content: const Text('האם לצאת מהאפליקציה?', style: TextStyle(fontFamily: 'Heebo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('יציאה', style: TextStyle(color: JC.cancelRed)),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: cs.surface,
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
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              border: Border(bottom: BorderSide(color: cs.outline, width: 0.8)),
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
                _DrawerTile(
                  icon: Icons.logout_rounded,
                  label: 'יציאה',
                  onTap: () => _confirmExit(context),
                ),

                // ── מעבדת Jarvis ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: const [
                      Icon(Icons.science_outlined, size: 13, color: JC.blue400),
                      SizedBox(width: 6),
                      Text(
                        'מעבדת Jarvis',
                        style: TextStyle(
                          color: JC.blue400,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                _DrawerTile(
                  icon: Icons.hub_rounded,
                  label: 'מרכז שליטה · Preview',
                  trailing: _PreviewBadge(),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      SlideFadeRoute(
                        page: ControlCenterPreviewScreen(settings: settings),
                      ),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'מנהל יום חכם · Preview',
                  trailing: _PreviewBadge(),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      SlideFadeRoute(
                        page: SmartProductivityPreviewScreen(settings: settings),
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

class _PreviewBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E4A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JC.blue500, width: 0.6),
      ),
      child: const Text(
        'Preview',
        style: TextStyle(
          color: JC.blue400,
          fontSize: 10,
          fontFamily: 'Heebo',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Icon(icon, color: cs.onSurfaceVariant, size: 22),
        title: Text(
          label,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 15,
            fontFamily: 'Heebo',
          ),
        ),
        trailing: trailing ??
            Icon(Icons.chevron_left_rounded,
                color: cs.onSurfaceVariant, size: 20),
        onTap: onTap,
      ),
    );
  }
}
