import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../app_settings.dart';

/// מדריך שלב-אחר-שלב להפעלת השרת המקומי וחיבור האפליקציה אליו.
class LocalModelSetupScreen extends StatefulWidget {
  final AppSettings settings;
  const LocalModelSetupScreen({super.key, required this.settings});

  @override
  State<LocalModelSetupScreen> createState() => _LocalModelSetupScreenState();
}

class _LocalModelSetupScreenState extends State<LocalModelSetupScreen> {
  int _step = 0;
  final _ipCtrl = TextEditingController();
  String? _pingMsg;
  bool _pinging = false;

  static const int _totalSteps = 3;

  String get _serverUrl {
    final raw = _ipCtrl.text.trim();
    if (raw.isEmpty) return AppSettings.defaultLocalServerUrl;
    if (raw.startsWith('http')) return raw;
    return 'http://$raw:3000';
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _ping() async {
    final url = _serverUrl;
    if (url.isEmpty) {
      setState(() => _pingMsg = '⚠️ הזן כתובת IP תחילה');
      return;
    }
    setState(() {
      _pinging = true;
      _pingMsg = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        setState(() => _pingMsg = '✅ השרת פעיל! ניתן לחזור ולהתחבר.');
        widget.settings.localServerUrl = url;
        widget.settings.useLocalServer = true;
        await widget.settings.save();
      } else {
        setState(() => _pingMsg = '❌ קיבלנו תשובה אבל קוד ${resp.statusCode}');
      }
    } catch (e) {
      final s = e.toString();
      if (s.contains('refused') ||
          s.contains('ClientException') ||
          s.contains('SocketException') ||
          s.contains('Failed host lookup')) {
        setState(() => _pingMsg = '❌ השרת לא זמין. באמולטור Android נסה 10.0.2.2; '
            'בטלפון אמיתי ודא ש-node server.js רץ ושהמחשב והטלפון על אותה רשת WiFi.');
      } else if (s.contains('timeout') || s.contains('TimeoutException')) {
        setState(() => _pingMsg = '❌ תם הזמן. בדוק שהכתובת נכונה: '
            '10.0.2.2 לאמולטור Android, או IP של המחשב לטלפון אמיתי.');
      } else {
        setState(() => _pingMsg = '❌ שגיאה: ${s.split('\n').first}');
      }
    } finally {
      setState(() => _pinging = false);
    }
  }

  void _done() {
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          title: const Text('הפעלת השרת המקומי',
              style: TextStyle(fontFamily: 'Heebo')),
          centerTitle: true,
        ),
        body: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(primary: JC.blue500, secondary: JC.blue400),
            canvasColor: JC.bg,
          ),
          child: Stepper(
            type: StepperType.vertical,
            currentStep: _step,
            onStepContinue: () {
              if (_step < _totalSteps - 1) {
                setState(() => _step++);
              } else {
                _done();
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
                      child: Text(
                          _step == _totalSteps - 1 ? 'סגור' : 'הבא',
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
              _buildStep1(),
              _buildStep2(),
              _buildStep3(),
            ],
          ),
        ),
      ),
    );
  }

  // ── שלב 1: הפעל את השרת ────────────────────────────────────────────────────
  Step _buildStep1() => Step(
        title: const Text('1. הפעל את השרת',
            style:
                TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 0,
        state: _step > 0 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText('פתח את VS Code בתיקיית Jarvis-Server ופתח טרמינל:'),
            const SizedBox(height: 8),
            _CmdTile(
              cmd: 'Ctrl + `',
              note: 'קיצור מקלדת לפתיחת טרמינל חדש ב-VS Code',
            ),
            const SizedBox(height: 10),
            const _InfoText('הרץ את הפקודה הזו בטרמינל:'),
            const SizedBox(height: 8),
            _CmdTile(
              cmd: 'node server.js',
            ),
            const SizedBox(height: 12),
            _SuccessTile(
              text: 'מחכים לראות בטרמינל:\n🚀 JARVIS ONLINE | MULTI-AGENT v3 | PORT: 3000',
            ),
          ],
        ),
      );

  // ── שלב 2: מצא את ה-IP ─────────────────────────────────────────────────────
  Step _buildStep2() => Step(
        title: const Text('2. מצא את ה-IP של המחשב',
            style:
                TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 1,
        state: _step > 1 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'פתח טרמינל חדש ב-VS Code (לא לסגור את זה שהשרת רץ בו) והרץ:'),
            const SizedBox(height: 8),
            _CmdTile(
              cmd: 'ipconfig',
              note: 'חפש תחת ה-WiFi שלך את השורה: "IPv4 Address"',
            ),
            const SizedBox(height: 12),
            _ExampleTile(
              lines: const [
                'Wireless LAN adapter Wi-Fi:',
                '   IPv4 Address. . . . . : 192.168.1.XX   ← זו הכתובת',
                '   Subnet Mask . . . . . : 255.255.255.0',
              ],
            ),
            const SizedBox(height: 14),
            const _InfoText('הזן את ה-IP שמצאת כאן (ללא http):'),
            const SizedBox(height: 8),
            TextField(
              controller: _ipCtrl,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              style: TextStyle(color: JC.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '192.168.1.XX',
                hintStyle: TextStyle(
                    color: JC.textMuted.withValues(alpha: 0.5),
                    fontFamily: 'monospace'),
                prefixText: 'http://',
                prefixStyle: TextStyle(color: JC.textMuted, fontFamily: 'monospace'),
                suffixText: ':3000',
                suffixStyle: TextStyle(color: JC.textMuted, fontFamily: 'monospace'),
                filled: true,
                fillColor: JC.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.border),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _WarningTile(
              text: 'הטלפון והמחשב חייבים להיות על אותה רשת WiFi.',
            ),
          ],
        ),
      );

  // ── שלב 3: בדוק חיבור ─────────────────────────────────────────────────────
  Step _buildStep3() => Step(
        title: const Text('3. בדוק חיבור',
            style:
                TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 2,
        state: StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'לחץ על הכפתור. אם השרת פועל והאייפי נכון — תקבל ✅.'),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: _pinging ? null : _ping,
              icon: _pinging
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.wifi_find_outlined),
              label: Text(_pinging ? 'בודק חיבור...' : 'בדוק חיבור לשרת',
                  style: const TextStyle(fontFamily: 'Heebo')),
            ),
            if (_pingMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JC.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JC.border),
                ),
                child: Text(_pingMsg!,
                    style: const TextStyle(
                        fontFamily: 'Heebo', fontSize: 13, height: 1.5)),
              ),
            ],
            const SizedBox(height: 16),
            _WarningTile(
              text: 'אם לא עובד: ודא ש-node server.js רץ, שהאייפי נכון, ושהטלפון על WiFi. Windows Firewall לפעמים חוסם — אשר גישה ל-Node.js אם נשאל.',
            ),
          ],
        ),
      );
}

// ── Widgets עזר ───────────────────────────────────────────────────────────────

class _InfoText extends StatelessWidget {
  final String text;
  const _InfoText(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: JC.textPrimary,
          fontSize: 13,
          fontFamily: 'Heebo',
          height: 1.5));
}

class _CmdTile extends StatelessWidget {
  final String cmd;
  final String? note;
  const _CmdTile({required this.cmd, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(8),
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
                        fontFamily: 'monospace', fontSize: 13),
                    textDirection: TextDirection.ltr),
              ),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.copy_outlined, color: JC.textMuted),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cmd));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('הועתק'),
                      duration: Duration(seconds: 1)));
                },
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!,
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ],
        ],
      ),
    );
  }
}

class _ExampleTile extends StatelessWidget {
  final List<String> lines;
  const _ExampleTile({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JC.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map((l) => Text(l,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: l.contains('←') ? JC.blue400 : JC.textMuted,
                    height: 1.6)))
            .toList(),
      ),
    );
  }
}

class _SuccessTile extends StatelessWidget {
  final String text;
  const _SuccessTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Heebo', fontSize: 12, height: 1.5)),
          ),
        ],
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
        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined,
              color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontFamily: 'Heebo', fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
