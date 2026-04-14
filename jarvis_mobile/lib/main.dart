import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'settings_screen.dart';
import 'main_shell.dart';
import 'transitions/slide_fade_route.dart';
import 'screens/onboarding_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const JarvisApp());
}

// ─── Design Tokens ────────────────────────────────────────────────────────────
class JC {
  // Backgrounds
  static const bg         = Color(0xFF05090E);
  static const surface    = Color(0xFF0B1422);
  static const surfaceAlt = Color(0xFF0F1929);
  static const border     = Color(0xFF1A2E4A);

  // Blue palette
  static const blue500 = Color(0xFF3B82F6);
  static const blue400 = Color(0xFF60A5FA);
  static const blue300 = Color(0xFF93C5FD);

  // Text
  static const textPrimary   = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted     = Color(0xFF475569);

  // Bubbles
  static const userBubble   = Color(0xFF11284A);
  static const jarvisBubble = Color(0xFF0B1929);

  // Actions
  static const cancelRed = Color(0xFFEF4444);
}

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  bool? _onboarded;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _onboarded = prefs.getBool('onboarded') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jarvis',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: JC.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: JC.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: _onboarded == null
          ? const Scaffold(backgroundColor: JC.bg) // brief splash
          : _onboarded!
              ? const MainShell()
              : const OnboardingScreen(),
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
              color: JC.blue400.withOpacity(0.8),
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
      case JarvisState.thinking: return 90.0;
      case JarvisState.speaking: return 86.0;
      default: return 78.0;
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
                color: _glow.withOpacity(0.06),
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
                color: _glow.withOpacity(0.13),
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
                    color: _glow.withOpacity(0.55),
                    blurRadius: 24,
                    spreadRadius: state == JarvisState.idle ? 1 : 6,
                  ),
                  BoxShadow(
                    color: _glow.withOpacity(0.2),
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
                  color: Colors.white.withOpacity(0.22),
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
class _ChatBubble extends StatelessWidget {
  final Map<String, String> msg;
  final int index;

  const _ChatBubble({required this.msg, required this.index});

  @override
  Widget build(BuildContext context) {
    final isUser = msg['sender'] == 'user';

    return TweenAnimationBuilder<double>(
      key: ValueKey(index),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: Align(
        // User messages → right, Jarvis → left (standard RTL chat convention)
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            bottom: 6,
            right: isUser ? 0 : 48,
            left:  isUser ? 48 : 0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser ? JC.userBubble : JC.jarvisBubble,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(18),
              topRight:    const Radius.circular(18),
              // Tail: user → bottom-right, jarvis → bottom-left
              bottomLeft:  Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: Border.all(
              color: isUser
                  ? JC.blue500.withOpacity(0.35)
                  : JC.border.withOpacity(0.6),
              width: 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                msg['text']!,
                style: const TextStyle(
                  fontSize: 15,
                  color: JC.textPrimary,
                  height: 1.55,
                  fontFamily: 'Heebo',
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 3),
              Text(
                msg['time'] ?? '',
                style: TextStyle(
                  fontSize: 10,
                  color: JC.textMuted.withOpacity(0.7),
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Chat Screen ──────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final AppSettings? initialSettings;
  final ValueChanged<AppSettings>? onSettingsChanged;

  const ChatScreen({
    super.key,
    this.initialSettings,
    this.onSettingsChanged,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller       = TextEditingController();
  final ScrollController       _scrollController = ScrollController();

  late stt.SpeechToText _speech;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker      = ImagePicker();

  JarvisState _currentState = JarvisState.idle;
  String      _listeningText = '';

  Uint8List? _imageBytes;
  String?    _base64Image;

  AppSettings _settings = AppSettings();

  late AnimationController _orbBreathController;
  late Animation<double>   _orbBreath;

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
    _speech = stt.SpeechToText();

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _currentState = JarvisState.idle);
    });

    if (widget.initialSettings != null) {
      _settings = widget.initialSettings!;
    } else {
      AppSettings.load().then((s) {
        if (mounted) setState(() => _settings = s);
      });
    }

    _orbBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat(reverse: true);
    _orbBreath = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _orbBreathController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSettings != null &&
        widget.initialSettings != oldWidget.initialSettings) {
      setState(() => _settings = widget.initialSettings!);
    }
  }

  @override
  void dispose() {
    _orbBreathController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─── Audio ────────────────────────────────────────────────────────────────────
  Future<void> _playAudio(String base64String) async {
    if (!_settings.voiceEnabled) {
      setState(() => _currentState = JarvisState.idle);
      return;
    }
    try {
      setState(() => _currentState = JarvisState.speaking);
      await _audioPlayer.play(BytesSource(base64Decode(base64String)));
    } catch (e) {
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
    if (_currentState != JarvisState.listening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'notListening' || val == 'done') {
            setState(() => _currentState = JarvisState.idle);
          }
        },
      );
      if (available) {
        setState(() {
          _currentState  = JarvisState.listening;
          _listeningText = 'מקשיב...';
        });
        _speech.listen(
          onResult: (val) {
            if (_currentState == JarvisState.listening) {
              setState(() {
                _controller.text = val.recognizedWords;
                _listeningText   = val.recognizedWords;
              });
            }
          },
          localeId: 'he_IL',
        );
      }
    } else {
      setState(() {
        _currentState  = JarvisState.idle;
        _listeningText = '';
      });
      _speech.stop();
    }
  }

  // ─── Send ─────────────────────────────────────────────────────────────────────
  Future<void> sendCommand(String text) async {
    if (text.trim().isEmpty && _base64Image == null) return;

    _speech.stop();

    setState(() {
      String display = text;
      if (_imageBytes != null) display += ' [תמונה מצורפת]';
      messages.add({'sender': 'user', 'text': display, 'time': _getCurrentTime()});
      _currentState  = JarvisState.thinking;
      _listeningText = '';
    });

    _scrollToBottom();
    _controller.clear();

    String? imageToSend = _base64Image;
    setState(() {
      _imageBytes  = null;
      _base64Image = null;
    });

    final url = Uri.parse('${_settings.serverUrl}/ask-jarvis');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command':  text,
          'image':    imageToSend,
          'settings': _settings.toJson(),
        }),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception('timeout'),
      );

      if (response.statusCode == 200) {
        final data          = jsonDecode(response.body);
        final String answer = data['answer'];
        final String? audio = data['audio'];
        final action        = data['action'];

        setState(() => messages.add(
            {'sender': 'jarvis', 'text': answer, 'time': _getCurrentTime()}));

        if (action != null && mounted) await _confirmAndSend(action);

        if (audio != null && audio.isNotEmpty) {
          _playAudio(audio);
        } else {
          setState(() => _currentState = JarvisState.idle);
        }
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
        msg = '🔌 Connection Refused\n'
            'הבקשה נדחתה ב-$serverAddr\n'
            'וודא ש-node server.js רץ ושהפורט 3000 פתוח.';
      } else {
        msg = '⚠️ שגיאת תקשורת\n'
            'כתובת: $serverAddr\n'
            'שגיאה: $errStr';
      }

      setState(() {
        messages.add({'sender': 'jarvis', 'text': msg, 'time': _getCurrentTime()});
        _currentState = JarvisState.idle;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Confirm & Send ───────────────────────────────────────────────────────────
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
          side: const BorderSide(color: JC.border, width: 1),
        ),
        title: Text(
          'לשלוח $label?',
          style: const TextStyle(color: JC.textPrimary, fontSize: 16,
              fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
          textDirection: TextDirection.rtl,
        ),
        content: Text(
          message,
          style: const TextStyle(color: JC.textSecondary, fontSize: 14,
              height: 1.6, fontFamily: 'Heebo'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('שלח $label',
                style: const TextStyle(color: JC.blue400,
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
        );
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

  // ─── Copy chat ────────────────────────────────────────────────────────────────
  void _copyChat() {
    final text = messages.map((m) {
      final sender = m['sender'] == 'user' ? 'אתה' : 'ג׳רביס';
      return '$sender: ${m['text']}';
    }).join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('השיחה הועתקה ללוח ✓',
            style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary)),
        backgroundColor: JC.surfaceAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
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

  // ─── State label ──────────────────────────────────────────────────────────────
  String get _stateLabel {
    switch (_currentState) {
      case JarvisState.listening: return 'מקשיב...';
      case JarvisState.thinking:  return 'חושב...';
      case JarvisState.speaking:  return 'מדבר...';
      default:                    return 'מצב Live';
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
              colors: [JC.bg, JC.bg.withOpacity(0)],
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: JC.textSecondary, size: 22),
          onPressed: _openSettings,
        ),
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _stateLabel,
            key: ValueKey(_stateLabel),
            style: const TextStyle(
              color: JC.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              fontFamily: 'Heebo',
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined,
                color: JC.textSecondary, size: 20),
            tooltip: 'העתק שיחה',
            onPressed: _copyChat,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              icon: const Icon(Icons.settings_outlined,
                  color: JC.textSecondary, size: 20),
              onPressed: _openSettings,
            ),
          ),
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
                    JC.blue500.withOpacity(0.18),
                    JC.bg.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [

              // ── Orb ──────────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 100, bottom: 8),
                child: _JarvisOrb(
                  state: _currentState,
                  breathAnim: _orbBreath,
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
                                  color: JC.border.withOpacity(0.6),
                                  width: 0.8),
                            ),
                            child: const _TypingDots(),
                          ),
                        ),
                      );
                    }

                    return _ChatBubble(msg: messages[index], index: index);
                  },
                ),
              ),

              // ── Listening hint ────────────────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: isListening && _listeningText.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: Text(
                          _listeningText,
                          style: const TextStyle(
                            color: JC.textSecondary,
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            fontFamily: 'Heebo',
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

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
                            child: const Icon(Icons.close_rounded,
                                color: JC.textPrimary, size: 14),
                          ),
                        ),
                      ],
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
                        ? JC.blue400.withOpacity(0.6)
                        : JC.border.withOpacity(0.7),
                    width: isListening ? 1.2 : 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isListening
                          ? JC.blue500.withOpacity(0.2)
                          : Colors.black.withOpacity(0.3),
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
                        style: const TextStyle(
                          color: JC.textPrimary,
                          fontSize: 15,
                          fontFamily: 'Heebo',
                        ),
                        decoration: const InputDecoration(
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
                              JC.blue500.withOpacity(0.8),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: JC.blue500.withOpacity(0.45),
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
              ? JC.blue500.withOpacity(0.2)
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
