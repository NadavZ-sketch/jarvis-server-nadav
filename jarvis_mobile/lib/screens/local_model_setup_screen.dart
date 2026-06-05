import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../app_settings.dart';

/// Interactive step-by-step wizard for connecting an already-installed local
/// Ollama on the user's computer to the Jarvis mobile app — either over the
/// local WiFi network, or exposed to the cloud via a secure tunnel.
class LocalModelSetupScreen extends StatefulWidget {
  final AppSettings settings;
  const LocalModelSetupScreen({super.key, required this.settings});

  @override
  State<LocalModelSetupScreen> createState() => _LocalModelSetupScreenState();
}

enum _ConnectionMode { localNetwork, cloudTunnel }

class _LocalModelSetupScreenState extends State<LocalModelSetupScreen> {
  int _step = 0;
  _ConnectionMode _mode = _ConnectionMode.localNetwork;
  final _urlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  String? _pingMsg;
  bool _pinging = false;
  List<String> _detectedModels = [];

  static const int _totalSteps = 4;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.settings.localServerUrl.replaceAll(':3000', ':11434');
    if (!_urlCtrl.text.contains('11434') &&
        !_urlCtrl.text.contains('ngrok') &&
        !_urlCtrl.text.contains('trycloudflare')) {
      _urlCtrl.text = 'http://192.168.1.100:11434';
    }
    _modelCtrl.text = widget.settings.localModelName.isEmpty
        ? 'llama3'
        : widget.settings.localModelName;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pingOllama() async {
    setState(() {
      _pinging = true;
      _pingMsg = null;
      _detectedModels = [];
    });
    try {
      final base = _urlCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
      final resp = await http
          .get(Uri.parse('$base/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final body = resp.body;
        final modelMatches =
            RegExp(r'"name"\s*:\s*"([^"]+)"').allMatches(body);
        final names = modelMatches.map((m) => m.group(1)!).toList();
        setState(() {
          _detectedModels = names;
          _pingMsg = names.isEmpty
              ? '⚠️ Ollama רץ אבל לא נמצאו מודלים מותקנים'
              : '✅ מחובר! נמצאו ${names.length} מודלים';
          if (names.isNotEmpty && !names.contains(_modelCtrl.text)) {
            _modelCtrl.text = names.first;
          }
        });
      } else {
        setState(() => _pingMsg = '❌ שגיאה: ${resp.statusCode}');
      }
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('Failed host lookup') ||
          s.contains('refused')) {
        setState(() => _pingMsg =
            '❌ לא ניתן להתחבר. ודא ש-Ollama רץ ושהמחשב והטלפון על אותה רשת.');
      } else {
        setState(() => _pingMsg = '❌ ${s.split('\n').first}');
      }
    } finally {
      setState(() => _pinging = false);
    }
  }

