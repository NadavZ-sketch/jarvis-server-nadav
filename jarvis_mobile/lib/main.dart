import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'app_settings.dart';
import 'theme/jarvis_theme.dart';
import 'theme/theme_notifier.dart';
import 'widgets/markdown_lite.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'live_talk_screen.dart';
import 'transitions/slide_fade_route.dart';
import 'screens/splash_screen.dart';
import 'screens/survey_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const JarvisApp());
}

// ─── Design Tokens ────────────────────────────────────────────────────────────
// `JC` is a runtime-swappable palette shim. Call [JC.apply] when the selected
// theme changes; every getter reads from the active [JarvisColorScheme] so the
// whole UI recolors on the next rebuild.
class JC {
  static JarvisColorScheme _scheme = JarvisColorScheme.navyDark;
  static AppTheme _theme = AppTheme.navyDark;

  static void apply(AppTheme t) {
    _theme = t;
    _scheme = JarvisThemeData.schemeFor(t);
  }

  static AppTheme get theme => _theme;
  static JarvisColorScheme get scheme => _scheme;

  // Backgrounds
  static Color get bg         => _scheme.bg;
  static Color get surface    => _scheme.surface;
  static Color get surfaceAlt => _scheme.surfaceAlt;
  static Color get border     => _scheme.border;

  // Blue / accent palette
  static Color get blue500 => _scheme.blue500;
  static Color get blue400 => _scheme.blue400;
  static Color get blue300 => _scheme.blue300;

  // Text
  static Color get textPrimary   => _scheme.textPrimary;
  static Color get textSecondary => _scheme.textSecondary;
  static Color get textMuted     => _scheme.textMuted;

  // Bubbles
  static Color get userBubble   => _scheme.userBubble;
  static Color get jarvisBubble => _scheme.jarvisBubble;

  // Actions
  static Color get cancelRed => _scheme.cancelRed;
  static Color get indigo500 => _scheme.indigo500;
  static Color get indigo300 => _scheme.indigo300;

  // Priority colors
  static Color get amber400 => _scheme.amber400;
  static Color get green500 => _scheme.green500;

  // Theme-specific extras
  static Color get accentPrimary  => _scheme.accentPrimary;
  static Color get glassOverlay   => _scheme.glassOverlay;
  static Color get neoShadowLight => _scheme.neoShadowLight;
  static Color get neoShadowDark  => _scheme.neoShadowDark;
}

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  final ValueNotifier<AppTheme> _themeNotifier =
      ValueNotifier<AppTheme>(AppTheme.navyDark);

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((s) {
      JC.apply(s.selectedTheme);
      _themeNotifier.value = s.selectedTheme;
    });
  }

  @override
  void dispose() {
    _themeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeNotifier(
      notifier: _themeNotifier,
      child: ValueListenableBuilder<AppTheme>(
        valueListenable: _themeNotifier,
        builder: (context, theme, _) {
          JC.apply(theme);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'ג׳רביס',
            locale: const Locale('he', 'IL'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('he', 'IL')],
            theme: JarvisThemeData.themeDataFor(theme),
            home: const SplashScreen(),
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}

enum JarvisState { idle, listening, thinking, speaking }

// ─── Typing Dots ──────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480),
    ));
    _anims = _controllers.map((c) =>
      Tween<double>(begin: 0, end: -6).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      )
    ).toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) => AnimatedBuilder(
        animation: _anims[i],
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _anims[i].value),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: JC.blue400.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
          ),
        ),
      )),
    );
  }
}

// ─── Jarvis Orb ───────────────────────────────────────────────────────────────
class _JarvisOrb extends StatelessWidget {
  final JarvisState state;
  final Animation<double> breathAnim;

  const _JarvisOrb({required this.state, required this.breathAnim});

  Color get _glow {
    switch (state) {
      case JarvisState.listening: return const Color(0xFF93C5FD);
      case JarvisState.thinking:  return const Color(0xFF818CF8);
      case JarvisState.speaking:  return const Color(0xFF22D3EE);
      default:                    return JC.blue500;
    }
  }

  List<Color> get _gradient {
    switch (state) {
      case JarvisState.listening: return [const Color(0xFFBAE6FD), JC.blue400];
      case JarvisState.thinking:  return [const Color(0xFFA78BFA), const Color(0xFF4338CA)];
      case JarvisState.speaking:  return [const Color(0xFF67E8F9), const Color(0xFF0E7490)];
      default:                    return [JC.blue400, const Color(0xFF1E3A8A)];
    }
  }

