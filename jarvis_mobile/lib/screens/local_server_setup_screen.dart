import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../app_settings.dart';

/// Interactive step-by-step wizard for connecting the Jarvis mobile app
/// to a Jarvis **server** running on the user's own computer — either over
/// the local WiFi network, or exposed to the cloud via a secure tunnel.
class LocalServerSetupScreen extends StatefulWidget {
  final AppSettings settings;
  const LocalServerSetupScreen({super.key, required this.settings});

  @override
  State<LocalServerSetupScreen> createState() => _LocalServerSetupScreenState();
}

enum _ConnectionMode { localNetwork, cloudTunnel }

class _LocalServerSetupScreenState extends State<LocalServerSetupScreen> {
  int _step = 0;
  _ConnectionMode _mode = _ConnectionMode.localNetwork;
  final _urlCtrl = TextEditingController();
  String? _pingMsg;
  bool _pinging = false;

  static const int _totalSteps = 4;

  @override
  void initState() {
    super.initState();
    final existing = widget.settings.localServerUrl.trim();
    if (existing.isEmpty) {
      _urlCtrl.text = 'http://192.168.1.100:3000';
    } else {
      _urlCtrl.text = existing;
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pingServer() async {
    setState(() {
      _pinging = true;
      _pingMsg = null;
    });
    try {
      final base = _urlCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
      final resp = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        setState(() => _pingMsg = '✅ השרת מחובר ומגיב!');
      } else {
        setState(() => _pingMsg = '⚠️ השרת ענה עם קוד ${resp.statusCode}');
      }
    } on SocketException {
      setState(() => _pingMsg =
          '❌ לא ניתן להתחבר. ודא שהשרת רץ ושהמחשב והטלפון על אותה רשת.');
    } catch (e) {
      setState(() => _pingMsg = '❌ ${e.toString().split('\n').first}');
    } finally {
      setState(() => _pinging = false);
    }
  }

  void _save() {
    widget.settings.localServerUrl = _urlCtrl.text.trim();
    widget.settings.useLocalServer = true;
    widget.settings.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ ההגדרות נשמרו! האפליקציה מחוברת לשרת המקומי.'),
      ));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          title: const Text('חיבור לשרת מקומי',
              style: TextStyle(fontFamily: 'Heebo')),
          centerTitle: true,
        ),
        body: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: JC.blue500,
                  secondary: JC.blue400,
                ),
            canvasColor: JC.bg,
          ),
          child: Stepper(
            type: StepperType.vertical,
            currentStep: _step,
            onStepContinue: () {
              if (_step < _totalSteps - 1) {
                setState(() => _step++);
              } else {
                _save();
              }
            },
            onStepCancel: () {
              if (_step > 0) setState(() => _step--);
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JC.blue500,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: details.onStepContinue,
                      child: Text(_step == _totalSteps - 1 ? 'סיים ושמור' : 'הבא',
                          style: const TextStyle(fontFamily: 'Heebo')),
                    ),
                    const SizedBox(width: 8),
                    if (_step > 0)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: const Text('חזור',
                            style: TextStyle(fontFamily: 'Heebo')),
                      ),
                  ],
                ),
              );
            },
            steps: [
              _buildModeStep(),
              _buildStartStep(),
              _buildAddressStep(),
              _buildVerifyStep(),
            ],
          ),
        ),
      ),
    );
  }

  Step _buildModeStep() => Step(
        title: const Text('1. בחר איך להתחבר',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 0,
        state: _step > 0 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'הפרויקט כבר מותקן על המחשב שלך. צריך רק להחליט איך הטלפון יגיע אליו:'),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.wifi_outlined,
              title: 'רשת מקומית (WiFi)',
              subtitle:
                  'הטלפון והמחשב על אותה רשת. הכי מהיר ופשוט — אפס עיכוב.',
              selected: _mode == _ConnectionMode.localNetwork,
              onTap: () =>
                  setState(() => _mode = _ConnectionMode.localNetwork),
            ),
            const SizedBox(height: 8),
            _ModeCard(
              icon: Icons.cloud_outlined,
              title: 'מנהרה לענן (Cloudflare / ngrok)',
              subtitle:
                  'גישה מכל מקום בעולם דרך כתובת ציבורית. דורש כלי חיצוני.',
              selected: _mode == _ConnectionMode.cloudTunnel,
              onTap: () =>
                  setState(() => _mode = _ConnectionMode.cloudTunnel),
            ),
          ],
        ),
      );

  Step _buildStartStep() {
    final isLocal = _mode == _ConnectionMode.localNetwork;
    return Step(
      title: Text(isLocal ? '2. הפעלת השרת במחשב' : '2. הפעלת השרת + מנהרה',
          style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
      isActive: _step >= 1,
      state: _step > 1 ? StepState.complete : StepState.indexed,
      content: isLocal ? _buildLocalStartContent() : _buildTunnelStartContent(),
    );
  }

  Widget _buildLocalStartContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InfoText(
              'בטרמינל במחשב — היכנס לתיקיית הפרויקט והפעל את השרת:'),
          const SizedBox(height: 12),
          const _Subtitle('macOS / Linux / Windows:'),
          _CmdTile(cmd: 'cd jarvis-server-nadav'),
          _CmdTile(
              cmd: 'node server.js',
              note: 'אמור להופיע: 🚀 JARVIS ONLINE | PORT: 3000'),
          const SizedBox(height: 10),
          const _Subtitle('הרצה ברקע (אופציונלי, דורש pm2):'),
          _CmdTile(cmd: 'pm2 start server.js --name jarvis'),
          const SizedBox(height: 12),
          _WarningTile(
            text:
                'אם הטלפון לא רואה את השרת — סביר שה-Firewall של המחשב חוסם. אפשר תעבורה נכנסת לפורט 3000.',
          ),
        ],
      );

  Widget _buildTunnelStartContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InfoText(
              'הפעל את השרת ובמקביל פתח מנהרה שתחשוף אותו לאינטרנט עם כתובת ציבורית:'),
          const SizedBox(height: 12),
          const _Subtitle('שלב 1 — הפעל את השרת:'),
          _CmdTile(cmd: 'cd jarvis-server-nadav && node server.js'),
          const SizedBox(height: 10),
          const _Subtitle('שלב 2 — פתח מנהרה בטרמינל נוסף:'),
          _CmdTile(
              cmd: 'cloudflared tunnel --url http://localhost:3000',
              note: 'הפלט יציג https://<random>.trycloudflare.com — העתק אותה'),
          const SizedBox(height: 8),
          const _Subtitle('או חלופית עם ngrok:'),
          _CmdTile(
              cmd: 'ngrok http 3000',
              note: 'הפלט יציג Forwarding https://xxxx.ngrok-free.app'),
          const SizedBox(height: 12),
          _WarningTile(
            text:
                'אזהרה: מנהרה חושפת את השרת לאינטרנט. סגור אותה כשלא בשימוש.',
          ),
        ],
      );

  Step _buildAddressStep() {
    final isLocal = _mode == _ConnectionMode.localNetwork;
    return Step(
      title: Text(isLocal ? '3. הזנת כתובת המחשב ברשת' : '3. הזנת כתובת המנהרה',
          style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
      isActive: _step >= 2,
      state: _step > 2 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isLocal) ...[
            const _InfoText(
                'מצא את כתובת ה-IP של המחשב ברשת המקומית והזן אותה כאן (פורט 3000).'),
            const SizedBox(height: 8),
            const Text('איך מוצאים IP?',
                style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 4),
            const _InfoText('• macOS/Linux: ifconfig | grep "inet "\n'
                '• Windows: ipconfig וחפש "IPv4 Address"'),
          ] else ...[
            const _InfoText(
                'הדבק כאן את הכתובת הציבורית שהמנהרה החזירה (trycloudflare.com / ngrok-free.app).'),
            const SizedBox(height: 8),
            _WarningTile(
              text:
                  'הקפד שזו כתובת HTTPS מלאה ללא רווחים. הכתובת משתנה בכל הפעלה של המנהרה.',
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: JC.textPrimary, fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: isLocal ? 'כתובת השרת' : 'כתובת מנהרה',
              labelStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
              hintText: isLocal
                  ? 'http://192.168.1.100:3000'
                  : 'https://xxxx.trycloudflare.com',
              hintStyle:
                  TextStyle(color: JC.textMuted.withValues(alpha: 0.5)),
              filled: true,
              fillColor: JC.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: JC.border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Step _buildVerifyStep() => Step(
        title: const Text('4. בדיקת חיבור',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 3,
        state: StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText('בדוק שהשרת עונה לכתובת שהזנת.'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _pinging ? null : _pingServer,
              icon: _pinging
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.wifi_find),
              label: Text(_pinging ? 'בודק...' : 'בדוק חיבור',
                  style: const TextStyle(fontFamily: 'Heebo')),
            ),
            if (_pingMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: JC.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JC.border),
                ),
                child: Text(_pingMsg!,
                    style: const TextStyle(fontFamily: 'Heebo', fontSize: 13)),
              ),
            ],
            const SizedBox(height: 12),
            const _InfoText(
                'בלחיצה על "סיים ושמור" — האפליקציה תעבור להשתמש בכתובת הזו.'),
          ],
        ),
      );
}

class _InfoText extends StatelessWidget {
  final String text;
  const _InfoText(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: JC.textPrimary, fontSize: 13, fontFamily: 'Heebo', height: 1.5));
}

class _Subtitle extends StatelessWidget {
  final String text;
  const _Subtitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: JC.textMuted,
          fontSize: 12,
          fontFamily: 'Heebo',
          fontWeight: FontWeight.bold));
}

class _CmdTile extends StatelessWidget {
  final String cmd;
  final String? note;
  const _CmdTile({required this.cmd, this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: JC.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText(cmd,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      textDirection: TextDirection.ltr),
                ),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: cmd));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('הועתק'),
                        duration: Duration(seconds: 1)));
                  },
                ),
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(note!,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo')),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? JC.blue500.withValues(alpha: 0.12)
              : JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? JC.blue500 : JC.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 24,
                color: selected ? JC.blue500 : JC.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: selected ? JC.blue500 : JC.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 12,
                          color: JC.textMuted,
                          height: 1.4)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: JC.blue500),
          ],
        ),
      ),
    );
  }
}

class _WarningTile extends StatelessWidget {
  final String text;
  const _WarningTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Heebo', fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
