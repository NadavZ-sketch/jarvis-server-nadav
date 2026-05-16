import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'app_settings.dart';
import 'main.dart' show JC, JarvisState;

class LiveTalkScreen extends StatefulWidget {
  final String chatId;
  final AppSettings settings;

  const LiveTalkScreen({
    super.key,
    required this.chatId,
    required this.settings,
  });

  @override
  State<LiveTalkScreen> createState() => _LiveTalkScreenState();
}

class _LiveTalkScreenState extends State<LiveTalkScreen>
    with TickerProviderStateMixin {
  late final stt.SpeechToText _speech;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _wsConnected = false;

  List<Map<String, String>> _messages = [];
  String _partialUser = '';     // STT in-flight
  String _streamingReply = '';  // assistant in-flight (from WS chunks)

  JarvisState _state = JarvisState.idle;
  double _soundLevel = 0;
  String _hint = 'מתחבר...';
  String? _lastTtsPath;

  Timer? _hardCapTimer;
  Timer? _ttsTimeoutTimer;
  bool _disposed = false;

  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _initTts();
    _audioPlayer.onPlayerComplete.listen((_) {
      if (_lastTtsPath != null) {
        File(_lastTtsPath!).delete().catchError((_) => File(''));
        _lastTtsPath = null;
      }
      if (!mounted) return;
      setState(() => _state = JarvisState.idle);
      _listen();
    });

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadHistory();
    final granted = await _ensureMicPermission();
    if (!granted) {
      if (mounted) {
        setState(() => _hint = '🎤 דרושה הרשאת מיקרופון');
      }
      return;
    }
    await _openWebSocket();
    await _listen();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  void _initTts() async {
    final heAvailable = await _flutterTts.isLanguageAvailable('he-IL');
    await _flutterTts.setLanguage(heAvailable == true ? 'he-IL' : 'en-US');
    await _flutterTts.setSpeechRate(0.7);
    await _flutterTts.setVolume(1.0);
    _flutterTts.setCompletionHandler(_onTtsDone);
    _flutterTts.setErrorHandler((_) => _onTtsDone());
  }

  void _onTtsDone() {
    _ttsTimeoutTimer?.cancel();
    _ttsTimeoutTimer = null;
    if (!mounted) return;
    setState(() => _state = JarvisState.idle);
    _listen();
  }

  // ─── History ─────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    try {
      final url = Uri.parse(
        '${widget.settings.serverUrl}/chat-history?limit=60&chatId=${widget.chatId}',
      );
      final r = await http.get(url).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || !mounted) return;
      final List raw = (jsonDecode(r.body)['messages'] ?? []) as List;
      final loaded = raw.map((m) {
        final role = m['role'] as String? ?? 'jarvis';
        final text = m['text'] as String? ?? '';
        return {
          'sender': role == 'user' ? 'user' : 'jarvis',
          'text': text,
        };
      }).toList();
      setState(() => _messages = loaded);
      _scrollToBottom(animated: false);
    } catch (_) {}
  }

  // ─── WebSocket ───────────────────────────────────────────────────────────
  Future<void> _openWebSocket() async {
    final base = widget.settings.serverUrl;
    final wsUrl = base.startsWith('https://')
        ? 'wss://${base.substring(8)}/ws-jarvis'
        : 'ws://${base.substring(7)}/ws-jarvis';
    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSub = _ws!.stream.listen(
        _onWsMessage,
        onError: (_) => _handleWsDown(),
        onDone: _handleWsDown,
        cancelOnError: true,
      );
      _ws!.sink.add(jsonEncode({
        'type': 'hello',
        'chatId': widget.chatId,
        'settings': widget.settings.toJson(),
      }));
    } catch (_) {
      _handleWsDown();
    }
  }

  void _handleWsDown() {
    if (!mounted || _disposed) return;
    _wsConnected = false;
    setState(() => _hint = '⚠️ נותק מהשרת');
  }

  void _onWsMessage(dynamic raw) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'];
    if (type == 'ack') {
      _wsConnected = true;
      if (mounted) setState(() => _hint = 'דבר אליי');
      return;
    }
    if (type == 'thinking') {
      if (!mounted) return;
      setState(() {
        _state = JarvisState.thinking;
        _streamingReply = '';
      });
      return;
    }
    if (type == 'assistant_chunk') {
      if (!mounted) return;
      setState(() {
        _state = JarvisState.speaking;
        _streamingReply += (data['text'] as String? ?? '');
      });
      return;
    }
    if (type == 'assistant_done') {
      final answer = (data['text'] as String? ?? _streamingReply).trim();
      final audio = data['audio'] as String?;
      if (mounted) {
        setState(() {
          if (answer.isNotEmpty) {
            _messages.add({'sender': 'jarvis', 'text': answer});
          }
          _streamingReply = '';
        });
      }
      _scrollToBottom();
      if (audio != null && audio.isNotEmpty && widget.settings.voiceEnabled) {
        _playServerAudio(audio);
      } else if (answer.isNotEmpty && widget.settings.voiceEnabled) {
        _speakText(answer);
      } else {
        _onTtsDone();
      }
      return;
    }
    if (type == 'aborted') {
      if (!mounted) return;
      setState(() {
        _streamingReply = '';
        _state = JarvisState.idle;
      });
      _listen();
      return;
    }
    if (type == 'error') {
      if (!mounted) return;
      setState(() {
        _hint = '⚠️ ${data['message'] ?? 'שגיאה'}';
        _state = JarvisState.idle;
      });
      _listen();
      return;
    }
  }

  void _sendWs(Map<String, dynamic> msg) {
    if (_ws == null || !_wsConnected) return;
    try {
      _ws!.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  // ─── STT (continuous, VAD via pauseFor) ──────────────────────────────────
  Future<void> _listen() async {
    if (_disposed || !mounted) return;
    if (_state == JarvisState.speaking || _state == JarvisState.thinking) return;

    _hardCapTimer?.cancel();
    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final available = await _speech.initialize(
      onError: (_) {
        if (mounted && _state == JarvisState.listening) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _listen();
          });
        }
      },
    );

    if (!available || _disposed || !mounted) return;

    setState(() {
      _state = JarvisState.listening;
      _hint = 'מקשיב...';
      _partialUser = '';
    });

    _speech.listen(
      onResult: (val) {
        if (!mounted || _disposed) return;
        if (!val.finalResult) {
          if (val.recognizedWords.isNotEmpty) {
            setState(() => _partialUser = val.recognizedWords);
          }
          return;
        }
        final text = val.recognizedWords.trim();
        if (text.isNotEmpty) _onUtteranceFinal(text);
      },
      localeId: 'he_IL',
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(milliseconds: 2500),
      onSoundLevelChange: (level) {
        if (!mounted || _disposed) return;
        setState(() => _soundLevel = level);
        if (level > 0 && _hint == 'מקשיב...') {
          setState(() => _hint = 'שומע...');
        }
        // Barge-in: user speaks while assistant is talking → cut TTS + tell server.
        if (widget.settings.bargeInEnabled &&
            level > 1.5 &&
            _state == JarvisState.speaking) {
          _flutterTts.stop();
          _audioPlayer.stop();
          _sendWs({'type': 'barge_in'});
          _onTtsDone();
        }
      },
    );

    _hardCapTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _state == JarvisState.listening) _listen();
    });
  }

  void _onUtteranceFinal(String text) {
    HapticFeedback.lightImpact();
    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _partialUser = '';
      _state = JarvisState.thinking;
      _hint = 'חושב...';
    });
    _scrollToBottom();
    _sendWs({'type': 'user_text', 'text': text});
  }

  // ─── Playback ────────────────────────────────────────────────────────────
  Future<void> _playServerAudio(String base64Audio) async {
    if (!widget.settings.voiceEnabled) {
      _onTtsDone();
      return;
    }
    try {
      setState(() => _state = JarvisState.speaking);
      final bytes = base64Decode(base64Audio);
      final tmpDir = await getTemporaryDirectory();
      final tmpPath =
          '${tmpDir.path}/jarvis_live_${DateTime.now().millisecondsSinceEpoch}.mp3';
      await File(tmpPath).writeAsBytes(bytes);
      _lastTtsPath = tmpPath;
      await _audioPlayer.play(DeviceFileSource(tmpPath));
    } catch (_) {
      _onTtsDone();
    }
  }

  Future<void> _speakText(String text) async {
    setState(() => _state = JarvisState.speaking);
    _ttsTimeoutTimer?.cancel();
    _ttsTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (_state == JarvisState.speaking) _onTtsDone();
    });
    try {
      await _flutterTts.stop();
      final r = await _flutterTts.speak(text);
      if (r != 1) _onTtsDone();
    } catch (_) {
      _onTtsDone();
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _endCall() async {
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _disposed = true;
    _hardCapTimer?.cancel();
    _ttsTimeoutTimer?.cancel();
    _waveController.dispose();
    _speech.stop();
    _flutterTts.stop();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    try {
      _sendWs({'type': 'bye'});
      _wsSub?.cancel();
      _ws?.sink.close();
    } catch (_) {}
    _scrollController.dispose();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'שיחה קולית',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: JC.textSecondary),
          onPressed: _endCall,
        ),
      ),
      body: Stack(
        children: [
          // Ambient glow
          Positioned(
            bottom: -60,
            left: -40,
            right: -40,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    JC.blue500.withValues(alpha: 0.2),
                    JC.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),

          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _LiveBubble(msg: _messages[i]),
                ),
              ),

              // In-flight transcript / partial reply
              if (_partialUser.isNotEmpty || _streamingReply.isNotEmpty)
                _InFlightCard(
                  partialUser: _partialUser,
                  streamingReply: _streamingReply,
                ),

              // Voice wave + hint
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  children: [
                    _VoiceWave(
                      level: _soundLevel,
                      state: _state,
                      controller: _waveController,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _hint,
                      style: TextStyle(
                        color: _state == JarvisState.listening
                            ? JC.blue400
                            : JC.textMuted,
                        fontSize: 13,
                        fontFamily: 'Heebo',
                        fontWeight: _state == JarvisState.listening
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              // End call button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                child: GestureDetector(
                  onTap: _endCall,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Live bubble (minimal, matches main.dart style) ─────────────────────────
class _LiveBubble extends StatelessWidget {
  final Map<String, String> msg;
  const _LiveBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg['sender'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          right: isUser ? 0 : 48,
          left: isUser ? 48 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? JC.userBubble : JC.jarvisBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 18),
          ),
          border: Border.all(
            color: isUser
                ? JC.blue400.withValues(alpha: 0.4)
                : JC.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Text(
          msg['text'] ?? '',
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            color: JC.textPrimary,
            fontSize: 14.5,
            height: 1.55,
            fontFamily: 'Heebo',
          ),
        ),
      ),
    );
  }
}

