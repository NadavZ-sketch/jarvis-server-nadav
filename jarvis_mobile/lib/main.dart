import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'app_settings.dart';
import 'settings_screen.dart';

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

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller    = TextEditingController();
  final ScrollController       _scrollController = ScrollController();

  late stt.SpeechToText _speech;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker      = ImagePicker();

  JarvisState _currentState = JarvisState.idle;
  String      _listeningText = '';

  File?   _selectedImage;
  String? _base64Image;

  AppSettings _settings = AppSettings();

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

    AppSettings.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  // ─── Orb Colors (black/white/gray) ─────────────────────────────────────────

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

  // ─── Audio ─────────────────────────────────────────────────────────────────

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

  // ─── Image ─────────────────────────────────────────────────────────────────

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

  // ─── Voice ─────────────────────────────────────────────────────────────────

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

  // ─── Send ──────────────────────────────────────────────────────────────────

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

    final url = Uri.parse('https://jarvis-server-nadav.onrender.com/ask-jarvis');

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
        final data        = jsonDecode(response.body);
        final String answer      = data['answer'];
        final String? audioBase64 = data['audio'];

        setState(() => messages.add({'sender': 'jarvis', 'text': answer, 'time': _getCurrentTime()}));

        if (audioBase64 != null && audioBase64.isNotEmpty) {
          _playAudio(audioBase64);
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

  // ─── Settings ──────────────────────────────────────────────────────────────

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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isListening = _currentState == JarvisState.listening;
    final int itemCount    = messages.length + (_currentState == JarvisState.thinking ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              _settings.assistantName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 16),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF9E9E9E)),
            onPressed: _openSettings,
          ),
        ],
      ),

      body: Column(
        children: [

          // ── Orb ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
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

          // ── Messages ─────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              itemCount: itemCount,
              itemBuilder: (context, index) {

                // Thinking bubble
                if (index == messages.length && _currentState == JarvisState.thinking) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(14), topRight: Radius.circular(14),
                          bottomLeft: Radius.circular(14), bottomRight: Radius.circular(0),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9E9E9E)),
                          ),
                          SizedBox(width: 10),
                          Text('מעבד...', style: TextStyle(color: Color(0xFF6E6E6E), fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }

                // Message bubble
                final msg    = messages[index];
                final isUser = msg['sender'] == 'user';

                return Align(
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
                );
              },
            ),
          ),

          // ── Listening text ────────────────────────────────────────────────
          if (isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                _listeningText,
                style: const TextStyle(color: Color(0xFF9E9E9E), fontStyle: FontStyle.italic, fontSize: 13),
              ),
            ),

          // ── Image preview ─────────────────────────────────────────────────
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

          // ── Input bar ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            color: const Color(0xFF1C1C1C),
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
    );
  }
}
