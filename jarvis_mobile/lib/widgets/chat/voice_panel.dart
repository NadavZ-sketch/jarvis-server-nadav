import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app_settings.dart';
import '../../main.dart' show JC, JarvisState;
import '../../platform/audio_support.dart';
import '../../widgets/jarvis_orb.dart';
import '../../screens/chat/chat_screen.dart' show ChatMessage;

class VoicePanel extends StatefulWidget {
  final String chatId;
  final AppSettings settings;
  final void Function(ChatMessage msg) onNewMessage;
  final List<ChatMessage> messages;

  const VoicePanel({
    super.key,
    required this.chatId,
    required this.settings,
    required this.onNewMessage,
    required this.messages,
  });

  @override
  State<VoicePanel> createState() => VoicePanelState();
}

class VoicePanelState extends State<VoicePanel>
    with TickerProviderStateMixin {
  late final stt.SpeechToText _speech;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();

  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  bool _wsConnected = false;
  bool _sseMode = false;
  Timer? _wsAckTimer;

  String _partialUser = '';
  String _streamingReply = '';

  JarvisState _state = JarvisState.idle;
  double _soundLevel = 0;
  String _hint = 'מתחבר...';
  String? _lastTtsPath;

  Timer? _hardCapTimer;
  Timer? _ttsTimeoutTimer;
  bool _disposed = false;

  int _bargeInFrames = 0;
  static const double _kBargeInThreshold = 4.0;
  static const int _kBargeInFramesRequired = 4;
  static const int _kPostTtsCooldownMs = 500;

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
        deleteTempAudio(_lastTtsPath);
        _lastTtsPath = null;
      }
      if (!mounted) return;
      _onTtsDone();
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final granted = await _ensureMicPermission();
    if (!granted) {
      if (mounted) setState(() => _hint = '🎤 דרושה הרשאת מיקרופון');
      return;
    }
    await _openWebSocket();
    await _listen();
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    return (await Permission.microphone.request()).isGranted;
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
    _bargeInFrames = 0;
    if (!mounted) return;
    setState(() => _state = JarvisState.idle);
    Future.delayed(const Duration(milliseconds: _kPostTtsCooldownMs), () {
      if (mounted && !_disposed) _listen();
    });
  }

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
      _wsAckTimer = Timer(const Duration(seconds: 5), () {
        if (!_wsConnected && !_disposed && mounted) _switchToSse();
      });
    } catch (_) {
      _handleWsDown();
    }
  }

  void _handleWsDown() {
    _wsAckTimer?.cancel();
    if (!mounted || _disposed) return;
    _switchToSse();
  }

  void _switchToSse() {
    _wsConnected = false;
    _sseMode = true;
    try { _wsSub?.cancel(); } catch (_) {}
    try { _ws?.sink.close(); } catch (_) {}
    if (mounted) setState(() => _hint = 'דבר אליי');
  }

  void _onWsMessage(dynamic raw) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw.toString()) as Map<String, dynamic>;
    } catch (_) { return; }

    final type = data['type'];
    if (type == 'ack') {
      _wsAckTimer?.cancel();
      _wsConnected = true;
      _sseMode = false;
      if (mounted) setState(() => _hint = 'דבר אליי');
      return;
    }
    if (type == 'thinking') {
      if (!mounted) return;
      setState(() { _state = JarvisState.thinking; _streamingReply = ''; });
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
      if (mounted) setState(() { _streamingReply = ''; });
      if (answer.isNotEmpty) {
        widget.onNewMessage(ChatMessage(
          id: 'v-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'jarvis',
          text: answer,
          fromVoice: true,
        ));
      }
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
      setState(() { _streamingReply = ''; _state = JarvisState.idle; });
      _listen();
      return;
    }
    if (type == 'error') {
      if (!mounted) return;
      setState(() { _hint = '⚠️ ${data['message'] ?? 'שגיאה'}'; _state = JarvisState.idle; });
      _listen();
      return;
    }
  }

  void _sendWs(Map<String, dynamic> msg) {
    if (_ws == null || !_wsConnected) return;
    try { _ws!.sink.add(jsonEncode(msg)); } catch (_) {}
  }

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
    setState(() { _state = JarvisState.listening; _hint = 'מקשיב...'; _partialUser = ''; });
    _speech.listen(
      onResult: (val) {
        if (!mounted || _disposed) return;
        if (!val.finalResult) {
          if (val.recognizedWords.isNotEmpty) setState(() => _partialUser = val.recognizedWords);
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
        if (level > 2.0 && _hint == 'מקשיב...') setState(() => _hint = 'שומע...');
        if (widget.settings.bargeInEnabled && _state == JarvisState.speaking) {
          if (level > _kBargeInThreshold) {
            _bargeInFrames++;
            if (_bargeInFrames >= _kBargeInFramesRequired) {
              _bargeInFrames = 0;
              _flutterTts.stop();
              _audioPlayer.stop();
              _sendWs({'type': 'barge_in'});
              _onTtsDone();
            }
          } else {
            _bargeInFrames = 0;
          }
        }
      },
    );
    _hardCapTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _state == JarvisState.listening) _listen();
    });
  }

  void _onUtteranceFinal(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.replaceAll(' ', '').length < 2) { _listen(); return; }
    HapticFeedback.lightImpact();
    _hardCapTimer?.cancel();
    widget.onNewMessage(ChatMessage(
      id: 'v-u-${DateTime.now().millisecondsSinceEpoch}',
      sender: 'user',
      text: trimmed,
      fromVoice: true,
    ));
    setState(() { _partialUser = ''; _state = JarvisState.thinking; _hint = 'חושב...'; });
    if (_wsConnected) {
      _sendWs({'type': 'user_text', 'text': trimmed});
    } else {
      _sseMode = true;
      _sendViaSSE(trimmed);
    }
  }

  Future<void> _sendViaSSE(String text) async {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('${widget.settings.serverUrl}/stream-jarvis'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'command': text, 'chatId': widget.chatId, 'settings': widget.settings.toJson()});
      final sr = await client.send(request).timeout(const Duration(seconds: 35));
      if (sr.statusCode == 429) throw Exception('rate_limit');
      if (sr.statusCode != 200) throw Exception('server ${sr.statusCode}');
      String accumulated = '';
      String lineBuffer = '';
      await for (final raw in sr.stream.transform(utf8.decoder)) {
        if (!mounted || _disposed) break;
        lineBuffer += raw;
        while (lineBuffer.contains('\n')) {
          final idx = lineBuffer.indexOf('\n');
          final line = lineBuffer.substring(0, idx).trim();
          lineBuffer = lineBuffer.substring(idx + 1);
          if (!line.startsWith('data: ')) continue;
          try {
            final data = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            if (data['error'] != null) throw Exception(data['error']);
            if (data['chunk'] is String) {
              accumulated += data['chunk'] as String;
              if (mounted) setState(() => _streamingReply = accumulated);
            }
            if (data['done'] == true) {
              final answer = accumulated.trim();
              if (mounted) setState(() => _streamingReply = '');
              if (answer.isNotEmpty) {
                widget.onNewMessage(ChatMessage(
                  id: 'v-${DateTime.now().millisecondsSinceEpoch}',
                  sender: 'jarvis',
                  text: answer,
                  fromVoice: true,
                ));
              }
              if (answer.isNotEmpty && widget.settings.voiceEnabled) {
                _speakText(answer);
              } else {
                _onTtsDone();
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      if (!mounted) return;
      final err = e.toString();
      final msg = err.contains('rate_limit') ? '⏳ עמוס כרגע, נסה שוב'
                : err.contains('timeout')    ? '⏱ זמן פג'
                :                             '⚠️ שגיאת חיבור';
      setState(() { _hint = msg; _streamingReply = ''; _state = JarvisState.idle; });
      _listen();
    } finally {
      client.close();
    }
  }

  Future<void> _playServerAudio(String base64Audio) async {
    if (!widget.settings.voiceEnabled) { _onTtsDone(); return; }
    try {
      setState(() => _state = JarvisState.speaking);
      final bytes = base64Decode(base64Audio);
      _lastTtsPath = await playBase64Audio(_audioPlayer, bytes);
    } catch (_) {
      _onTtsDone();
    }
  }

  String _stripMarkdown(String text) => text
      .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
      .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
      .replaceAll(RegExp(r'`[^`]+`'), '')
      .replaceAll(RegExp(r'#{1,6}\s+'), '')
      .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
      .replaceAll(RegExp(r'^[-•*]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\n{2,}'), '. ')
      .replaceAll('\n', ' ')
      .trim();

  Future<void> _speakText(String text) async {
    setState(() => _state = JarvisState.speaking);
    text = _stripMarkdown(text);
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

  /// Called by ChatScreen when switching away from voice mode.
  void stopVoice() {
    _hardCapTimer?.cancel();
    _ttsTimeoutTimer?.cancel();
    _speech.stop();
    _flutterTts.stop();
    _audioPlayer.stop();
    if (mounted) setState(() { _state = JarvisState.idle; _hint = 'דבר אליי'; });
  }

  /// Called by ChatScreen when switching back to voice mode.
  void resumeVoice() {
    if (!_disposed && mounted) _listen();
  }

  @override
  void dispose() {
    _disposed = true;
    _hardCapTimer?.cancel();
    _ttsTimeoutTimer?.cancel();
    _wsAckTimer?.cancel();
    _waveController.dispose();
    _speech.stop();
    _flutterTts.stop();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    if (_lastTtsPath != null) { deleteTempAudio(_lastTtsPath); _lastTtsPath = null; }
    try { _sendWs({'type': 'bye'}); _wsSub?.cancel(); _ws?.sink.close(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('voice'),
      children: [
        Positioned(
          bottom: -60, left: -40, right: -40,
          child: Container(
            height: 320,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.8,
                colors: [JC.blue500.withValues(alpha: 0.2), JC.bg.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Column(
          children: [
            Expanded(child: const SizedBox.shrink()),
            if (_partialUser.isNotEmpty || _streamingReply.isNotEmpty)
              _InFlightCard(partialUser: _partialUser, streamingReply: _streamingReply),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                children: [
                  JarvisOrb(
                    state: _state,
                    level: _soundLevel,
                    size: 220,
                    baseColorOverride: widget.settings.orbCustomColors
                        ? Color(widget.settings.orbBaseColor) : null,
                    tipColorOverride: widget.settings.orbCustomColors
                        ? Color(widget.settings.orbTipColor) : null,
                    voiceSensitivity: widget.settings.orbVoiceSensitivity,
                    rotationSensitivity: widget.settings.orbRotationSensitivity,
                    explosionEnabled: widget.settings.orbExplosionEnabled,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _hint,
                    style: TextStyle(
                      color: _state == JarvisState.listening ? JC.blue400 : JC.textMuted,
                      fontSize: 13,
                      fontFamily: 'Heebo',
                      fontWeight: _state == JarvisState.listening
                          ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                      blurRadius: 18, offset: const Offset(0, 4),
                    )],
                  ),
                  child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InFlightCard extends StatelessWidget {
  final String partialUser;
  final String streamingReply;
  const _InFlightCard({required this.partialUser, required this.streamingReply});

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
          if (partialUser.isNotEmpty) Text(partialUser, textDirection: TextDirection.rtl,
            style: TextStyle(color: JC.blue300, fontSize: 14, fontStyle: FontStyle.italic, fontFamily: 'Heebo')),
          if (partialUser.isNotEmpty && streamingReply.isNotEmpty) const SizedBox(height: 6),
          if (streamingReply.isNotEmpty) Text(streamingReply, textDirection: TextDirection.rtl,
            style: TextStyle(color: JC.textPrimary, fontSize: 14.5, height: 1.55, fontFamily: 'Heebo')),
        ],
      ),
    );
  }
}
