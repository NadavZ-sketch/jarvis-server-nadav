import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'theme/jarvis_theme.dart';

class AppSettings {
  String assistantName;
  String gender;       // 'male' | 'female'
  String personality;  // 'friendly' | 'formal' | 'concise' | 'humorous'
  bool voiceEnabled;
  String userName;
  bool useLocalModel;   // true = Ollama, false = Groq/DeepSeek/Gemini
  bool useLocalServer;  // true = local server, false = Render cloud
  String localServerUrl;
bool obsidianAutoSync;
  bool telemetryConsent;
  bool bargeInEnabled;

  // ── Appearance ──
  AppTheme selectedTheme;
  AppBrightnessMode brightnessMode; // light / dark / system (independent of theme)
  bool animationsEnabled;
  bool quickSettingsEnabled; // show the floating quick-settings button

  // ── Orb ──
  bool orbCustomColors;        // use orbBaseColor/orbTipColor instead of per-state
  int orbBaseColor;            // ARGB int — strand root color
  int orbTipColor;             // ARGB int — strand tip color
  double orbVoiceSensitivity;  // 0.2 – 2.5; how strongly strands react to voice
  double orbRotationSensitivity; // 0.2 – 2.5; drag-rotation speed multiplier
  bool orbExplosionEnabled;    // tap → explosion pulse

  // ── Today tab ──
  bool todayBriefingEnabled;   // show the weekly briefing card in the Today tab
  String todayBriefingFocus;   // optional focus the briefing should emphasise

  // ── Environment ──
  String city; // city used for the home-screen weather (Open-Meteo geocoding)

  // ── Voice / TTS ──
  double ttsSpeed;     // 0.3 – 1.0 (flutter_tts speech rate)
  double ttsPitch;     // 0.5 – 2.0
  String ttsLanguage;  // 'he-IL' | 'en-US'
  String ttsVoiceName; // platform voice name, '' = default

  // ── AI / model ──
  String cloudProvider; // 'groq' | 'deepseek' | 'openrouter' | 'gemini'
  String openrouterModel; // model id to pass when cloudProvider == 'openrouter'
  String localModelName;
  double temperature;   // 0.0 – 1.0
  String responseLength; // 'short' | 'medium' | 'long'
  bool saverMode;        // token-saver: forces short replies + low temperature server-side

  // ── Notifications ──
  bool notificationsEnabled;
  int quietHoursStart; // hour 0-23
  int quietHoursEnd;   // hour 0-23

  // ── Home screen layout ──
  List<String> homeCardOrder;   // ordered card ids; empty = registry default
  Set<String> homeCardsHidden;  // card ids the user hid

  // ── Tasks screen ──
  String tasksDefaultView; // 'list' | 'eisenhower' | 'kanban' | 'day_plan'

  static const String cloudServerUrl = 'https://jarvis-server-nadav.onrender.com';

  String get serverUrl => useLocalServer ? localServerUrl : cloudServerUrl;

  AppSettings({
    this.assistantName = 'Jarvis',
    this.gender = 'male',
    this.personality = 'friendly',
    this.voiceEnabled = true,
    this.userName = 'נדב',
    this.useLocalModel = false,
    this.useLocalServer = false,
    this.localServerUrl = 'http://192.168.1.100:3000',
    this.obsidianAutoSync = true,
    this.telemetryConsent = false,
    this.bargeInEnabled = true,
    this.selectedTheme = AppTheme.navyDark,
    this.brightnessMode = AppBrightnessMode.dark,
    this.animationsEnabled = true,
    this.quickSettingsEnabled = false,
    this.orbCustomColors = false,
    this.orbBaseColor = 0xFF666666,
    this.orbTipColor = 0xFFFFFFFF,
    this.orbVoiceSensitivity = 1.0,
    this.orbRotationSensitivity = 1.0,
    this.orbExplosionEnabled = true,
    this.todayBriefingEnabled = true,
    this.todayBriefingFocus = '',
    this.city = 'תל אביב',
    this.ttsSpeed = 0.7,
    this.ttsPitch = 1.0,
    this.ttsLanguage = 'he-IL',
    this.ttsVoiceName = '',
    this.cloudProvider = 'groq',
    this.openrouterModel = 'meta-llama/llama-3.3-70b-instruct:free',
    this.localModelName = 'gemma4:e4b',
    this.temperature = 0.7,
    this.responseLength = 'medium',
    this.saverMode = false,
    this.notificationsEnabled = true,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 8,
    List<String>? homeCardOrder,
    Set<String>? homeCardsHidden,
    this.tasksDefaultView = 'list',
  })  : homeCardOrder = homeCardOrder ?? [],
        homeCardsHidden = homeCardsHidden ?? {};

