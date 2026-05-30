import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_settings.dart';
import 'main.dart' show JC;
import 'theme/theme_notifier.dart';
import 'widgets/theme_picker.dart';
import 'services/api_service.dart';
import 'screens/local_model_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final Function(AppSettings) onSave;

  const SettingsScreen({super.key, required this.settings, required this.onSave});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _ServerPreset {
  final String label;
  final String url;
  final IconData icon;
  const _ServerPreset(this.label, this.url, this.icon);
}

const _kPresets = [
  _ServerPreset('localhost',    'http://localhost:3000',       Icons.computer_outlined),
  _ServerPreset('192.168.1.x',  'http://192.168.1.100:3000',  Icons.wifi_outlined),
  _ServerPreset('10.0.0.x',     'http://10.0.0.2:3000',       Icons.router_outlined),
  _ServerPreset('מותאם אישית', '',                             Icons.edit_outlined),
];

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s;
  late TextEditingController _assistantNameCtrl;
  late TextEditingController _userNameCtrl;
  late TextEditingController _localServerUrlCtrl;
  late TextEditingController _localModelCtrl;
  late TextEditingController _briefingFocusCtrl;
  String? _pingResult;
  int _selectedPreset = -1; // index into _kPresets, -1 = custom
  String? _obsidianSyncStatus;
  String? _personalityPreview;
  bool _personalityPreviewLoading = false;

  // TTS preview
  final FlutterTts _tts = FlutterTts();
  List<String> _voiceNames = [];

  // Permissions
  PermissionStatus _micStatus        = PermissionStatus.denied;
  PermissionStatus _cameraStatus     = PermissionStatus.denied;
  PermissionStatus _photosStatus     = PermissionStatus.denied;
  PermissionStatus _notifStatus      = PermissionStatus.denied;

  @override
  void initState() {
    super.initState();
    final w = widget.settings;
    _s = AppSettings(
      assistantName:    w.assistantName,
      gender:           w.gender,
      personality:      w.personality,
      voiceEnabled:     w.voiceEnabled,
      userName:         w.userName,
      useLocalModel:    w.useLocalModel,
      useLocalServer:   w.useLocalServer,
      localServerUrl:   w.localServerUrl,
      obsidianAutoSync: w.obsidianAutoSync,
      telemetryConsent: w.telemetryConsent,
      bargeInEnabled:   w.bargeInEnabled,
      selectedTheme:    w.selectedTheme,
      animationsEnabled: w.animationsEnabled,
      ttsSpeed:         w.ttsSpeed,
      ttsPitch:         w.ttsPitch,
      ttsLanguage:      w.ttsLanguage,
      ttsVoiceName:     w.ttsVoiceName,
      cloudProvider:    w.cloudProvider,
      openrouterModel:  w.openrouterModel,
      localModelName:   w.localModelName,
      temperature:      w.temperature,
      responseLength:   w.responseLength,
      notificationsEnabled: w.notificationsEnabled,
      quietHoursStart:  w.quietHoursStart,
      quietHoursEnd:    w.quietHoursEnd,
      homeCardOrder:    w.homeCardOrder,
      homeCardsHidden:  w.homeCardsHidden,
    );
    _assistantNameCtrl  = TextEditingController(text: _s.assistantName);
    _userNameCtrl       = TextEditingController(text: _s.userName);
    _localServerUrlCtrl = TextEditingController(text: _s.localServerUrl);
    _localModelCtrl     = TextEditingController(text: _s.localModelName);
    _briefingFocusCtrl  = TextEditingController(text: _s.todayBriefingFocus);
    _detectPreset(_s.localServerUrl);
    _loadPermissions();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final voices = await _tts.getVoices;
      if (voices is List && mounted) {
        final names = <String>[];
        for (final v in voices) {
          if (v is Map) {
            final locale = (v['locale'] ?? '').toString().toLowerCase();
            final name = (v['name'] ?? '').toString();
            // Hebrew + English voices only, to keep the list relevant
            if (name.isNotEmpty &&
                (locale.startsWith('he') || locale.startsWith('iw') ||
                 locale.startsWith('en'))) {
              names.add(name);
            }
          }
        }
        final sorted = names.toSet().toList()..sort();
        setState(() {
          _voiceNames = sorted;
          // Clear a stale voice name saved from a different device/OS version
          if (_s.ttsVoiceName.isNotEmpty && !sorted.contains(_s.ttsVoiceName)) {
            _s.ttsVoiceName = '';
          }
        });
      }
    } catch (_) {/* voices unavailable on this platform */}
  }

  Future<void> _previewTts() async {
    try {
      await _tts.setLanguage(_s.ttsLanguage);
      await _tts.setSpeechRate(_s.ttsSpeed);
      await _tts.setPitch(_s.ttsPitch);
      if (_s.ttsVoiceName.isNotEmpty) {
        await _tts.setVoice({'name': _s.ttsVoiceName, 'locale': _s.ttsLanguage});
      }
      await _tts.speak(_s.ttsLanguage.startsWith('he')
          ? 'שלום, אני ${_s.assistantName}. כך אני נשמע.'
          : 'Hello, I am ${_s.assistantName}. This is how I sound.');
    } catch (_) {/* ignore preview failures */}
  }

  Future<void> _loadPermissions() async {
    final mic    = await Permission.microphone.status;
    final camera = await Permission.camera.status;
    final photos = await Permission.photos.status;
    final notif  = await Permission.notification.status;
    if (!mounted) return;
    setState(() {
      _micStatus    = mic;
      _cameraStatus = camera;
      _photosStatus = photos;
      _notifStatus  = notif;
    });
  }

  Future<void> _requestPermission(Permission permission) async {
    final current = await permission.status;
    // Granted/limited → open system settings so user can revoke
    if (current.isGranted || current.isLimited) {
      await openAppSettings();
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadPermissions();
      return;
    }
    final status = await permission.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await _loadPermissions();
  }

  void _detectPreset(String url) {
    for (int i = 0; i < _kPresets.length - 1; i++) {
      if (_kPresets[i].url == url) { _selectedPreset = i; return; }
    }
    // custom
    _selectedPreset = _kPresets.length - 1;
  }

  void _selectPreset(int i) {
    setState(() {
      _selectedPreset = i;
      _pingResult = null;
      if (_kPresets[i].url.isNotEmpty) {
        _localServerUrlCtrl.text = _kPresets[i].url;
      }
    });
  }

  @override
  void dispose() {
    _assistantNameCtrl.dispose();
    _userNameCtrl.dispose();
    _localServerUrlCtrl.dispose();
    _localModelCtrl.dispose();
    _briefingFocusCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  void _save() {
    _s.assistantName  = _assistantNameCtrl.text.trim().isEmpty ? 'Jarvis'                    : _assistantNameCtrl.text.trim();
    _s.userName       = _userNameCtrl.text.trim().isEmpty      ? 'נדב'                       : _userNameCtrl.text.trim();
    _s.localServerUrl = _localServerUrlCtrl.text.trim().isEmpty? 'http://192.168.1.100:3000' : _localServerUrlCtrl.text.trim();
    _s.localModelName = _localModelCtrl.text.trim().isEmpty    ? 'llama3'                     : _localModelCtrl.text.trim();
    _s.todayBriefingFocus = _briefingFocusCtrl.text.trim();
    widget.onSave(_s);
    // Fire-and-forget: sync identity fields to Supabase so they survive
    // device reinstalls. SharedPreferences remains the source of truth locally.
    ApiService(_s).saveUserProfile(
      userName:      _s.userName,
      assistantName: _s.assistantName,
      gender:        _s.gender,
      personality:   _s.personality,
    ).catchError((_) {});
    Navigator.pop(context);
  }

  Future<void> _previewPersonality() async {
    setState(() { _personalityPreviewLoading = true; _personalityPreview = null; });
    try {
      final result = await ApiService(_s).askJarvis('שלום! תציג את עצמך במשפט אחד.', _s);
      if (!mounted) return;
      setState(() => _personalityPreview = result['answer']?.toString() ?? '');
    } catch (e) {
      if (!mounted) return;
      setState(() => _personalityPreview = '❌ ${ApiService.friendlyError(e is Exception ? e : Exception(e.toString()))}');
    } finally {
      if (mounted) setState(() => _personalityPreviewLoading = false);
    }
  }

  Future<void> _syncObsidian() async {
    setState(() => _obsidianSyncStatus = '⏳ מסנכרן...');
    try {
      final res = await http
          .post(Uri.parse('${_s.serverUrl}/sync/obsidian'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        setState(() => _obsidianSyncStatus = '✅ הסנכרון הושלם');
      } else {
        setState(() => _obsidianSyncStatus = '⚠️ שגיאה ${res.statusCode}');
      }
    } on Exception catch (e) {
      setState(() => _obsidianSyncStatus = '❌ ${ApiService.friendlyError(e)}');
    }
  }

  Future<void> _setObsidianAutoSync(bool enabled) async {
    setState(() => _s.obsidianAutoSync = enabled);
    try {
      await http
          .post(
            Uri.parse('${_s.serverUrl}/sync/obsidian/auto'),
            headers: {'Content-Type': 'application/json'},
            body: '{"enabled":$enabled}',
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // fire-and-forget; server will pick it up on next sync
    }
  }



  Future<void> _resetTelemetry() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JC.surface,
        title: const Text('איפוס למידה / Telemetry', textAlign: TextAlign.right),
        content: const Text('הפעולה תמחק אירועי Telemetry מהשרת ומהמכשיר (אם קיימים). לא ניתן לשחזר.', textAlign: TextAlign.right),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ביטול')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('איפוס')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await http.post(
        Uri.parse('${_s.serverUrl}/dashboard/smart-telemetry/reset'),
        headers: {'Content-Type': 'application/json'},
        body: '{"scope":"user"}',
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('בוצע איפוס Telemetry.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('לא הצלחנו לאפס כרגע. נסה שוב.')));
    }
  }
  Future<void> _openProgressMap() async {
    final uri = Uri.parse('${_s.serverUrl}/progress-map');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('לא ניתן לפתוח את מפת ההתקדמות')),
        );
      }
    }
  }

  Future<void> _pingServer() async {
    final url = _localServerUrlCtrl.text.trim().isEmpty
        ? 'http://192.168.1.100:3000'
        : _localServerUrlCtrl.text.trim();

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _pingResult = '❌ כתובת לא תקינה — חייבת להתחיל ב-http:// או https://');
      return;
    }

    setState(() => _pingResult = '⏳ בודק...');
    try {
      final res = await http
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _pingResult = '✅ השרת פעיל ב-$url');
      } else {
        setState(() => _pingResult = '⚠️ השרת ענה קוד ${res.statusCode} מ-$url');
      }
    } catch (e) {
      if (!mounted) return;
      final err = e.toString();
      final hint = err.contains('timeout')
          ? 'הבקשה פגה — השרת לא מגיב.\nוודא ש-node server.js רץ.'
          : err.contains('refused') || err.contains('Failed host lookup') || err.contains('NetworkError')
              ? 'חיבור נדחה — בדוק:\n1. node server.js רץ?\n2. ה-IP נכון?\n3. פורט 3000 פתוח?'
              : ApiService.friendlyError(e is Exception ? e : Exception(err));
      setState(() => _pingResult = '❌ $hint');
    }
  }

  // ─── Permission helpers ───────────────────────────────────────────────────────

  Color _permColor(PermissionStatus s) {
    if (s.isGranted || s.isLimited)        return const Color(0xFF22C55E);
    if (s.isDenied)                        return const Color(0xFFF59E0B);
    if (s.isPermanentlyDenied)             return const Color(0xFFEF4444);
    return JC.textMuted;
  }

  String _permLabel(PermissionStatus s) {
    if (s.isGranted)           return 'מאושר · נהל';
    if (s.isLimited)           return 'מוגבל · נהל';
    if (s.isPermanentlyDenied) return 'חסום — פתח הגדרות';
    if (s.isDenied)            return 'לא אושר';
    return 'לא ידוע';
  }

  IconData _permIcon(PermissionStatus s) {
    if (s.isGranted || s.isLimited)  return Icons.check_circle_rounded;
    if (s.isPermanentlyDenied)       return Icons.block_rounded;
    return Icons.radio_button_unchecked_rounded;
  }

  Widget _permRow({
    required String label,
    required String description,
    required IconData rowIcon,
    required PermissionStatus status,
    required Permission permission,
  }) {
    final color = _permColor(status);
    return InkWell(
      onTap: () => _requestPermission(permission),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(rowIcon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(
                          color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_permLabel(status),
                    style: TextStyle(
                        color: color, fontSize: 12,
                        fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Icon(_permIcon(status), color: color, size: 17),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
    child: Row(
      children: [
        Icon(icon, size: 13, color: JC.blue400),
        const SizedBox(width: 7),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: JC.blue400,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            fontFamily: 'Heebo',
          ),
        ),
      ],
    ),
  );

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    decoration: BoxDecoration(
      color: JC.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: JC.border.withValues(alpha: 0.7), width: 0.8),
    ),
    child: Column(children: children),
  );

  Widget _divider() => Divider(
    color: JC.border.withValues(alpha: 0.5),
    height: 1,
    indent: 16,
    endIndent: 16,
  );

  Widget _rowField({
    required String label,
    required IconData icon,
    required TextEditingController ctrl,
    required String hint,
    TextDirection textDir = TextDirection.ltr,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    fontFamily: 'Heebo')),
            const Spacer(),
            SizedBox(
              width: 150,
              child: TextField(
                controller: ctrl,
                textAlign: TextAlign.end,
                textDirection: textDir,
                style: TextStyle(
                    color: JC.textSecondary,
                    fontSize: 14,
                    fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(color: JC.textMuted.withValues(alpha: 0.6)),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _rowDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    fontFamily: 'Heebo')),
            const Spacer(),
            DropdownButton<T>(
              value: value,
              dropdownColor: JC.surface,
              underline: const SizedBox(),
              icon: Icon(Icons.expand_more_rounded,
                  color: JC.textMuted, size: 18),
              style: TextStyle(
                  color: JC.textSecondary,
                  fontSize: 14,
                  fontFamily: 'Heebo'),
              items: items,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  Widget _quietHourRow({
    required String label,
    required IconData icon,
    required int hour,
    required void Function(int) onPick,
  }) =>
      InkWell(
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: hour, minute: 0),
            builder: (ctx, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          );
          if (picked != null) onPick(picked.hour);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: JC.textMuted),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
              const Spacer(),
              Text('${hour.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                      color: JC.blue400, fontSize: 14,
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Widget _rowSlider({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String Function(double) display,
    required void Function(double) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: JC.textMuted),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                        color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
                const Spacer(),
                Text(display(value),
                    style: TextStyle(
                        color: JC.blue400, fontSize: 13, fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: JC.blue500,
                inactiveTrackColor: JC.border,
                thumbColor: JC.blue400,
                overlayColor: JC.blue500.withValues(alpha: 0.18),
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );

  static const List<int> _orbPalette = [
    0xFFFFFFFF, 0xFF666666, 0xFF44CCFF, 0xFF38BDF8,
    0xFF00FFCC, 0xFFA78BFA, 0xFFFF44AA, 0xFFFFB020,
    0xFF22C55E, 0xFFEF4444,
  ];

  Widget _orbColorRow({
    required String label,
    required int selected,
    required void Function(int) onPick,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _orbPalette.map((c) {
                final isSel = c == selected;
                return GestureDetector(
                  onTap: () => onPick(c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSel ? JC.blue400 : JC.border,
                        width: isSel ? 2.5 : 1,
                      ),
                    ),
                    child: isSel
                        ? Icon(Icons.check_rounded,
                            size: 16,
                            color: Color(c) == const Color(0xFFFFFFFF)
                                ? Colors.black
                                : Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      );

  Widget _rowSwitch({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool value,
    required void Function(bool) onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: JC.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 15,
                          fontFamily: 'Heebo')),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo')),
                ],
              ),
            ),
            Switch(
              value: value,
              activeColor: Colors.white,
              activeTrackColor: JC.blue500,
              inactiveThumbColor: JC.textMuted,
              inactiveTrackColor: JC.border,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final initials = _s.userName.isNotEmpty
        ? _s.userName[0].toUpperCase()
        : 'J';

    return Scaffold(
      backgroundColor: JC.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: JC.textSecondary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'הגדרות',
          style: TextStyle(
            color: JC.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 17,
            fontFamily: 'Heebo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'שמור',
              style: TextStyle(
                color: JC.blue400,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                fontFamily: 'Heebo',
              ),
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 100),

            // ── Profile card ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [JC.blue500.withValues(alpha: 0.15), JC.surfaceAlt],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: JC.blue500.withValues(alpha: 0.3), width: 0.8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [JC.blue400, JC.blue500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: JC.blue500.withValues(alpha: 0.4),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Heebo',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _s.userName,
                            style: TextStyle(
                              color: JC.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Heebo',
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF22C55E),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF22C55E).withValues(alpha: 0.5),
                                      blurRadius: 4,
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_s.assistantName} פעיל',
                                style: TextStyle(
                                  color: JC.textSecondary,
                                  fontSize: 13,
                                  fontFamily: 'Heebo',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── מראה ─────────────────────────────────────────────────────────
            _sectionHeader('מראה ועיצוב', Icons.palette_outlined),
            ThemePicker(
              selected: _s.selectedTheme,
              onSelected: (t) {
                setState(() => _s.selectedTheme = t);
                ThemeNotifier.of(context).value = t; // live preview
              },
            ),
            const SizedBox(height: 6),
            _card([
              _rowSwitch(
                label: 'אנימציות עשירות',
                subtitle: 'מעברים ואפקטים חלקים בין מסכים',
                icon: Icons.animation_outlined,
                value: _s.animationsEnabled,
                onChanged: (val) => setState(() => _s.animationsEnabled = val),
              ),
              _divider(),
              _rowSwitch(
                label: 'כפתור הגדרות מהירות',
                subtitle: 'כפתור צף לשינוי אופי/קול/שרת במהירות',
                icon: Icons.tune_rounded,
                value: _s.quickSettingsEnabled,
                onChanged: (val) => setState(() => _s.quickSettingsEnabled = val),
              ),
            ]),

            // ── האורב ────────────────────────────────────────────────────────
            _sectionHeader('האורב', Icons.blur_on_rounded),
            _card([
              _rowSwitch(
                label: 'צבעים מותאמים אישית',
                subtitle: 'השתמש בצבעים שלך במקום צבעי המצב האוטומטיים',
                icon: Icons.palette_outlined,
                value: _s.orbCustomColors,
                onChanged: (val) => setState(() => _s.orbCustomColors = val),
              ),
              if (_s.orbCustomColors) ...[
                _divider(),
                _orbColorRow(
                  label: 'צבע בסיס',
                  selected: _s.orbBaseColor,
                  onPick: (c) => setState(() => _s.orbBaseColor = c),
                ),
                _divider(),
                _orbColorRow(
                  label: 'צבע קצוות',
                  selected: _s.orbTipColor,
                  onPick: (c) => setState(() => _s.orbTipColor = c),
                ),
              ],
              _divider(),
              _rowSlider(
                label: 'רגישות קול',
                icon: Icons.graphic_eq_rounded,
                value: _s.orbVoiceSensitivity,
                min: 0.2,
                max: 2.5,
                divisions: 23,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setState(() => _s.orbVoiceSensitivity = v),
              ),
              _divider(),
              _rowSlider(
                label: 'רגישות סיבוב',
                icon: Icons.threesixty_rounded,
                value: _s.orbRotationSensitivity,
                min: 0.2,
                max: 2.5,
                divisions: 23,
                display: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setState(() => _s.orbRotationSensitivity = v),
              ),
              _divider(),
              _rowSwitch(
                label: 'פיצוץ בלחיצה',
                subtitle: 'פעימת אנרגיה כשנוגעים באורב',
                icon: Icons.auto_awesome_rounded,
                value: _s.orbExplosionEnabled,
                onChanged: (val) => setState(() => _s.orbExplosionEnabled = val),
              ),
            ]),

            // ── מסך היום ──────────────────────────────────────────────────────
            _sectionHeader('מסך היום', Icons.today_outlined),
            _card([
              _rowSwitch(
                label: 'בריפינג שבועי',
                subtitle: 'כרטיס סיכום שבועי מג׳רוויס בכרטיסיית היום',
                icon: Icons.insights_rounded,
                value: _s.todayBriefingEnabled,
                onChanged: (val) => setState(() => _s.todayBriefingEnabled = val),
              ),
              if (_s.todayBriefingEnabled) ...[
                _divider(),
                _rowField(
                  label: 'דגש לבריפינג',
                  icon: Icons.center_focus_strong_outlined,
                  ctrl: _briefingFocusCtrl,
                  hint: 'לדוגמה: עבודה, כושר',
                  textDir: TextDirection.rtl,
                ),
              ],
            ]),

            // ── זהות ─────────────────────────────────────────────────────────
            _sectionHeader('זהות', Icons.person_outline_rounded),
            _card([
              _rowField(
                label: 'השם שלך',
                icon: Icons.account_circle_outlined,
                ctrl: _userNameCtrl,
                hint: 'נדב',
                textDir: TextDirection.rtl,
              ),
              _divider(),
              _rowField(
                label: 'שם העוזר',
                icon: Icons.smart_toy_outlined,
                ctrl: _assistantNameCtrl,
                hint: 'Jarvis',
              ),
              _divider(),
              _rowDropdown<String>(
                label: 'מגדר',
                icon: Icons.person_outline_rounded,
                value: _s.gender,
                items: const [
                  DropdownMenuItem(value: 'male',   child: Text('זכר')),
                  DropdownMenuItem(value: 'female', child: Text('נקבה')),
                ],
                onChanged: (val) => setState(() => _s.gender = val!),
              ),
              _divider(),
              _rowDropdown<String>(
                label: 'אופי',
                icon: Icons.psychology_outlined,
                value: _s.personality,
                items: const [
                  DropdownMenuItem(value: 'friendly',  child: Text('ידידותי')),
                  DropdownMenuItem(value: 'formal',    child: Text('רשמי')),
                  DropdownMenuItem(value: 'concise',   child: Text('קצר ולעניין')),
                  DropdownMenuItem(value: 'humorous',  child: Text('הומוריסטי')),
                ],
                onChanged: (val) {
                  setState(() { _s.personality = val!; _personalityPreview = null; });
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton.icon(
                      onPressed: _personalityPreviewLoading ? null : _previewPersonality,
                      icon: _personalityPreviewLoading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_circle_outline, size: 16),
                      label: const Text('תצוגה מקדימה — שמע איך ג\'רוויס ידבר'),
                    ),
                    if (_personalityPreview != null)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JC.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: JC.blue400.withOpacity(0.4)),
                        ),
                        child: Text(
                          _personalityPreview!,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: JC.textPrimary, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ]),

            // ── קול ו-TTS ─────────────────────────────────────────────────────
            _sectionHeader('קול ו-TTS', Icons.record_voice_over_outlined),
            _card([
              _rowSwitch(
                label: 'הפעלת קול',
                subtitle: '${_s.assistantName} יקרא את התשובות בקול',
                icon: Icons.record_voice_over_outlined,
                value: _s.voiceEnabled,
                onChanged: (val) => setState(() => _s.voiceEnabled = val),
              ),
              if (_s.voiceEnabled) ...[
                _divider(),
                _rowSlider(
                  label: 'מהירות דיבור',
                  icon: Icons.speed_rounded,
                  value: _s.ttsSpeed,
                  min: 0.3,
                  max: 1.0,
                  divisions: 14,
                  display: (v) => '${(v * 100).round()}%',
                  onChanged: (v) => setState(() => _s.ttsSpeed = v),
                ),
                _divider(),
                _rowSlider(
                  label: 'גובה קול',
                  icon: Icons.graphic_eq_rounded,
                  value: _s.ttsPitch,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  display: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _s.ttsPitch = v),
                ),
                _divider(),
                _rowDropdown<String>(
                  label: 'שפת הקראה',
                  icon: Icons.language_rounded,
                  value: _s.ttsLanguage,
                  items: const [
                    DropdownMenuItem(value: 'he-IL', child: Text('עברית')),
                    DropdownMenuItem(value: 'en-US', child: Text('English')),
                  ],
                  onChanged: (val) => setState(() => _s.ttsLanguage = val!),
                ),
                if (_voiceNames.isNotEmpty) ...[
                  _divider(),
                  _rowDropdown<String>(
                    label: 'קול',
                    icon: Icons.spatial_audio_off_rounded,
                    value: _voiceNames.contains(_s.ttsVoiceName)
                        ? _s.ttsVoiceName
                        : '',
                    items: [
                      const DropdownMenuItem(value: '', child: Text('ברירת מחדל')),
                      ..._voiceNames.map((n) => DropdownMenuItem(
                            value: n,
                            child: Text(n, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (val) => setState(() => _s.ttsVoiceName = val ?? ''),
                  ),
                ],
                _divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: GestureDetector(
                    onTap: _previewTts,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: JC.blue500.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: JC.blue500.withValues(alpha: 0.4), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded, size: 17, color: JC.blue400),
                          const SizedBox(width: 8),
                          Text('השמע דוגמה',
                              style: TextStyle(
                                  color: JC.blue400, fontSize: 13,
                                  fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              _divider(),
              _rowSwitch(
                label: 'קטיעת דיבור (Barge-in)',
                subtitle: 'אפשר לדבר תוך כדי שג׳רביס מקריא',
                icon: Icons.interpreter_mode_outlined,
                value: _s.bargeInEnabled,
                onChanged: (val) => setState(() => _s.bargeInEnabled = val),
              ),
            ]),

            // ── שרת ──────────────────────────────────────────────────────────
            _sectionHeader('חיבור לשרת', Icons.dns_outlined),
            _card([
              _rowSwitch(
                label: 'שרת מקומי (LAN / ענן-מנהרה)',
                subtitle: _s.useLocalServer
                    ? 'מתחבר אל: ${_s.localServerUrl}'
                    : 'מחובר לשרת Render Cloud',
                icon: Icons.router_outlined,
                value: _s.useLocalServer,
                onChanged: (val) => setState(() => _s.useLocalServer = val),
              ),
              if (_s.useLocalServer) ...[
                _divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_outlined, size: 16, color: JC.textMuted),
                          const SizedBox(width: 8),
                          Text('בחר סוג שרת',
                              style: TextStyle(color: JC.textPrimary, fontSize: 14, fontFamily: 'Heebo')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_kPresets.length, (i) {
                          final p      = _kPresets[i];
                          final active = _selectedPreset == i;
                          return GestureDetector(
                            onTap: () => _selectPreset(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: active ? JC.blue500.withValues(alpha: 0.2) : JC.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: active ? JC.blue400 : JC.border,
                                  width: active ? 1.2 : 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(p.icon, size: 13,
                                      color: active ? JC.blue400 : JC.textMuted),
                                  const SizedBox(width: 6),
                                  Text(p.label,
                                      style: TextStyle(
                                        color: active ? JC.blue400 : JC.textSecondary,
                                        fontSize: 13,
                                        fontFamily: 'Heebo',
                                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                                      )),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                _divider(),
                _rowField(
                  label: 'כתובת',
                  icon: Icons.lan_outlined,
                  ctrl: _localServerUrlCtrl,
                  hint: 'http://192.168.1.x:3000',
                ),
                _divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pingServer,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: JC.blue500.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: JC.blue500.withValues(alpha: 0.4), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_find_outlined, size: 15, color: JC.blue400),
                              const SizedBox(width: 8),
                              Text('בדוק חיבור לשרת',
                                  style: TextStyle(
                                      color: JC.blue400,
                                      fontSize: 13,
                                      fontFamily: 'Heebo',
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      if (_pingResult != null) ...[
                        const SizedBox(height: 8),
                        Text(_pingResult!,
                            style: TextStyle(
                              color: _pingResult!.startsWith('✅') ? const Color(0xFF22C55E) :
                                     _pingResult!.startsWith('⚠️') ? const Color(0xFFF59E0B) :
                                     _pingResult! == '...'          ? JC.textMuted
                                                                     : const Color(0xFFEF4444),
                              fontSize: 12,
                              fontFamily: 'Heebo',
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ]),

            // ── מודל AI ──────────────────────────────────────────────────────
            _sectionHeader('מנוע AI (מי מייצר את התשובות)', Icons.memory_outlined),
            _card([
              _rowSwitch(
                label: 'מודל מקומי — Ollama',
                subtitle: _s.useLocalModel
                    ? 'מנוע: Ollama (דרך השרת)'
                    : 'מנוע: ספק ענן',
                icon: Icons.precision_manufacturing_outlined,
                value: _s.useLocalModel,
                onChanged: (val) => setState(() => _s.useLocalModel = val),
              ),
              if (_s.useLocalModel) ...[
                _divider(),
                _rowField(
                  label: 'שם מודל',
                  icon: Icons.dns_outlined,
                  ctrl: _localModelCtrl,
                  hint: 'llama3',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'במצב מקומי משתמשים אך ורק במודל שלך. אם הוא לא זמין — תוצג שגיאה (אין מעבר אוטומטי לענן).',
                    style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'),
                  ),
                ),
                _divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JC.blue500,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              LocalModelSetupScreen(settings: _s),
                        ),
                      );
                      if (result == true && mounted) {
                        setState(() {
                          _localServerUrlCtrl.text = _s.localServerUrl;
                          _localModelCtrl.text = _s.localModelName;
                        });
                      }
                    },
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('מדריך התקנה אינטראקטיבי',
                        style: TextStyle(fontFamily: 'Heebo')),
                  ),
                ),
              ] else ...[
                _divider(),
                _rowDropdown<String>(
                  label: 'ספק ענן',
                  icon: Icons.cloud_outlined,
                  value: _s.cloudProvider,
                  items: const [
                    DropdownMenuItem(value: 'groq',       child: Text('Groq')),
                    DropdownMenuItem(value: 'deepseek',   child: Text('DeepSeek')),
                    DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
                    DropdownMenuItem(value: 'gemini',     child: Text('Gemini')),
                  ],
                  onChanged: (val) => setState(() => _s.cloudProvider = val!),
                ),
                if (_s.cloudProvider == 'openrouter') ...[
                  _divider(),
                  _rowDropdown<String>(
                    label: 'מודל OpenRouter',
                    icon: Icons.memory_outlined,
                    value: _s.openrouterModel,
                    items: const [
                      DropdownMenuItem(
                        value: 'deepseek/deepseek-v4-flash:free',
                        child: Text('DeepSeek V4 Flash (free)'),
                      ),
                      DropdownMenuItem(
                        value: 'google/gemma-4-31b-it:free',
                        child: Text('Gemma 4 31B (free)'),
                      ),
                      DropdownMenuItem(
                        value: 'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
                        child: Text('Nemotron Nano Reasoning (free)'),
                      ),
                    ],
                    onChanged: (val) => setState(() => _s.openrouterModel = val!),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'הספק שתבחר ינוסה ראשון; אם הוא לא זמין, נמשיך אוטומטית לשאר כגיבוי.',
                    style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'),
                  ),
                ),
              ],
              _divider(),
              _rowSlider(
                label: 'יצירתיות',
                icon: Icons.auto_awesome_outlined,
                value: _s.temperature,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                display: (v) => v.toStringAsFixed(1),
                onChanged: (v) => setState(() => _s.temperature = v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  () {
                    final t = _s.temperature;
                    if (t <= 0.2) return '🎯 דטרמיניסטי — תשובות עקביות וצפויות';
                    if (t <= 0.5) return '⚖️ מאוזן — אמין עם מעט גיוון';
                    if (t <= 0.7) return '✨ יצירתי — מגוון עם שמירה על רלוונטיות';
                    return '🎲 חופשי — מפתיע, לפעמים בלתי צפוי';
                  }(),
                  style: TextStyle(
                    color: JC.textMuted,
                    fontSize: 12,
                    fontFamily: 'Heebo',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              _divider(),
              _rowDropdown<String>(
                label: 'אורך תשובה',
                icon: Icons.notes_rounded,
                value: _s.responseLength,
                items: const [
                  DropdownMenuItem(value: 'short',  child: Text('קצר')),
                  DropdownMenuItem(value: 'medium', child: Text('בינוני')),
                  DropdownMenuItem(value: 'long',   child: Text('ארוך')),
                ],
                onChanged: (val) => setState(() => _s.responseLength = val!),
              ),
            ]),

            // ── התראות ───────────────────────────────────────────────────────
            _sectionHeader('התראות', Icons.notifications_outlined),
            _card([
              _rowSwitch(
                label: 'התראות פעילות',
                subtitle: 'תזכורות, סיכומי בוקר ועדכונים',
                icon: Icons.notifications_active_outlined,
                value: _s.notificationsEnabled,
                onChanged: (val) => setState(() => _s.notificationsEnabled = val),
              ),
              if (_s.notificationsEnabled) ...[
                _divider(),
                _quietHourRow(
                  label: 'תחילת שעות שקט',
                  icon: Icons.bedtime_outlined,
                  hour: _s.quietHoursStart,
                  onPick: (h) => setState(() => _s.quietHoursStart = h),
                ),
                _divider(),
                _quietHourRow(
                  label: 'סיום שעות שקט',
                  icon: Icons.wb_sunny_outlined,
                  hour: _s.quietHoursEnd,
                  onPick: (h) => setState(() => _s.quietHoursEnd = h),
                ),
              ],
            ]),

            // ── הרשאות ───────────────────────────────────────────────────────
            _sectionHeader('הרשאות', Icons.security_outlined),
            _card([
              _permRow(
                label: 'מיקרופון',
                description: 'נדרש לשיחות קוליות ו-Whisper STT',
                rowIcon: Icons.mic_outlined,
                status: _micStatus,
                permission: Permission.microphone,
              ),
              _divider(),
              _permRow(
                label: 'התראות',
                description: 'נדרש לתזכורות ועדכונים',
                rowIcon: Icons.notifications_outlined,
                status: _notifStatus,
                permission: Permission.notification,
              ),
              _divider(),
              _permRow(
                label: 'מצלמה',
                description: 'נדרש לצילום תמונות לשליחה לג\'רביס',
                rowIcon: Icons.camera_alt_outlined,
                status: _cameraStatus,
                permission: Permission.camera,
              ),
              _divider(),
              _permRow(
                label: 'גלריה / תמונות',
                description: 'נדרש לבחירת תמונות קיימות',
                rowIcon: Icons.photo_library_outlined,
                status: _photosStatus,
                permission: Permission.photos,
              ),
              _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: GestureDetector(
                  onTap: _loadPermissions,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, size: 14, color: JC.textMuted),
                      SizedBox(width: 6),
                      Text('רענן סטטוס הרשאות',
                          style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
                    ],
                  ),
                ),
              ),
            ]),

            // ── פרויקט ───────────────────────────────────────────────────────
            _sectionHeader('פרויקט', Icons.map_outlined),
            _card([
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.map_outlined, color: JC.textMuted, size: 20),
                title: Text('מפת התקדמות',
                    style: TextStyle(color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
                subtitle: Text('יכולות, הערות ודיאגרמת זרימה',
                    style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
                trailing: Icon(Icons.open_in_new_rounded, color: JC.textMuted, size: 18),
                onTap: _openProgressMap,
              ),
              _divider(),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.sync_rounded, color: JC.textMuted, size: 20),
                title: Text('סנכרן עם Obsidian',
                    style: TextStyle(color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
                subtitle: Text(
                  _obsidianSyncStatus ?? 'סנכרון הערות, זיכרונות ומשימות',
                  style: TextStyle(
                    color: _obsidianSyncStatus == null
                        ? JC.textMuted
                        : _obsidianSyncStatus!.startsWith('✅') ? const Color(0xFF22C55E)
                        : _obsidianSyncStatus!.startsWith('⚠️') ? const Color(0xFFF59E0B)
                        : _obsidianSyncStatus!.startsWith('❌') ? const Color(0xFFEF4444)
                        : JC.textMuted,
                    fontSize: 12,
                    fontFamily: 'Heebo',
                  ),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: JC.textMuted, size: 18),
                onTap: _syncObsidian,
              ),
              _divider(),
              _rowSwitch(
                label: 'סנכרון אוטומטי',
                subtitle: 'מסנכרן כל 5 דקות עם ה-vault',
                icon: Icons.sync_lock_outlined,
                value: _s.obsidianAutoSync,
                onChanged: _setObsidianAutoSync,
              ),
            ]),



            _sectionHeader('פרטיות ו-Telemetry', Icons.privacy_tip_outlined),
            _card([
              _rowSwitch(
                label: 'איסוף Telemetry אנונימי',
                subtitle: 'נאספים רק מונים/סטטוסים ללא טקסט חופשי',
                icon: Icons.analytics_outlined,
                value: _s.telemetryConsent,
                onChanged: (val) => setState(() => _s.telemetryConsent = val),
              ),
              _divider(),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 20),
                title: Text('איפוס למידה / Telemetry', style: TextStyle(color: JC.textPrimary, fontSize: 15, fontFamily: 'Heebo')),
                subtitle: Text('מחיקת אירועים שנשמרו עבור המשתמש הזה', style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
                trailing: Icon(Icons.chevron_right_rounded, color: JC.textMuted, size: 18),
                onTap: _resetTelemetry,
              ),
            ]),

            // ── Save button ───────────────────────────────────────────────────
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _save,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [JC.blue400, JC.blue500],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: JC.blue500.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'שמור שינויים',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}