class _InFlightCard extends StatelessWidget {
  final String partialUser;
  final String streamingReply;
  const _InFlightCard({
    required this.partialUser,
    required this.streamingReply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JC.surfaceAlt.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JC.blue400.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (partialUser.isNotEmpty)
            Text(
              partialUser,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: JC.blue300,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                fontFamily: 'Heebo',
              ),
            ),
          if (partialUser.isNotEmpty && streamingReply.isNotEmpty)
            const SizedBox(height: 6),
          if (streamingReply.isNotEmpty)
            Text(
              streamingReply,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                color: JC.textPrimary,
                fontSize: 14.5,
                height: 1.55,
                fontFamily: 'Heebo',
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Voice wave widget — animated bars driven by mic level ──────────────────
class _VoiceWave extends StatelessWidget {
  final double level;          // 0..~10 (speech_to_text reports up to ~10)
  final JarvisState state;
  final AnimationController controller;

  const _VoiceWave({
    required this.level,
    required this.state,
    required this.controller,
  });

  Color get _color {
    switch (state) {
      case JarvisState.listening: return JC.blue400;
      case JarvisState.thinking:  return JC.indigo300;
      case JarvisState.speaking:  return const Color(0xFF22D3EE);
      default:                    return JC.blue500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final amp = (level.clamp(0.0, 10.0)) / 10.0; // 0..1
    return SizedBox(
      height: 84,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final t = controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(11, (i) {
              final phase = (i / 11) * 2 * math.pi;
              final base = state == JarvisState.idle ? 0.15 : 0.35;
              final speakingBoost = state == JarvisState.speaking ? 0.55 : 0.0;
              final wave = (math.sin(t * 2 * math.pi + phase) + 1) / 2;
              final h = (base + amp * 0.7 + speakingBoost * wave) * 70.0 + 8.0;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: h.clamp(8.0, 78.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _color.withValues(alpha: 0.95),
                      _color.withValues(alpha: 0.55),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