  double get _size {
    switch (state) {
      case JarvisState.thinking: return 100.0;
      case JarvisState.speaking: return 96.0;
      default: return 114.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breathAnim,
      builder: (_, __) => Transform.scale(
        scale: state == JarvisState.idle ? breathAnim.value : 1.0,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer ambient ring
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              width:  _size + 52,
              height: _size + 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _glow.withValues(alpha: 0.06),
              ),
            ),
            // Mid glow ring
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              width:  _size + 28,
              height: _size + 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _glow.withValues(alpha: 0.13),
              ),
            ),
            // Core orb
            AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              width:  _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: _gradient,
                  center: const Alignment(-0.25, -0.3),
                  radius: 0.85,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _glow.withValues(alpha: 0.55),
                    blurRadius: 24,
                    spreadRadius: state == JarvisState.idle ? 1 : 6,
                  ),
                  BoxShadow(
                    color: _glow.withValues(alpha: 0.2),
                    blurRadius: 56,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),
            // Orb inner specular highlight
            Positioned(
              top: (_size + 52) / 2 - _size / 2 + 12,
              left: (_size + 52) / 2 - _size / 2 + 14,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width:  _size * 0.28,
                height: _size * 0.18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Chat Bubble ─────────────────────────────────────────────────────────────
class _ChatBubble extends StatefulWidget {
  final Map<String, String> msg;
  final int index;
  final ValueChanged<String>? onSpeak;
  final void Function(String target)? onNavigate;

  const _ChatBubble({
    required this.msg,
    required this.index,
    this.onSpeak,
    this.onNavigate,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _showTime = false;

  void _showCopyMenu(String text) {
    final isJarvis = widget.msg['sender'] != 'user';
    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuAction(
              icon: Icons.copy_rounded,
              label: 'העתקה',
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('הודעה הועתקה'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: JC.blue500,
                  ),
                );
              },
            ),
            if (isJarvis && widget.onSpeak != null)
              _menuAction(
                icon: Icons.volume_up_rounded,
                label: 'הקרא שוב',
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onSpeak!(text);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: JC.textPrimary, size: 22),
              const SizedBox(width: 16),
              Text(label,
                  style: TextStyle(
                      fontSize: 16, color: JC.textPrimary, fontFamily: 'Heebo')),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isUser = widget.msg['sender'] == 'user';

    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.index),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => setState(() => _showTime = !_showTime),
          onLongPress: () => _showCopyMenu(widget.msg['text'] ?? ''),
          child: _bubbleSurface(isUser: isUser, child: _bubbleContent(isUser)),
        ),
      ),
    );
  }

  Widget _bubbleContent(bool isUser) => Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          MarkdownLite(
            text: widget.msg['text']!,
            textDirection: TextDirection.rtl,
            baseStyle: TextStyle(
              fontSize: 15,
              color: JC.textPrimary,
              height: 1.6,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w400,
            ),
          ),
          if (!isUser && widget.msg['navTarget'] != null) ...[
            const SizedBox(height: 10),
            _navButton(widget.msg['navTarget']!, widget.msg['navLabel'] ?? 'פתח'),
          ],
          if (_showTime) ...[
            const SizedBox(height: 6),
            Text(
              widget.msg['time'] ?? '',
              style: TextStyle(
                fontSize: 11,
                color: JC.textMuted.withValues(alpha: 0.8),
                fontFamily: 'Heebo',
              ),
            ),
          ],
        ],
      );

  Widget _navButton(String target, String label) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onNavigate?.call(target),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: JC.blue500.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: JC.blue400.withValues(alpha: 0.5), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded,
                      size: 16, color: JC.blue400),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: JC.blue400,
                      fontFamily: 'Heebo',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _bubbleSurface({required bool isUser, required Widget child}) {
    final scheme = JC.scheme;
    final margin = EdgeInsets.only(
      bottom: 14,
      right: isUser ? 0 : 48,
      left: isUser ? 48 : 0,
    );
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isUser ? 20 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 20),
    );
    final borderColor = isUser
        ? JC.blue400.withValues(alpha: 0.5)
        : (scheme.isCyber ? JC.blue400.withValues(alpha: 0.4)
                          : JC.border.withValues(alpha: 0.7));
    final baseColor = isUser ? JC.userBubble : JC.jarvisBubble;

    if (scheme.usesGlass) {
      return Container(
        margin: margin,
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: baseColor.withValues(alpha: 0.5),
                borderRadius: radius,
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: isUser
                ? JC.blue400.withValues(alpha: scheme.isCyber ? 0.18 : 0.1)
                : (scheme.isCyber ? JC.blue400.withValues(alpha: 0.08) : Colors.transparent),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Chat Screen ──────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final AppSettings? initialSettings;
  final ValueChanged<AppSettings>? onSettingsChanged;
  final VoidCallback? onOpenDrawer;
  final String? pendingCommand;
  final VoidCallback? onCommandConsumed;
  final VoidCallback? onBeforeUnfocus;
  final void Function(Future<void> Function())? onRegisterArchive;
  final void Function(String target)? onNavigate;

  const ChatScreen({
    super.key,
    this.initialSettings,
    this.onSettingsChanged,
    this.onOpenDrawer,
    this.pendingCommand,
    this.onCommandConsumed,
    this.onBeforeUnfocus,
    this.onRegisterArchive,
    this.onNavigate,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller       = TextEditingController();
  final ScrollController       _scrollController = ScrollController();

  late stt.SpeechToText _speech;
  final AudioPlayer  _audioPlayer = AudioPlayer();
  final FlutterTts   _flutterTts  = FlutterTts();
  final ImagePicker  _picker      = ImagePicker();

  JarvisState _currentState = JarvisState.idle;
  String      _listeningText = '';
  bool        _voiceConversationMode = false; // one-shot mic dictation toggle

  Timer? _ttsTimeoutTimer;
  String? _lastTtsPath;

  // Background-job poll: used when the server is running a long task asynchronously
  Timer? _bgPollTimer;
  int    _bgPollAttempts = 0;
  int    _bgPollBaseline = 0; // message count at poll start
  static const int _bgPollMaxAttempts = 12; // 12 × 15s = 3 minutes

  String? _currentProposalTitle;

  Uint8List? _imageBytes;
  String?    _base64Image;

  AppSettings _settings = AppSettings();
  String _chatId = ''; // Unique ID for this chat session

  // Survey tracking
  DateTime? _sessionStartTime;
  int _agentCallCount = 0;
  bool _surveyShownThisSession = false;
  // When eligible, the survey surfaces as a dismissible banner above the input
  // (never a blocking modal) so it can't interrupt an active conversation.
  List<Map<String, dynamic>>? _pendingSurveyQuestions;

  late AnimationController _orbBreathController;
  late Animation<double>   _orbBreath;

  bool _showOrbAndHint = true;
  bool _showScrollToBottom = false;

  String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  late List<Map<String, String>> messages = [
    {'sender': 'jarvis', 'text': 'מערכת מחוברת. מוכן לעזור, ${_settings.userName}.', 'time': _getCurrentTime()}
  ];

  @override
  void initState() {
    super.initState();
    widget.onRegisterArchive?.call(() => archiveCurrentSession());
    _speech = stt.SpeechToText();
    _initTts();

    if (widget.initialSettings != null) {
      _settings = widget.initialSettings!;
      _loadChatHistory();
    } else {
      AppSettings.load().then((s) {
        if (!mounted) return;
        setState(() => _settings = s);
        _loadChatHistory();
      });
    }

    _orbBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);
    _orbBreath = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _orbBreathController, curve: Curves.easeInOut),
    );

    _scrollController.addListener(_onScroll);
    _audioPlayer.onPlayerComplete.listen((_) {
      if (_lastTtsPath != null) {
        File(_lastTtsPath!).delete().catchError((_) {});
        _lastTtsPath = null;
      }
      if (!mounted) return;
      setState(() => _currentState = JarvisState.idle);
    });
    NotificationService.init().catchError((_) {});

    // Track session start for survey
    _sessionStartTime = DateTime.now();
    _agentCallCount = 0;
    _surveyShownThisSession = false;
  }

  void _onScroll() {
    final pos = _scrollController.position;
    final showOrb    = pos.pixels < 100;
    final showBottom = (pos.maxScrollExtent - pos.pixels) > 200 && messages.length > 3;
    if (showOrb == _showOrbAndHint && showBottom == _showScrollToBottom) return;
    setState(() {
      _showOrbAndHint     = showOrb;
      _showScrollToBottom = showBottom;
    });
  }


  // ─── Chat history persistence ─────────────────────────────────────────────────

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();

    // Load or generate chat_id
    final saved = prefs.getString('current_chat_id');
    if (saved != null && saved.isNotEmpty) {
      _chatId = saved;
    } else {
      _chatId = 'chat-${DateTime.now().millisecondsSinceEpoch}-${(math.Random().nextInt(100000)).toString()}';
      await prefs.setString('current_chat_id', _chatId);
    }

    print('📂 Loading chat history for: $_chatId');

    // 1. Load cached messages from SharedPreferences immediately (instant)
    final cached = prefs.getString('current_messages');
    if (cached != null && cached.isNotEmpty && mounted) {
      try {
        final List decoded = jsonDecode(cached);
        final loaded = decoded.cast<Map<String, dynamic>>()
            .map((m) => m.map((k, v) => MapEntry(k, v.toString())))
            .toList();
        if (loaded.isNotEmpty) {
          setState(() => messages = loaded);
        }
      } catch (_) {}
    }

    // 2. Fetch fresh history from server in the background
    try {
      final url = Uri.parse('${_settings.serverUrl}/chat-history?limit=60&chatId=$_chatId');
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final List raw = data['messages'] ?? [];
        print('📥 Server returned ${raw.length} messages for chatId: $_chatId');

        if (raw.isEmpty) {
          // New conversation - ensure greeting is shown
          if (messages.isEmpty || messages.length == 1 && messages[0]['sender'] == 'jarvis') {
            return; // Keep local greeting
          }
          return;
        }

        final serverMessages = raw.map((m) {
          final role = m['role'] as String? ?? 'jarvis';
          final text = m['text'] as String? ?? '';
          final createdAt = m['created_at'] as String?;
          String time = '';
          if (createdAt != null) {
            try {
              final dt = DateTime.parse(createdAt).toLocal();
              time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            } catch (_) {}
          }
          return {'sender': role == 'user' ? 'user' : 'jarvis', 'text': text, 'time': time};
        }).toList();

        setState(() => messages = serverMessages);
        await prefs.setString('current_messages', jsonEncode(serverMessages));
      }
    } catch (e) {
      print('⚠️ Error loading chat history: $e');
    }
  }

  Future<void> _persistMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_messages', jsonEncode(messages));
    } catch (_) {}
  }

  Future<void> _archiveSessionToHistory() async {
    if (messages.length <= 1) return; // Only the greeting — nothing to archive
    if (_chatId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_sessions') ?? '[]';
      final List sessions = jsonDecode(raw);
      // Deduplicate: remove existing entry for this chatId, then re-add updated
      sessions.removeWhere((s) => s['chat_id'] == _chatId);
      sessions.add({
        'date': DateTime.now().toIso8601String(),
        'messages': messages,
        'chat_id': _chatId,
      });
      // Keep last 50 sessions
      final trimmed = sessions.length > 50 ? sessions.sublist(sessions.length - 50) : sessions;
      await prefs.setString('chat_sessions', jsonEncode(trimmed));
    } catch (_) {}
  }

  Future<void> archiveCurrentSession() => _archiveSessionToHistory();

  static const _promptStart = '<<<PROMPT_START>>>';
  static const _promptEnd   = '<<<PROMPT_END>>>';

  void _checkForFinalPrompt(String text) {
    final s = text.indexOf(_promptStart);
    final e = text.indexOf(_promptEnd);
    if (s == -1 || e == -1 || e <= s) return;
    final prompt = text.substring(s + _promptStart.length, e).trim();
    if (prompt.isEmpty) return;
    _savePromptAsTask(prompt);
  }

  Future<void> _savePromptAsTask(String prompt) async {
    final title = _currentProposalTitle ?? 'הצעה מה-Backlog';
    final content = '$title\n$_kPromptSep\n$prompt';
    try {
      await _api.addTask(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: JC.surfaceAlt,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(children: [
              Icon(Icons.task_alt_rounded, color: JC.indigo500, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'הפרומפט נשמר במשימות תחת "$title"',
                  style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
                ),
              ),
            ]),
            duration: const Duration(seconds: 4),
          ),
        );
        _currentProposalTitle = null;
      }
    } catch (_) {}
  }

  static const _kPromptSep = '<<<AI_PROMPT>>>';

  ApiService get _api => ApiService(_settings);

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSettings != null &&
        widget.initialSettings != oldWidget.initialSettings) {
      setState(() => _settings = widget.initialSettings!);
      _initTts(); // re-apply voice/speed/pitch from updated settings
    }
    if (widget.pendingCommand != null &&
        widget.pendingCommand != oldWidget.pendingCommand) {
      var cmd = widget.pendingCommand!;
      // Extract proposal title marker if present
      const titlePrefix = '[PROPOSAL_TITLE:';
      if (cmd.startsWith(titlePrefix)) {
        final end = cmd.indexOf(']\n\n');
        if (end != -1) {
          _currentProposalTitle = cmd.substring(titlePrefix.length, end);
          cmd = cmd.substring(end + 3);
        }
      }
      final cleanCmd = cmd;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCommandConsumed?.call();
        if (mounted) sendCommand(cleanCmd);
      });
    }
  }

  void _startBackgroundPoll() {
    _bgPollTimer?.cancel();
    _bgPollAttempts = 0;
    _bgPollBaseline = messages.length;
    _bgPollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      _bgPollAttempts++;
      await _loadChatHistory();
      if (!mounted) { _bgPollTimer?.cancel(); return; }
      // Stop when a new message arrived or we hit the limit
      if (messages.length > _bgPollBaseline || _bgPollAttempts >= _bgPollMaxAttempts) {
        _bgPollTimer?.cancel();
        _bgPollTimer = null;
        if (messages.length > _bgPollBaseline) _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _bgPollTimer?.cancel();
    _ttsTimeoutTimer?.cancel();
    _orbBreathController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  // ─── TTS (client-side) ───────────────────────────────────────────────────────
  void _initTts() async {
    final pref = _settings.ttsLanguage.isNotEmpty ? _settings.ttsLanguage : 'he-IL';
    final available = await _flutterTts.isLanguageAvailable(pref);
    await _flutterTts.setLanguage(available == true ? pref : 'en-US');
    await _flutterTts.setSpeechRate(_settings.ttsSpeed);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(_settings.ttsPitch);
    if (_settings.ttsVoiceName.isNotEmpty) {
      try {
        await _flutterTts.setVoice(
            {'name': _settings.ttsVoiceName, 'locale': pref});
      } catch (_) {/* voice not available; keep language default */}
    }
    _flutterTts.setCompletionHandler(_onTtsDone);
    _flutterTts.setErrorHandler((_) => _onTtsDone());
  }

  void _onTtsDone() {
    _ttsTimeoutTimer?.cancel();
    _ttsTimeoutTimer = null;
    if (!mounted) return;
    setState(() => _currentState = JarvisState.idle);
    if (_voiceConversationMode) _listen();
  }

  Future<void> _speakText(String text) async {
    if (!_settings.voiceEnabled) {
      setState(() => _currentState = JarvisState.idle);
      if (_voiceConversationMode) _listen();
      return;
    }
    setState(() => _currentState = JarvisState.speaking);
    // Safety timeout: if TTS completion handler never fires (known Android bug),
    // resume the conversation cycle after at most 15 s.
    _ttsTimeoutTimer?.cancel();
    _ttsTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_currentState == JarvisState.speaking) _onTtsDone();
    });
    try {
      await _flutterTts.stop();
      final result = await _flutterTts.speak(text);
      // speak() returns 1 on success; anything else means TTS won't fire
      // the completion handler, so we resume the cycle manually.
      if (result != 1) _onTtsDone();
    } catch (_) {
      _onTtsDone();
    }
  }

  // ─── Audio (server-side mp3, kept for reference) ─────────────────────────────
  Future<void> _playAudio(String base64String) async {
    if (!_settings.voiceEnabled) {
      setState(() => _currentState = JarvisState.idle);
      return;
    }
    try {
      setState(() => _currentState = JarvisState.speaking);
      // BytesSource is unreliable on Android in audioplayers v6 — write to temp file
      final bytes = base64Decode(base64String);
      final tmpDir = await getTemporaryDirectory();
      final tmpPath =
          '${tmpDir.path}/jarvis_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      await File(tmpPath).writeAsBytes(bytes);
      _lastTtsPath = tmpPath;
      await _audioPlayer.play(DeviceFileSource(tmpPath));
    } catch (e) {
      if (_lastTtsPath != null) {
        File(_lastTtsPath!).delete().catchError((_) {});
        _lastTtsPath = null;
      }
      setState(() => _currentState = JarvisState.idle);
    }
  }

  // ─── Image ────────────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final bytes = await image.readAsBytes(); // XFile.readAsBytes works on web + mobile
      setState(() {
        _imageBytes  = bytes;
        _base64Image = base64Encode(bytes);
      });
    }
  }

  // ─── Voice ────────────────────────────────────────────────────────────────────

  void _listen() async {
    HapticFeedback.selectionClick();

    if (_currentState == JarvisState.listening || _voiceConversationMode) {
      setState(() {
        _voiceConversationMode = false;
        _currentState  = JarvisState.idle;
        _listeningText = '';
      });
      _speech.stop();
      return;
    }

    if (_currentState != JarvisState.idle) return;

    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'notListening' || val == 'done') {
          if (!_voiceConversationMode || _controller.text.trim().isEmpty) {
            setState(() => _currentState = JarvisState.idle);
          }
        }
      },
    );

    if (available) {
      setState(() {
        _voiceConversationMode = true;
        _currentState          = JarvisState.listening;
        _listeningText         = 'מקשיב...';
      });
      _speech.listen(
        onResult: (val) {
          if (_currentState == JarvisState.listening) {
            setState(() {
              _controller.text = val.recognizedWords;
              _listeningText   = val.recognizedWords;
            });
            if (val.finalResult &&
                _voiceConversationMode &&
                val.recognizedWords.trim().isNotEmpty) {
              sendCommand(val.recognizedWords);
            }
          }
        },
        localeId:  'he_IL',
        listenFor: const Duration(seconds: 30),
        pauseFor:  const Duration(seconds: 2),
      );
    } else {
      setState(() {
        _voiceConversationMode = false;
        _currentState          = JarvisState.idle;
        messages.add({'sender': 'jarvis', 'text': '🎤 זיהוי הקול אינו זמין. אנא הקלד את הבקשה.', 'time': _getCurrentTime()});
      });
    }
  }

  // ─── Live Talk launcher ──────────────────────────────────────────────────────
  Future<void> _openLiveTalk() async {
    HapticFeedback.mediumImpact();
    // Make sure no STT/TTS from the chat screen is running before pushing.
    _speech.stop();
    _flutterTts.stop();
    _audioPlayer.stop();
    if (_chatId.isEmpty) await _loadChatHistory();
    if (!mounted) return;
    final returned = await Navigator.of(context).push<List<Map<String, String>>>(
      MaterialPageRoute(
        builder: (_) => LiveTalkScreen(
          chatId: _chatId,
          settings: _settings,
          initialMessages: List.from(messages),
        ),
      ),
    );
    if (!mounted) return;
    // Immediately show the messages from the live session, then background-sync.
    if (returned != null && returned.length > messages.length) {
      setState(() => messages = returned);
    }
    _scrollToBottom();
    _loadChatHistory(); // background sync — no await
  }

  // ─── Quick commands (/task, /note, /remind) ───────────────────────────────────
  Future<bool> _tryQuickCommand(String text) async {
    final trimmed = text.trim();
    String? type;
    String? content;

    if (trimmed.toLowerCase().startsWith('/task ')) {
      type    = 'task';
      content = trimmed.substring(6).trim();
    } else if (trimmed.toLowerCase().startsWith('/note ')) {
      type    = 'note';
      content = trimmed.substring(6).trim();
    } else if (trimmed.toLowerCase().startsWith('/remind ')) {
      type    = 'remind';
      content = trimmed.substring(8).trim();
    }

    if (type == null || content == null || content.isEmpty) return false;

    _controller.clear();
    setState(() {
      messages.add({'sender': 'user', 'text': trimmed, 'time': _getCurrentTime()});
      _currentState = JarvisState.thinking;
    });
    _scrollToBottom();

    try {
      String reply;
      if (type == 'task') {
        await _api.addTask(content);
        reply = '✅ משימה נוספה: $content';
      } else if (type == 'note') {
        await _api.addNote(content);
        reply = '📝 הערה נשמרה: $content';
      } else {
        final when = DateTime.now().add(const Duration(hours: 1));
        await _api.addReminder(content, when.toIso8601String());
        reply = '🔔 תזכורת נוספה לעוד שעה: $content';
      }
      setState(() {
        messages.add({'sender': 'jarvis', 'text': reply, 'time': _getCurrentTime()});
        _currentState = JarvisState.idle;
      });
    } catch (e) {
      setState(() {
        messages.add({'sender': 'jarvis', 'text': '⚠️ לא הצלחתי לשמור. נסה שוב.',
            'time': _getCurrentTime()});
        _currentState = JarvisState.idle;
      });
    }
    _scrollToBottom();
    return true;
  }

  // ─── Send ─────────────────────────────────────────────────────────────────────
  Future<void> sendCommand(String text) async {
    if (text.trim().isEmpty && _base64Image == null) return;
    if (_currentState == JarvisState.thinking) return;

    // Handle quick commands before sending to server
    if (_base64Image == null && await _tryQuickCommand(text)) return;

    HapticFeedback.lightImpact();
    _speech.stop();

    setState(() {
      String display = text;
      if (_imageBytes != null) display += ' [תמונה מצורפת]';
      messages.add({'sender': 'user', 'text': display, 'time': _getCurrentTime()});
      _currentState  = JarvisState.thinking;
      _listeningText = '';
    });
    _persistMessages();

    _scrollToBottom();
    _controller.clear();

    String? imageToSend = _base64Image;
    setState(() {
      _imageBytes  = null;
      _base64Image = null;
    });

    // Use streaming endpoint when there is no image (faster delivery + voice-ready)
    if (imageToSend == null) {
      await _sendCommandStreaming(text);
      _scrollToBottom();
      return;
    }

    // Image path: must use /ask-jarvis (streaming doesn't support images)
    final url = Uri.parse('${_settings.serverUrl}/ask-jarvis');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command':  text,
          'image':    imageToSend,
          'chatId':   _chatId,
          'settings': _settings.toJson(),
        }),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('timeout'),
      );

      if (response.statusCode == 200) {
        final data          = jsonDecode(response.body);
        final String answer = data['answer'];
        final action        = data['action'];

        final isNav     = action is Map && action['type'] == 'navigate';
        final navTarget = isNav ? action['target']?.toString() : null;
        final navLabel  = isNav ? action['label']?.toString() : null;

        setState(() => messages.add({
              'sender': 'jarvis',
              'text': answer,
              'time': _getCurrentTime(),
              if (navTarget != null) 'navTarget': navTarget,
              if (navLabel != null) 'navLabel': navLabel,
            }));
        _persistMessages();
        _checkForFinalPrompt(answer);

        // Navigate actions render an inline button in the bubble (see _ChatBubble);
        // settings_update actions are applied silently; whatsapp/email need dialog.
        if (action != null && !isNav && mounted) {
          if (action['type'] == 'settings_update') {
            await _applySettingsUpdate(Map<String, dynamic>.from(action['data'] as Map));
          } else {
            await _confirmAndSend(action);
          }
        }

        // If the server started a background job, poll for the result automatically
        if (answer.contains('ברקע') && answer.contains('יופיע בשיחה')) {
          _startBackgroundPoll();
        }

        // Track agent calls for survey
        _agentCallCount++;
        _checkSurveyEligibility();

        _speakText(answer);
      } else {
        setState(() {
          messages.add({'sender': 'jarvis', 'text': 'שגיאה מהשרת: קוד ${response.statusCode}', 'time': _getCurrentTime()});
          _currentState = JarvisState.idle;
        });
      }
    } catch (e) {
      final errStr     = e.toString();
      final isTimeout  = errStr.contains('timeout') || errStr.contains('TimeoutException');
      final isRefused  = errStr.contains('refused') || errStr.contains('ECONNREFUSED') || errStr.contains('NetworkError');
      final isLocal    = _settings.useLocalServer;
      final serverAddr = _settings.serverUrl;

      String msg;
      if (isTimeout) {
        msg = '⏱ זמן פג (20 שניות)\n'
            '${isLocal ? "השרת ב-$serverAddr לא ענה בזמן.\nוודא שהשרת רץ ושה-IP נכון." : "שרת הענן לא ענה, נסה שוב."}';
      } else if (isRefused) {
        msg = '🔌 לא ניתן להתחבר\n'
            'הבקשה נדחתה ב-$serverAddr\n'
            'וודא שהשרת רץ ושהפורט 3000 פתוח.';
      } else {
        msg = '⚠️ ${ApiService.friendlyError(e)}';
      }

      setState(() {
        messages.add({'sender': 'jarvis', 'text': msg, 'time': _getCurrentTime()});
        _currentState          = JarvisState.idle;
        _voiceConversationMode = false;
      });
    }

    _scrollToBottom();
  }

  // ─── SSE streaming command (voice-mode optimised) ────────────────────────────
  Future<void> _sendCommandStreaming(String text) async {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('${_settings.serverUrl}/stream-jarvis'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'command':  text,
        'chatId':   _chatId,
        'settings': _settings.toJson(),
      });

      final sr = await client.send(request).timeout(const Duration(seconds: 35));
      if (sr.statusCode != 200) throw Exception('server ${sr.statusCode}');

      String accumulated = '';
      String lineBuffer  = '';

      await for (final raw in sr.stream.transform(utf8.decoder)) {
        if (!mounted) break;
        lineBuffer += raw;
        while (lineBuffer.contains('\n')) {
          final idx  = lineBuffer.indexOf('\n');
          final line = lineBuffer.substring(0, idx).trim();
          lineBuffer = lineBuffer.substring(idx + 1);
          if (!line.startsWith('data: ')) continue;
          try {
            final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;

            if (data['error'] != null) throw Exception(data['error'].toString());
            if (data['chatId'] is String) _chatId = data['chatId'] as String;

            if (data['chunk'] is String) {
              accumulated += data['chunk'] as String;
            }

            if (data['done'] == true) {
              if (!mounted) return;
              final answer = accumulated;
              final action = data['action'];
              final isNav     = action is Map && action['type'] == 'navigate';
              final navTarget = isNav ? action['target']?.toString() : null;
              final navLabel  = isNav ? action['label']?.toString() : null;
              setState(() {
                messages.add({
                  'sender': 'jarvis',
                  'text': answer,
                  'time': _getCurrentTime(),
                  if (navTarget != null) 'navTarget': navTarget,
                  if (navLabel != null) 'navLabel': navLabel,
                });
              });
              _persistMessages();
              _checkForFinalPrompt(answer);
              if (action != null && !isNav && mounted) {
                if (action['type'] == 'settings_update') {
                  await _applySettingsUpdate(Map<String, dynamic>.from(action['data'] as Map));
                } else {
                  await _confirmAndSend(Map<String, dynamic>.from(action as Map));
                }
              }
              _agentCallCount++;
              _checkSurveyEligibility();
              _speakText(answer);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      final isTimeout = errStr.contains('timeout') || errStr.contains('TimeoutException');
      final msg = isTimeout
          ? '⏱ זמן פג — נסה שוב'
          : '⚠️ ${ApiService.friendlyError(e)}';
      setState(() {
        messages.add({'sender': 'jarvis', 'text': msg, 'time': _getCurrentTime()});
        _currentState          = JarvisState.idle;
        _voiceConversationMode = false;
      });
    } finally {
      client.close();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkSurveyEligibility() async {
    if (_surveyShownThisSession) return;

    final sessionMinutes = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inMinutes
        : 0;

    if (sessionMinutes < 25 && _agentCallCount < 8) return;

    _surveyShownThisSession = true;

    try {
      final url = Uri.parse(
        '${_settings.serverUrl}/survey-check?sessionMinutes=$sessionMinutes&agentCallCount=$_agentCallCount',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (!mounted || response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data['showSurvey'] == true && mounted) {
        final questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
        if (questions.isNotEmpty) {
          // Surface as a gentle banner instead of a blocking modal — the user
          // opens it when convenient, so it never cuts into the conversation.
          setState(() => _pendingSurveyQuestions = questions);
        }
      }
    } catch (e) {
      print('⚠️ Survey check error: $e');
    }
  }

  void _showSurveyModal(List<Map<String, dynamic>> questions) {
    setState(() => _pendingSurveyQuestions = null);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => Container(
          color: JC.bg,
          child: SurveyModal(
            questions: questions,
            settings: _settings,
            onDismiss: () {},
          ),
        ),
      ),
    );
  }

  Widget _buildSurveyBanner() {
    final questions = _pendingSurveyQuestions;
    if (questions == null) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showSurveyModal(questions),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: JC.blue500.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: JC.blue400.withValues(alpha: 0.4), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.feedback_outlined, size: 20, color: JC.blue400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'יש לך דקה? משוב קצר יעזור לי להשתפר',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: JC.textPrimary,
                        fontFamily: 'Heebo',
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        setState(() => _pendingSurveyQuestions = null),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: JC.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Confirm & Send ───────────────────────────────────────────────────────────
  Future<void> _applySettingsUpdate(Map<String, dynamic> data) async {
    if (data.containsKey('personality'))    _settings.personality    = data['personality'] as String;
    if (data.containsKey('voiceEnabled'))   _settings.voiceEnabled   = data['voiceEnabled'] as bool;
    if (data.containsKey('ttsSpeed'))       _settings.ttsSpeed       = (data['ttsSpeed'] as num).toDouble();
    if (data.containsKey('responseLength')) _settings.responseLength = data['responseLength'] as String;
    if (data.containsKey('userName'))       _settings.userName       = data['userName'] as String;
    if (data.containsKey('assistantName'))  _settings.assistantName  = data['assistantName'] as String;
    await _settings.save();
    if (mounted) setState(() {});
    widget.onSettingsChanged?.call(_settings);
  }

  Future<void> _confirmAndSend(Map<String, dynamic> action) async {
    final type    = action['type'] as String;
    final message = action['message'] as String;
    final isWA    = type == 'whatsapp';
    final label   = isWA ? 'WhatsApp' : 'מייל';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JC.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: JC.border, width: 1),
        ),
        title: Text(
          'לשלוח $label?',
          style: TextStyle(color: JC.textPrimary, fontSize: 16,
              fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
          textDirection: TextDirection.rtl,
        ),
        content: Text(
          message,
          style: TextStyle(color: JC.textSecondary, fontSize: 14,
              height: 1.6, fontFamily: 'Heebo'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('ביטול',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('שלח $label',
                style: TextStyle(color: JC.blue400,
                    fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (isWA) {
      final phone = action['phone'] as String;
      final waUrl = Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(waUrl)) {
        await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      }
    } else {
      try {
        final res = await http.post(
          Uri.parse('${_settings.serverUrl}/send-email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'to': action['email'], 'message': message}),
        ).timeout(const Duration(seconds: 15));
        final ok = jsonDecode(res.body)['ok'] == true;
        if (mounted) {
          setState(() => messages.add({
            'sender': 'jarvis',
            'text': ok ? '✅ המייל נשלח בהצלחה!' : '❌ שגיאה בשליחת המייל.',
            'time': _getCurrentTime(),
          }));
        }
      } catch (_) {
        if (mounted) {
          setState(() => messages.add({
            'sender': 'jarvis',
            'text': '❌ לא הצלחתי לשלוח את המייל.',
            'time': _getCurrentTime(),
          }));
        }
      }
    }
  }

  // ─── History ──────────────────────────────────────────────────────────────────
  void _openHistory() {
    Navigator.push(
      context,
      SlideFadeRoute(
        page: HistoryScreen(
          onResume: (session) async {
            final chatId = session['chat_id'] as String? ?? '';
            final msgs = (session['messages'] as List?)
                ?.cast<Map<String, dynamic>>() ?? [];
            if (chatId.isEmpty || msgs.isEmpty) return;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('current_chat_id', chatId);
            await prefs.setString('current_messages', jsonEncode(msgs));
            if (!mounted) return;
            setState(() {
              _chatId = chatId;
              messages = msgs
                  .map((m) => m.map((k, v) => MapEntry(k, v.toString())))
                  .toList();
            });
            _scrollToBottom();
          },
        ),
      ),
    );
  }

  Future<void> _startNewChat() async {
    await _archiveSessionToHistory();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    // Generate new chat_id for the new session
    _chatId = 'chat-${DateTime.now().millisecondsSinceEpoch}-${(math.Random().nextInt(100000)).toString()}';

    // Save new ID and clear all previous session data
    await prefs.setString('current_chat_id', _chatId);
    await prefs.remove('current_messages');

    _speech.stop();
    _flutterTts.stop();
    _audioPlayer.stop();
    setState(() {
      _voiceConversationMode = false;
      _currentState = JarvisState.idle;
      _listeningText = '';
      messages = [
        {'sender': 'jarvis', 'text': 'שיחה חדשה! מוכן לעזור, ${_settings.userName}.', 'time': _getCurrentTime()},
      ];
    });

    // Reset survey tracking
    _sessionStartTime = DateTime.now();
    _agentCallCount = 0;
    _surveyShownThisSession = false;

    // Ensure new chat is persisted immediately
    await _persistMessages();
    _scrollToBottom();

    // Log for debugging
    print('✅ New chat started with ID: $_chatId');
  }

  // ─── Settings ─────────────────────────────────────────────────────────────────
  void _openSettings() {
    Navigator.push(
      context,
      SlideFadeRoute(
        page: SettingsScreen(
          settings: _settings,
          onSave: (updated) async {
            await updated.save();
            setState(() => _settings = updated);
            widget.onSettingsChanged?.call(updated);
          },
        ),
      ),
    );
  }

  String get _orbHint {
    switch (_currentState) {
      case JarvisState.listening:
        return _listeningText.isEmpty ? 'מקשיב...' : _listeningText;
      case JarvisState.thinking: return 'חושב...';
      case JarvisState.speaking: return 'מדבר...';
      default:
        return _voiceConversationMode ? 'לחץ לעצירה' : 'לחץ לשיחה קולית';
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool isListening = _currentState == JarvisState.listening;
    final int itemCount = messages.length +
        (_currentState == JarvisState.thinking ? 1 : 0);

    return Scaffold(
      backgroundColor: JC.bg,
      extendBodyBehindAppBar: true,

      // ── AppBar ────────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [JC.bg, JC.bg.withValues(alpha: 0)],
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, color: JC.textSecondary, size: 22),
          onPressed: () {
            if (widget.onOpenDrawer != null) {
              widget.onOpenDrawer!();
            } else {
              _openSettings();
            }
          },
        ),
        title: Text(
          'ג׳רביס',
          style: TextStyle(
            color: JC.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            fontFamily: 'Heebo',
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: JC.textSecondary, size: 22),
            tooltip: 'רענן שיחה',
            onPressed: _loadChatHistory,
          ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined,
                color: JC.textSecondary, size: 22),
            tooltip: 'שיחה חדשה',
            onPressed: _startNewChat,
          ),
          IconButton(
            icon: Icon(Icons.history_rounded,
                color: JC.textSecondary, size: 22),
            tooltip: 'היסטוריית שיחות',
            onPressed: _openHistory,
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: Stack(
        children: [

          // ── Background ambient glow (bottom) ─────────────────────────────────
          Positioned(
            bottom: -60,
            left: -40,
            right: -40,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    JC.blue500.withValues(alpha: 0.18),
                    JC.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [

              // ── Orb (tappable — primary mic trigger) ─────────────────────
              AnimatedOpacity(
                opacity: _showOrbAndHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Padding(
                  padding: const EdgeInsets.only(top: 96, bottom: 4),
                  child: GestureDetector(
                    onTap: _openLiveTalk,
                    onLongPress: null,
                    child: Column(
                      children: [
                        _JarvisOrb(
                          state: _currentState,
                          breathAnim: _orbBreath,
                        ),
                        const SizedBox(height: 10),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _orbHint,
                            key: ValueKey(_orbHint),
                            style: TextStyle(
                              color: _currentState == JarvisState.listening
                                  ? JC.blue400
                                  : JC.textMuted,
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              fontWeight: _currentState == JarvisState.listening
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Messages ──────────────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {

                    // Thinking bubble
                    if (index == messages.length &&
                        _currentState == JarvisState.thinking) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 240),
                        builder: (_, v, child) => Opacity(
                          opacity: v,
                          child: Transform.translate(
                              offset: Offset(0, 10 * (1 - v)),
                              child: child),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            decoration: BoxDecoration(
                              color: JC.jarvisBubble,
                              borderRadius: const BorderRadius.only(
                                topLeft:     Radius.circular(18),
                                topRight:    Radius.circular(18),
                                bottomRight: Radius.circular(18),
                                bottomLeft:  Radius.circular(4),
                              ),
                              border: Border.all(
                                  color: JC.border.withValues(alpha: 0.6),
                                  width: 0.8),
                            ),
                            child: const _TypingDots(),
                          ),
                        ),
                      );
                    }

                    return _ChatBubble(
                      msg: messages[index],
                      index: index,
                      onSpeak: _speakText,
                      onNavigate: widget.onNavigate,
                    );
                  },
                ),
              ),

              // ── Survey banner (gentle, dismissible) ───────────────────────────
              _buildSurveyBanner(),

              // ── Image preview ─────────────────────────────────────────────────
              if (_imageBytes != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          height: 72, width: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: JC.border, width: 1),
                            image: DecorationImage(
                                image: MemoryImage(_imageBytes!),
                                fit: BoxFit.cover),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _imageBytes  = null;
                            _base64Image = null;
                          }),
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xCC111827),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close_rounded,
                                color: JC.textPrimary, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Scroll to bottom button ────────────────────────────────────
              if (_showScrollToBottom)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: JC.blue400.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: JC.blue400.withValues(alpha: 0.5), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'הודעות חדשות',
                              style: TextStyle(
                                color: JC.blue400,
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_downward_rounded,
                                color: JC.blue400, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // ── Input bar ─────────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: JC.surfaceAlt,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isListening
                        ? JC.blue400.withValues(alpha: 0.6)
                        : JC.border.withValues(alpha: 0.7),
                    width: isListening ? 1.2 : 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isListening
                          ? JC.blue500.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.3),
                      blurRadius: isListening ? 16 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Image picker
                    _InputIconButton(
                      icon: Icons.image_outlined,
                      active: _imageBytes != null,
                      onTap: _pickImage,
                    ),
                    // Mic
                    _InputIconButton(
                      icon: isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      active: isListening,
                      onTap: _listen,
                    ),
                    // Text input
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 15,
                          fontFamily: 'Heebo',
                        ),
                        decoration: InputDecoration(
                          hintText: 'שאל אותי משהו...',
                          hintStyle: TextStyle(
                            color: JC.textMuted,
                            fontFamily: 'Heebo',
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onSubmitted: sendCommand,
                      ),
                    ),
                    // Send button
                    GestureDetector(
                      onTap: () => sendCommand(_controller.text),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              JC.blue400,
                              JC.blue500.withValues(alpha: 0.8),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: JC.blue500.withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Input Icon Button ────────────────────────────────────────────────────────
class _InputIconButton extends StatelessWidget {
  final IconData icon;
  final bool     active;
  final VoidCallback onTap;

  const _InputIconButton({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 38, height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? JC.blue500.withValues(alpha: 0.2)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 21,
          color: active ? JC.blue400 : JC.textMuted,
        ),
      ),
    );
  }
}
