import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jarvis',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1C1C1C),
          elevation: 0,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

enum JarvisState { idle, listening, thinking, speaking }

// ── Animated Typing Dots ───────────────────────────────────────────────────────
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
      vsync: this,
      duration: const Duration(milliseconds: 500),
    ));
    _anims = _controllers.map((c) =>
      Tween<double>(begin: 0, end: -7).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      )
    ).toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 170), () {
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
            width: 7, height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF9E9E9E),
              shape: BoxShape.circle,
            ),
          ),
        ),
      )),
    );
  }
}

// ── Chat Screen ────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

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

  File?   _selectedImage;
  String? _base64Image;

  AppSettings _settings = AppSettings();
  late String _sessionId;

  // ── Orb breathing ──
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
    _sessionId = DateTime.now().toIso8601String();

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) setState(() => _currentState = JarvisState.idle);
    });

    AppSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });

    // Orb breathing animation
    _orbBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _orbBreath = Tween<double>(begin: 0.93, end: 1.07).animate(
      CurvedAnimation(parent: _orbBreathController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _orbBreathController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─── Orb Colors ───────────────────────────────────────────────────────────────
  List<Color> _getOrbColors() {
    switch (_currentState) {
      case JarvisState.listening:
        return [Colors.white, const Color(0xFF9E9E9E)];
      case JarvisState.thinking:
        return [const Color(0xFF8A8A8A), const Color(0xFF2A2A2A)];
      case JarvisState.speaking:
        return [const Color(0xFFD0D0D0), const Color(0xFF606060)];
      case JarvisState.idle:
      default:
        return [const Color(0xFF4A4A4A), const Color(0xFF1A1A1A)];
    }
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
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      final bytes = await File(image.path).readAsBytes();
      setState(() {
        _selectedImage = File(image.path);
        _base64Image   = base64Encode(bytes);
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
          _listeningText = 'מקשיב לך...';
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

  // ─── Session Save ──────────────────────────────────────────────────────────────
  Future<void> _saveSession() async {
    if (messages.length <= 1) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_sessions') ?? '[]';
      final List sessions = jsonDecode(raw);
      final sessionData = {
        'id': _sessionId,
        'date': _sessionId,
        'messages': messages,
      };
      final idx = sessions.indexWhere((s) => s['id'] == _sessionId);
      if (idx >= 0) {
        sessions[idx] = sessionData;
      } else {
        sessions.add(sessionData);
      }
      if (sessions.length > 50) sessions.removeAt(0);
      await prefs.setString('chat_sessions', jsonEncode(sessions));
    } catch (_) {}
  }

  // ─── Send ──────────────────────────────────────────────────────────────────────
  Future<void> sendCommand(String text) async {
    if (text.trim().isEmpty && _base64Image == null) return;

    _speech.stop();

    setState(() {
      String display = text;
      if (_selectedImage != null) display += ' [תמונה מצורפת]';
      messages.add({'sender': 'user', 'text': display, 'time': _getCurrentTime()});
      _currentState  = JarvisState.thinking;
      _listeningText = '';
    });

    _scrollToBottom();
    _controller.clear();

    String? imageToSend = _base64Image;
    setState(() {
      _selectedImage = null;
      _base64Image   = null;
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
      );

      if (response.statusCode == 200) {
        final data          = jsonDecode(response.body);
        final String answer = data['answer'];
        final String? audio = data['audio'];
        final action        = data['action'];

        setState(() => messages.add({'sender': 'jarvis', 'text': answer, 'time': _getCurrentTime()}));

        if (action != null && mounted) {
          await _handleAction(action);
        }

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
      setState(() {
        messages.add({'sender': 'jarvis', 'text': 'תקלה בתקשורת עם השרת.', 'time': _getCurrentTime()});
        _currentState = JarvisState.idle;
      });
    }

    _scrollToBottom();
    _saveSession();
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

  // ─── Handle Action ─────────────────────────────────────────────────────────────
  Future<void> _handleAction(Map<String, dynamic> action) async {
    final type = action['type'] as String;

    // ── Music → open YouTube Music ──
    if (type == 'music') {
      final url = Uri.parse(action['url'] as String);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'פתוח ב-YouTube Music?',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('לא', style: TextStyle(color: Color(0xFF6E6E6E))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('פתח', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed == true && await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // ── WhatsApp / Email ──
    final message = action['message'] as String;
    final isWA    = type == 'whatsapp';
    final label   = isWA ? 'WhatsApp' : 'מייל';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'לשלוח $label?',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          textDirection: TextDirection.rtl,
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14, height: 1.5),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול', style: TextStyle(color: Color(0xFF6E6E6E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('שלח $label', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (isWA) {
      final phone = action['phone'] as String;
      final waUrl = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
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

  // ─── Navigation ────────────────────────────────────────────────────────────────
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          settings: _settings,
          onSave: (updated) async {
            await updated.save();
            setState(() => _settings = updated);
          },
        ),
      ),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool isListening = _currentState == JarvisState.listening;
    final int itemCount    = messages.length + (_currentState == JarvisState.thinking ? 1 : 0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1C),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'יציאה?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textDirection: TextDirection.rtl,
            ),
            content: const Text(
              'לסגור את האפליקציה?',
              style: TextStyle(color: Color(0xFF9E9E9E)),
              textDirection: TextDirection.rtl,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ביטול', style: TextStyle(color: Color(0xFF6E6E6E))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('יציאה', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              AnimatedBuilder(
                animation: _orbBreath,
                builder: (_, __) => Icon(
                  Icons.bolt,
                  color: Colors.white.withOpacity(0.55 + 0.45 * (_orbBreath.value - 0.93) / 0.14),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _settings.assistantName.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 16),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history, color: Color(0xFF9E9E9E)),
              onPressed: _openHistory,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Color(0xFF9E9E9E)),
              onPressed: _openSettings,
            ),
          ],
        ),

        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (DragEndDetails details) {
            if ((details.primaryVelocity ?? 0) > 500) _openHistory();
          },
          child: Column(
            children: [

              // ── Orb ────────────────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: AnimatedBuilder(
                  animation: _orbBreath,
                  builder: (context, child) => Transform.scale(
                    scale: _currentState == JarvisState.idle ? _orbBreath.value : 1.0,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width:  _currentState == JarvisState.thinking ? 90 : 78,
                    height: _currentState == JarvisState.thinking ? 90 : 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: _getOrbColors()),
                      boxShadow: [
                        BoxShadow(
                          color: _getOrbColors()[0].withOpacity(0.5),
                          blurRadius:   _currentState == JarvisState.listening ? 28 : 12,
                          spreadRadius: _currentState == JarvisState.speaking  ? 8  : 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Messages ────────────────────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {

                    // Thinking bubble
                    if (index == messages.length && _currentState == JarvisState.thinking) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 250),
                        builder: (_, value, child) => Opacity(
                          opacity: value,
                          child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1C1C1C),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                                bottomLeft: Radius.circular(14), bottomRight: Radius.circular(0),
                              ),
                            ),
                            child: const _TypingDots(),
                          ),
                        ),
                      );
                    }

                    // Message bubble with entrance animation
                    final msg    = messages[index];
                    final isUser = msg['sender'] == 'user';

                    return TweenAnimationBuilder<double>(
                      key: ValueKey(index),
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 16 * (1 - value)),
                          child: child,
                        ),
                      ),
                      child: Align(
                        alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF2A2A2A) : const Color(0xFF1C1C1C),
                            borderRadius: BorderRadius.only(
                              topLeft:     const Radius.circular(14),
                              topRight:    const Radius.circular(14),
                              bottomLeft:  Radius.circular(isUser ? 0 : 14),
                              bottomRight: Radius.circular(isUser ? 14 : 0),
                            ),
                            border: isUser ? null : Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
                          ),
                          child: Column(
                            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg['text']!,
                                style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4),
                                textDirection: TextDirection.rtl,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg['time'] ?? '',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF555555)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ── Listening text ──────────────────────────────────────────────────────
              if (isListening)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    _listeningText,
                    style: const TextStyle(color: Color(0xFF9E9E9E), fontStyle: FontStyle.italic, fontSize: 13),
                  ),
                ),

              // ── Image preview ───────────────────────────────────────────────────────
              if (_selectedImage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          height: 75, width: 75,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            image: DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() { _selectedImage = null; _base64Image = null; }),
                          child: Container(
                            decoration: const BoxDecoration(color: Color(0xAA000000), shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Input bar ───────────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1C1C1C),
                  border: Border(top: BorderSide(color: Color(0xFF2A2A2A), width: 0.5)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image_outlined, size: 22),
                      color: const Color(0xFF6E6E6E),
                      onPressed: _pickImage,
                    ),
                    IconButton(
                      icon: Icon(isListening ? Icons.mic : Icons.mic_none, size: 22),
                      color: isListening ? Colors.white : const Color(0xFF6E6E6E),
                      onPressed: _listen,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: const InputDecoration(
                          hintText: 'הקלד הודעה...',
                          hintStyle: TextStyle(color: Color(0xFF444444)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onSubmitted: sendCommand,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => sendCommand(_controller.text),
                      child: Container(
                        width: 38, height: 38,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3A3A3A),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
