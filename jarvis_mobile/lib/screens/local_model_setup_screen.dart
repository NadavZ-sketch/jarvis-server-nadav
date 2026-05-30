import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../app_settings.dart';

/// Interactive step-by-step wizard for connecting a local LLM (Ollama)
/// running on the user's computer to the Jarvis mobile app.
class LocalModelSetupScreen extends StatefulWidget {
  final AppSettings settings;
  const LocalModelSetupScreen({super.key, required this.settings});

  @override
  State<LocalModelSetupScreen> createState() => _LocalModelSetupScreenState();
}

class _LocalModelSetupScreenState extends State<LocalModelSetupScreen> {
  int _step = 0;
  final _urlCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  String? _pingMsg;
  bool _pinging = false;
  List<String> _detectedModels = [];

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.settings.localServerUrl.replaceAll(':3000', ':11434');
    if (!_urlCtrl.text.contains('11434')) {
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
    } on SocketException {
      setState(() => _pingMsg =
          '❌ לא ניתן להתחבר. ודא ש-Ollama רץ ושהמחשב והטלפון על אותה רשת.');
    } catch (e) {
      setState(() => _pingMsg = '❌ ${e.toString().split('\n').first}');
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
              if (_step < 4) {
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
                      child: Text(_step == 4 ? 'סיים ושמור' : 'הבא',
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
              _buildInstallStep(),
              _buildPullStep(),
              _buildServeStep(),
              _buildConnectStep(),
              _buildVerifyStep(),
            ],
          ),
        ),
      ),
    );
  }

  Step _buildInstallStep() => Step(
        title: const Text('1. התקנת Ollama על המחשב',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 0,
        state: _step > 0 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'Ollama הוא שרת קוד פתוח שמריץ מודלי שפה על המחשב שלך, חינם ובלי לשלוח מידע לענן.'),
            const SizedBox(height: 12),
            _PlatformTile(
              icon: Icons.apple,
              label: 'macOS',
              cmd: 'הורד מ-ollama.com/download',
            ),
            _PlatformTile(
              icon: Icons.window,
              label: 'Windows',
              cmd: 'הורד את ה-installer מ-ollama.com/download',
            ),
            _PlatformTile(
              icon: Icons.terminal,
              label: 'Linux',
              cmd: 'curl -fsSL https://ollama.com/install.sh | sh',
              copyable: true,
            ),
          ],
        ),
      );

  Step _buildPullStep() => Step(
        title: const Text('2. הורדת מודל',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 1,
        state: _step > 1 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'פתח טרמינל (Terminal / PowerShell) והרץ את הפקודה. בחר מודל לפי הזיכרון של המחשב:'),
            const SizedBox(height: 12),
            _CmdTile(
              cmd: 'ollama pull llama3',
              note: 'מומלץ — איכותי, 4.7GB, דורש ~8GB RAM',
            ),
            _CmdTile(
              cmd: 'ollama pull gemma2:2b',
              note: 'קל ומהיר, 1.6GB, דורש ~4GB RAM',
            ),
            _CmdTile(
              cmd: 'ollama pull qwen2.5:7b',
              note: 'תומך עברית טוב יותר, 4.4GB',
            ),
          ],
        ),
      );

  Step _buildServeStep() => Step(
        title: const Text('3. הפעלת השרת לכל הרשת',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 2,
        state: _step > 2 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'כברירת מחדל Ollama מאזין רק ל-localhost. כדי שהטלפון יוכל להתחבר, הגדר משתנה סביבה:'),
            const SizedBox(height: 12),
            const _Subtitle('macOS / Linux:'),
            _CmdTile(cmd: 'export OLLAMA_HOST=0.0.0.0:11434'),
            _CmdTile(cmd: 'ollama serve'),
            const SizedBox(height: 8),
            const _Subtitle('Windows (PowerShell):'),
            _CmdTile(cmd: '\$env:OLLAMA_HOST="0.0.0.0:11434"'),
            _CmdTile(cmd: 'ollama serve'),
            const SizedBox(height: 12),
            _WarningTile(
              text: 'חשוב: הטלפון והמחשב חייבים להיות על אותה רשת WiFi. '
                  'אם יש לך Firewall, אפשר את פורט 11434.',
            ),
          ],
        ),
      );

  Step _buildConnectStep() => Step(
        title: const Text('4. הזנת כתובת המחשב',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 3,
        state: _step > 3 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoText(
                'מצא את כתובת ה-IP של המחשב ברשת המקומית והזן אותה כאן.'),
            const SizedBox(height: 8),
            const Text(
              'איך מוצאים IP?',
              style: TextStyle(
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            const SizedBox(height: 4),
            const _InfoText(
                '• macOS/Linux: הרץ ifconfig | grep "inet "\n'
                '• Windows: הרץ ipconfig וחפש "IPv4 Address"'),
            const SizedBox(height: 16),
            TextField(
              controller: _urlCtrl,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: JC.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'כתובת Ollama',
                labelStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                hintText: 'http://192.168.1.100:11434',
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

  Step _buildVerifyStep() => Step(
        title: const Text('5. בדיקת חיבור ובחירת מודל',
            style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
        isActive: _step >= 4,
        state: _step >= 4 ? StepState.indexed : StepState.indexed,
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

class _PlatformTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String cmd;
  final bool copyable;
  const _PlatformTile({
    required this.icon,
    required this.label,
    required this.cmd,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: JC.textMuted),
          const SizedBox(width: 8),
          SizedBox(
              width: 70,
              child: Text(label,
                  style:
                      const TextStyle(fontFamily: 'Heebo', fontSize: 13))),
          Expanded(
            child: copyable
                ? _CmdTile(cmd: cmd)
                : Text(cmd,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 12,
                        fontFamily: 'Heebo')),
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