  static AppTheme _parseTheme(String? name) {
    if (name == null) return AppTheme.navyDark;
    for (final t in AppTheme.values) {
      if (t.name == name) return t;
    }
    return AppTheme.navyDark;
  }

  static AppBrightnessMode _parseBrightnessMode(String? name) {
    if (name == null) return AppBrightnessMode.dark;
    for (final m in AppBrightnessMode.values) {
      if (m.name == name) return m;
    }
    return AppBrightnessMode.dark;
  }

  // Fetch the raw server profile (best-effort, used on fresh install) so identity
  // fields AND portable preferences can be recovered after a reinstall / device
  // switch. Returns the `profile` object as-is (snake_case identity columns plus a
  // `preferences` JSONB blob), or null on any failure.
  static Future<Map<String, dynamic>?> _fetchServerProfile(String serverUrl) async {
    try {
      final res = await http
          .get(Uri.parse('$serverUrl/user-profile'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['profile'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    // On a fresh install none of the identity keys exist in SharedPreferences.
    // In that case, try to recover them from the server profile so the user
    // doesn't have to re-enter their name/personality after switching devices.
    final isFirstLoad = prefs.getString('userName') == null;
    Map<String, dynamic>? serverProfile;
    if (isFirstLoad) {
      final useLocal = prefs.getBool('useLocalServer') ?? false;
      final localUrl = prefs.getString('localServerUrl') ?? 'http://192.168.1.100:3000';
      const cloudUrl = cloudServerUrl;
      serverProfile = await _fetchServerProfile(useLocal ? localUrl : cloudUrl);
    }
    String? _ident(String key) =>
        (serverProfile != null && serverProfile[key] is String) ? serverProfile[key] as String : null;

    final s = AppSettings(
      assistantName:    prefs.getString('assistantName')    ?? _ident('assistant_name') ?? 'Jarvis',
      gender:           prefs.getString('gender')           ?? _ident('gender')         ?? 'male',
      personality:      prefs.getString('personality')      ?? _ident('personality')    ?? 'friendly',
      voiceEnabled:     prefs.getBool('voiceEnabled')       ?? true,
      userName:         prefs.getString('userName')         ?? _ident('user_name')      ?? 'נדב',
      useLocalModel:    prefs.getBool('useLocalModel')      ?? false,
      useLocalServer:   prefs.getBool('useLocalServer')     ?? false,
      localServerUrl:   prefs.getString('localServerUrl')   ?? 'http://192.168.1.100:3000',
      obsidianAutoSync: prefs.getBool('obsidianAutoSync')   ?? true,
      telemetryConsent: prefs.getBool('telemetryConsent')   ?? false,
      bargeInEnabled:   prefs.getBool('bargeInEnabled')     ?? true,
      selectedTheme:    _parseTheme(prefs.getString('selectedTheme')),
      brightnessMode:   _parseBrightnessMode(prefs.getString('brightnessMode')),
      animationsEnabled: prefs.getBool('animationsEnabled') ?? true,
      quickSettingsEnabled: prefs.getBool('quickSettingsEnabled') ?? false,
      orbCustomColors:  prefs.getBool('orbCustomColors')    ?? false,
      orbBaseColor:     prefs.getInt('orbBaseColor')        ?? 0xFF666666,
      orbTipColor:      prefs.getInt('orbTipColor')         ?? 0xFFFFFFFF,
      orbVoiceSensitivity:    prefs.getDouble('orbVoiceSensitivity')    ?? 1.0,
      orbRotationSensitivity: prefs.getDouble('orbRotationSensitivity') ?? 1.0,
      orbExplosionEnabled: prefs.getBool('orbExplosionEnabled') ?? true,
      todayBriefingEnabled: prefs.getBool('todayBriefingEnabled') ?? true,
      todayBriefingFocus:  prefs.getString('todayBriefingFocus') ?? '',
      city:             prefs.getString('city')             ?? 'תל אביב',
      ttsSpeed:         prefs.getDouble('ttsSpeed')         ?? 0.7,
      ttsPitch:         prefs.getDouble('ttsPitch')         ?? 1.0,
      ttsLanguage:      prefs.getString('ttsLanguage')      ?? 'he-IL',
      ttsVoiceName:     prefs.getString('ttsVoiceName')     ?? '',
      cloudProvider:    prefs.getString('cloudProvider')    ?? 'groq',
      openrouterModel:  prefs.getString('openrouterModel')  ?? 'meta-llama/llama-3.3-70b-instruct:free',
      localModelName:   prefs.getString('localModelName')   ?? 'gemma4:e4b',
      temperature:      prefs.getDouble('temperature')      ?? 0.7,
      responseLength:   prefs.getString('responseLength')   ?? 'medium',
      saverMode:        prefs.getBool('saverMode')          ?? false,
      notificationsEnabled: prefs.getBool('notificationsEnabled') ?? true,
      quietHoursStart:  prefs.getInt('quietHoursStart')     ?? 22,
      quietHoursEnd:    prefs.getInt('quietHoursEnd')       ?? 8,
      homeCardOrder:    prefs.getStringList('homeCardOrder') ?? [],
      homeCardsHidden:  (prefs.getStringList('homeCardsHidden') ?? []).toSet(),
      tasksDefaultView: prefs.getString('tasksDefaultView') ?? 'list',
    );

    // Fresh install: fill in portable preferences from the server profile, then
    // persist so SharedPreferences becomes the source of truth from here on.
    if (isFirstLoad && serverProfile != null && serverProfile['preferences'] is Map) {
      s.applyPreferences(Map<String, dynamic>.from(serverProfile['preferences'] as Map));
      await s.save();
    }

    return s;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('assistantName',  assistantName);
    await prefs.setString('gender',         gender);
    await prefs.setString('personality',    personality);
    await prefs.setBool('voiceEnabled',     voiceEnabled);
    await prefs.setString('userName',       userName);
    await prefs.setBool('useLocalModel',    useLocalModel);
    await prefs.setBool('useLocalServer',   useLocalServer);
    await prefs.setString('localServerUrl', localServerUrl);
    await prefs.setBool('obsidianAutoSync', obsidianAutoSync);
    await prefs.setBool('telemetryConsent', telemetryConsent);
    await prefs.setBool('bargeInEnabled',   bargeInEnabled);
    await prefs.setString('selectedTheme',  selectedTheme.name);
    await prefs.setString('brightnessMode', brightnessMode.name);
    await prefs.setBool('animationsEnabled', animationsEnabled);
    await prefs.setBool('quickSettingsEnabled', quickSettingsEnabled);
    await prefs.setBool('orbCustomColors',   orbCustomColors);
    await prefs.setInt('orbBaseColor',       orbBaseColor);
    await prefs.setInt('orbTipColor',        orbTipColor);
    await prefs.setDouble('orbVoiceSensitivity',    orbVoiceSensitivity);
    await prefs.setDouble('orbRotationSensitivity', orbRotationSensitivity);
    await prefs.setBool('orbExplosionEnabled', orbExplosionEnabled);
    await prefs.setBool('todayBriefingEnabled', todayBriefingEnabled);
    await prefs.setString('todayBriefingFocus', todayBriefingFocus);
    await prefs.setString('city', city);
    await prefs.setDouble('ttsSpeed',       ttsSpeed);
    await prefs.setDouble('ttsPitch',       ttsPitch);
    await prefs.setString('ttsLanguage',    ttsLanguage);
    await prefs.setString('ttsVoiceName',   ttsVoiceName);
    await prefs.setString('cloudProvider',  cloudProvider);
    await prefs.setString('openrouterModel', openrouterModel);
    await prefs.setString('localModelName', localModelName);
    await prefs.setDouble('temperature',    temperature);
    await prefs.setString('responseLength', responseLength);
    await prefs.setBool('saverMode',        saverMode);
    await prefs.setBool('notificationsEnabled', notificationsEnabled);
    await prefs.setInt('quietHoursStart',   quietHoursStart);
    await prefs.setInt('quietHoursEnd',     quietHoursEnd);
    await prefs.setStringList('homeCardOrder',  homeCardOrder);
    await prefs.setStringList('homeCardsHidden', homeCardsHidden.toList());
    await prefs.setString('tasksDefaultView', tasksDefaultView);
  }

  // Returns true if [hour] (0-23) falls inside the quiet window.
  // Handles overnight spans: start=22, end=8 → quiet from 22:00 to 07:59.
  bool isInQuietHours([int? hour]) {
    if (!notificationsEnabled) return false;
    final h = hour ?? DateTime.now().hour;
    if (quietHoursStart <= quietHoursEnd) {
      return h >= quietHoursStart && h < quietHoursEnd;
    }
    // Overnight: e.g. start=22, end=8 → quiet if h>=22 OR h<8
    return h >= quietHoursStart || h < quietHoursEnd;
  }

  Map<String, dynamic> toJson() => {
    'assistantName':  assistantName,
    'gender':         gender,
    'personality':    personality,
    'userName':       userName,
    'useLocalModel':  useLocalModel,
    'useLocalServer': useLocalServer,
    'ttsEnabled':     voiceEnabled,   // server checks settings.ttsEnabled
    'telemetryConsent': telemetryConsent,
    'cloudProvider':   cloudProvider,
    'openrouterModel': openrouterModel,
    'localModelName':  localModelName,
    'temperature':    temperature,
    'responseLength': responseLength,
    'saverMode':      saverMode,
  };

  // ── Portable preferences (synced to the server `preferences` JSONB column) ──
  // CANONICAL KEY LIST — must stay identical to the server-side merge in
  // POST /user-profile and the settings blob in progress-map.html. Enums are
  // serialised via .name so the web <select> values match.
  Map<String, dynamic> toPreferences() => {
    // AI / model
    'cloudProvider':   cloudProvider,
    'useLocalModel':   useLocalModel,
    'localModelName':  localModelName,
    'openrouterModel': openrouterModel,
    'temperature':     temperature,
    'responseLength':  responseLength,
    'saverMode':       saverMode,
    // Voice / TTS
    'voiceEnabled':    voiceEnabled,
    'ttsSpeed':        ttsSpeed,
    'ttsPitch':        ttsPitch,
    'ttsLanguage':     ttsLanguage,
    'ttsVoiceName':    ttsVoiceName,
    'bargeInEnabled':  bargeInEnabled,
    // Appearance
    'selectedTheme':   selectedTheme.name,
    'brightnessMode':  brightnessMode.name,
    'animationsEnabled': animationsEnabled,
    // Today tab
    'todayBriefingEnabled': todayBriefingEnabled,
    'todayBriefingFocus':   todayBriefingFocus,
    'city':            city,
    // Notifications
    'notificationsEnabled': notificationsEnabled,
    'quietHoursStart': quietHoursStart,
    'quietHoursEnd':   quietHoursEnd,
    // Advanced
    'telemetryConsent': telemetryConsent,
    'obsidianAutoSync': obsidianAutoSync,
  };

  // Apply a (partial) preferences blob fetched from the server. Each key is
  // guarded + falls back to the current value, mirroring load()'s defaults.
  void applyPreferences(Map<String, dynamic> p) {
    T pick<T>(String key, T current) => p[key] is T ? p[key] as T : current;
    // AI / model
    cloudProvider   = pick('cloudProvider', cloudProvider);
    useLocalModel   = pick('useLocalModel', useLocalModel);
    localModelName  = pick('localModelName', localModelName);
    openrouterModel = pick('openrouterModel', openrouterModel);
    temperature     = (p['temperature'] is num) ? (p['temperature'] as num).toDouble() : temperature;
    responseLength  = pick('responseLength', responseLength);
    saverMode       = pick('saverMode', saverMode);
    // Voice / TTS
    voiceEnabled    = pick('voiceEnabled', voiceEnabled);
    ttsSpeed        = (p['ttsSpeed'] is num) ? (p['ttsSpeed'] as num).toDouble() : ttsSpeed;
    ttsPitch        = (p['ttsPitch'] is num) ? (p['ttsPitch'] as num).toDouble() : ttsPitch;
    ttsLanguage     = pick('ttsLanguage', ttsLanguage);
    ttsVoiceName    = pick('ttsVoiceName', ttsVoiceName);
    bargeInEnabled  = pick('bargeInEnabled', bargeInEnabled);
    // Appearance
    if (p['selectedTheme'] is String) selectedTheme = _parseTheme(p['selectedTheme'] as String);
    if (p['brightnessMode'] is String) brightnessMode = _parseBrightnessMode(p['brightnessMode'] as String);
    animationsEnabled = pick('animationsEnabled', animationsEnabled);
    // Today tab
    todayBriefingEnabled = pick('todayBriefingEnabled', todayBriefingEnabled);
    todayBriefingFocus   = pick('todayBriefingFocus', todayBriefingFocus);
    city            = pick('city', city);
    // Notifications
    notificationsEnabled = pick('notificationsEnabled', notificationsEnabled);
    quietHoursStart = (p['quietHoursStart'] is num) ? (p['quietHoursStart'] as num).toInt() : quietHoursStart;
    quietHoursEnd   = (p['quietHoursEnd'] is num) ? (p['quietHoursEnd'] as num).toInt() : quietHoursEnd;
    // Advanced
    telemetryConsent = pick('telemetryConsent', telemetryConsent);
    obsidianAutoSync = pick('obsidianAutoSync', obsidianAutoSync);
  }
}