  void _save() {
    widget.settings.localServerUrl = _urlCtrl.text.trim();
    widget.settings.localModelName = _modelCtrl.text.trim();
    widget.settings.useLocalModel = true;
    widget.settings.useLocalServer = false;
    widget.settings.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ ההגדרות נשמרו! המודל המקומי פעיל.'),
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
          title: const Text('חיבור מודל מקומי',
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
              _buildServeStep(),
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
                'אנחנו מניחים ש-Ollama כבר מותקן אצלך. עכשיו צריך להחליט איך הטלפון יגיע אליו:'),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.wifi_outlined,
              title: 'רשת מקומית (WiFi)',
              subtitle:
                  'הטלפון והמחשב על אותה רשת WiFi בבית. הכי מהיר, אפס עיכוב.',
              selected: _mode == _ConnectionMode.localNetwork,
              onTap: () =>
                  setState(() => _mode = _ConnectionMode.localNetwork),
            ),
            const SizedBox(height: 8),
            _ModeCard(
              icon: Icons.cloud_outlined,
              title: 'מנהרה לענן (ngrok / Cloudflare)',
              subtitle:
                  'גישה מכל מקום בעולם דרך כתובת ציבורית. מעט עיכוב, דורש כלי חיצוני.',
              selected: _mode == _ConnectionMode.cloudTunnel,
              onTap: () =>
                  setState(() => _mode = _ConnectionMode.cloudTunnel),
            ),
          ],
        ),
      );

  Step _buildServeStep() {
    final isLocal = _mode == _ConnectionMode.localNetwork;
    return Step(
      title: Text(isLocal ? '2. הפעלת השרת לרשת המקומית' : '2. הפעלת מנהרה לענן',
          style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
      isActive: _step >= 1,
      state: _step > 1 ? StepState.complete : StepState.indexed,
      content: isLocal ? _buildLocalServeContent() : _buildTunnelServeContent(),
    );
  }

  Widget _buildLocalServeContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InfoText(
              'כברירת מחדל Ollama מאזין רק ל-localhost ולא לטלפון. צריך לאפשר חיבורים מהרשת:'),
          const SizedBox(height: 12),
          const _Subtitle('macOS / Linux — בטרמינל:'),
          _CmdTile(cmd: 'export OLLAMA_HOST=0.0.0.0:11434'),
          _CmdTile(cmd: 'ollama serve'),
          const SizedBox(height: 10),
          const _Subtitle('Windows — ב-PowerShell:'),
          _CmdTile(cmd: '\$env:OLLAMA_HOST="0.0.0.0:11434"'),
          _CmdTile(cmd: 'ollama serve'),
          const SizedBox(height: 10),
          const _Subtitle('macOS עם אפליקציה רקעית — הגדרה קבועה:'),
          _CmdTile(
              cmd: 'launchctl setenv OLLAMA_HOST "0.0.0.0:11434"',
              note: 'אחרי הפקודה: צא מאפליקציית Ollama ופתח אותה שוב'),
          const SizedBox(height: 12),
          _WarningTile(
            text:
                'אם החיבור לא עובד — סביר שה-Firewall חוסם. אפשר את התעבורה הנכנסת לפורט 11434.',
          ),
        ],
      );

  Widget _buildTunnelServeContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _InfoText(
              'מנהרה (tunnel) הופכת את Ollama בלוקאל לכתובת ציבורית מאובטחת. בחר אחת מהאפשרויות:'),
          const SizedBox(height: 12),
          const _Subtitle('אפשרות א׳ — Cloudflare Tunnel (חינם, בלי הרשמה):'),
          _CmdTile(cmd: 'ollama serve'),
          _CmdTile(
              cmd: 'cloudflared tunnel --url http://localhost:11434',
              note: 'הפלט יציג כתובת מסוג https://<random>.trycloudflare.com — העתק אותה'),
          const SizedBox(height: 10),
          const _Subtitle('אפשרות ב׳ — ngrok (דורש חשבון חינם):'),
          _CmdTile(cmd: 'ollama serve'),
          _CmdTile(
              cmd: 'ngrok http 11434',
              note: 'הפלט יציג Forwarding https://xxxx.ngrok-free.app — העתק אותה'),
          const SizedBox(height: 12),
          _WarningTile(
            text:
                'אזהרה: מנהרה חושפת את ה-Ollama שלך לאינטרנט. סגור אותה כשלא בשימוש, ולא להריץ על מודלים עם מידע רגיש.',
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
                'מצא את כתובת ה-IP של המחשב ברשת המקומית והזן אותה כאן.'),
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
              labelText: isLocal ? 'כתובת Ollama' : 'כתובת מנהרה',
              labelStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
              hintText: isLocal
                  ? 'http://192.168.1.100:11434'
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
        title: const Text('4. בדיקת חיבור ובחירת מודל',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 3,
        state: StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText('בדוק שהחיבור עובד ובחר מודל מהרשימה.'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _pinging ? null : _pingOllama,
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
            if (_detectedModels.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _Subtitle('בחר מודל:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _detectedModels.map((name) {
                  final selected = _modelCtrl.text == name;
                  return ChoiceChip(
                    label: Text(name,
                        style: const TextStyle(fontFamily: 'monospace')),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _modelCtrl.text = name),
                    selectedColor: JC.blue500,
                    backgroundColor: JC.surface,
                    labelStyle: TextStyle(
                        color: selected ? Colors.white : JC.textPrimary),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _modelCtrl,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: JC.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'שם המודל',
                labelStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
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
