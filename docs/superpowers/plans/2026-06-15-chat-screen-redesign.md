# Chat Screen Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the voice-only LiveTalkScreen with a unified screen combining a voice panel (orb) and a text panel (bubbles + input + file uploads), toggled by a segmented button in the top bar.

**Architecture:** `ChatScreen` is a thin shell that owns a shared `List<ChatMessage>` and a `ChatMode` toggle. `VoicePanel` contains all the existing STT/TTS/WebSocket logic (moved from `LiveTalkScreen`). `TextPanel` is a new widget with `AnimatedList` bubbles, a text field, tap-to-toggle mic, and file attachment. `live_talk_screen.dart` becomes a one-line wrapper so existing navigation call sites need no changes.

**Tech Stack:** Flutter (Material 3 `SegmentedButton`, `AnimatedList`, `AnimatedSwitcher`, `AnimatedSize`, `ScaleTransition`), `speech_to_text`, `flutter_tts`, `audioplayers`, `image_picker`, `file_picker` (new), Node.js `pdf-parse` (existing), `mammoth` (new), Express.js.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `jarvis_mobile/lib/screens/chat/chat_screen.dart` | Shell: top bar, mode, shared messages, animated panel switcher |
| Create | `jarvis_mobile/lib/widgets/chat/voice_panel.dart` | All STT/TTS/WS/SSE logic + JarvisOrb display |
| Create | `jarvis_mobile/lib/widgets/chat/text_panel.dart` | Bubble list, text input, mic toggle, file attachment |
| Modify | `jarvis_mobile/lib/live_talk_screen.dart` | Thin wrapper → `ChatScreen` |
| Modify | `jarvis_mobile/lib/services/api_service.dart` | Add `askJarvisWithImage`, `transcribeAudio`, `parseDocument` |
| Modify | `jarvis_mobile/pubspec.yaml` | Add `file_picker: ^8.0.0` |
| Modify | `server.js` | Add `POST /parse-document` endpoint |
| Modify | `package.json` | Add `mammoth` dependency |
| Create | `tests/unit/parseDocument.test.js` | Unit tests for the new endpoint |

---

## Task 1: Backend — `POST /parse-document`

**Files:**
- Modify: `server.js`
- Modify: `package.json`
- Create: `tests/unit/parseDocument.test.js`

- [ ] **Step 1: Install mammoth**

```bash
npm install mammoth
```

Expected: `package.json` gains `"mammoth": "^1.x.x"` under `dependencies`.

- [ ] **Step 2: Write the failing test**

Create `tests/unit/parseDocument.test.js`:

```javascript
'use strict';

jest.mock('node-cron', () => ({ schedule: jest.fn() }));
jest.mock('nodemailer', () => ({ createTransport: jest.fn().mockReturnValue({ sendMail: jest.fn() }) }));
jest.mock('openai', () => ({ OpenAI: jest.fn().mockImplementation(() => ({ audio: { transcriptions: { create: jest.fn() } } })), toFile: jest.fn() }));
jest.mock('google-tts-api', () => ({ getAllAudioBase64: jest.fn().mockResolvedValue([{ base64: '' }]) }));
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn().mockReturnValue({ from: jest.fn() }) }));
jest.mock('../../services/obsidianSync', () => ({ initSync: jest.fn(), fullSyncFromDb: jest.fn(), appendChatMessage: jest.fn(), syncAll: jest.fn() }));
jest.mock('../../services/weatherSource', () => ({ getWeatherSummary: jest.fn().mockResolvedValue(null) }));
jest.mock('../../services/newsSource', () => ({ getNewsSummary: jest.fn().mockResolvedValue(null), getTopicHeadlines: jest.fn().mockResolvedValue(null) }));
jest.mock('../../agents/models', () => ({ callGemma4: jest.fn(), callGemma4Stream: jest.fn() }));

// Mock pdf-parse and mammoth so tests don't need real files.
jest.mock('pdf-parse', () => jest.fn());
jest.mock('mammoth', () => ({ extractRawText: jest.fn() }));

const request = require('supertest');
const pdfParse = require('pdf-parse');
const mammoth = require('mammoth');
const { app } = require('../../server');

describe('POST /parse-document', () => {
    beforeEach(() => jest.clearAllMocks());

    it('returns 400 when no fileBase64 provided', async () => {
        const res = await request(app).post('/parse-document').send({ fileType: 'pdf' });
        expect(res.status).toBe(400);
        expect(res.body).toHaveProperty('error');
    });

    it('parses PDF and returns text', async () => {
        pdfParse.mockResolvedValue({ text: 'שלום עולם', numpages: 1 });
        const fakeBase64 = Buffer.from('fake-pdf').toString('base64');
        const res = await request(app).post('/parse-document').send({
            fileBase64: fakeBase64,
            fileType: 'pdf',
        });
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('text', 'שלום עולם');
        expect(res.body).toHaveProperty('pages', 1);
    });

    it('parses docx and returns text', async () => {
        mammoth.extractRawText.mockResolvedValue({ value: 'תוכן מסמך' });
        const fakeBase64 = Buffer.from('fake-docx').toString('base64');
        const res = await request(app).post('/parse-document').send({
            fileBase64: fakeBase64,
            fileType: 'docx',
        });
        expect(res.status).toBe(200);
        expect(res.body).toHaveProperty('text', 'תוכן מסמך');
    });

    it('returns error for unsupported file type', async () => {
        const res = await request(app).post('/parse-document').send({
            fileBase64: 'aGVsbG8=',
            fileType: 'xlsx',
        });
        expect(res.status).toBe(400);
        expect(res.body.error).toMatch(/סוג קובץ/);
    });

    it('truncates text longer than 8000 chars', async () => {
        const longText = 'א'.repeat(10000);
        pdfParse.mockResolvedValue({ text: longText, numpages: 50 });
        const res = await request(app).post('/parse-document').send({
            fileBase64: Buffer.from('x').toString('base64'),
            fileType: 'pdf',
        });
        expect(res.status).toBe(200);
        expect(res.body.text.length).toBeLessThanOrEqual(8000);
    });
});
```

- [ ] **Step 3: Run to verify it fails**

```bash
npx jest tests/unit/parseDocument.test.js --verbose 2>&1 | tail -20
```

Expected: FAIL — "Cannot find module" or 404 on POST /parse-document.

- [ ] **Step 4: Add the endpoint to `server.js`**

Find the line `// ─── Whisper STT` (~line 588) and add the following **before** it:

```javascript
// ─── Document Parser ──────────────────────────────────────────────────────────

app.post('/parse-document', _rl(5), async (req, res) => {
    const { fileBase64, fileType } = req.body;
    if (!fileBase64) return res.status(400).json({ error: 'fileBase64 required' });
    const type = (fileType || '').toLowerCase().replace('.', '');
    if (!['pdf', 'docx'].includes(type)) {
        return res.status(400).json({ error: `סוג קובץ לא נתמך: ${type}. השתמש ב-pdf או docx.` });
    }
    try {
        const buffer = Buffer.from(fileBase64, 'base64');
        let text = '';
        let pages;
        if (type === 'pdf') {
            const pdfParse = require('pdf-parse');
            const result = await pdfParse(buffer);
            text = (result.text || '').trim();
            pages = result.numpages;
        } else {
            const mammoth = require('mammoth');
            const result = await mammoth.extractRawText({ buffer });
            text = (result.value || '').trim();
        }
        if (!text) return res.status(422).json({ error: 'לא ניתן לחלץ טקסט מהקובץ' });
        const truncated = text.slice(0, 8000);
        const wordCount = truncated.split(/\s+/).filter(Boolean).length;
        res.json({ text: truncated, ...(pages !== undefined && { pages }), wordCount });
    } catch (err) {
        console.error('❌ parse-document error:', err.message);
        res.status(500).json({ error: 'לא ניתן לקרוא את הקובץ' });
    }
});
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
npx jest tests/unit/parseDocument.test.js --verbose 2>&1 | tail -20
```

Expected: `5 passed, 5 total`

- [ ] **Step 6: Commit**

```bash
git add server.js package.json package-lock.json tests/unit/parseDocument.test.js
git commit -m "feat: add POST /parse-document endpoint for PDF and DOCX text extraction"
```

---

## Task 2: ApiService — new methods

**Files:**
- Modify: `jarvis_mobile/lib/services/api_service.dart`

- [ ] **Step 1: Add `file_picker` to pubspec.yaml**

In `jarvis_mobile/pubspec.yaml`, under `dependencies:` after `image_picker: ^1.2.1`, add:

```yaml
  file_picker: ^8.0.0
```

Then run:

```bash
cd jarvis_mobile && flutter pub get 2>&1 | tail -5
```

Expected: `Got dependencies!`

- [ ] **Step 2: Add three new methods to `api_service.dart`**

Open `jarvis_mobile/lib/services/api_service.dart`. After the existing `askJarvis` method (around line 324), add:

```dart
  Future<Map<String, dynamic>> askJarvisWithImage(
      String command, String imageBase64, AppSettings settings) async {
    final body = <String, dynamic>{
      'command': command,
      'imageBase64': imageBase64,
      'settings': settings.toJson(),
    };
    final res = await _client
        .post(
          _uri('/ask-jarvis'),
          headers: _headers({'Content-Type': 'application/json'}),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    return jsonDecode(_safeBody(res)) as Map<String, dynamic>;
  }

  Future<String> transcribeAudio(List<int> bytes, String format) async {
    final base64Audio = base64Encode(bytes);
    final res = await _client
        .post(
          _uri('/transcribe'),
          headers: _headers({'Content-Type': 'application/json'}),
          body: jsonEncode({'audio': base64Audio, 'format': format}),
        )
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return (data['text'] as String? ?? '').trim();
  }

  Future<String> parseDocument(List<int> bytes, String fileType) async {
    final base64File = base64Encode(bytes);
    final res = await _client
        .post(
          _uri('/parse-document'),
          headers: _headers({'Content-Type': 'application/json'}),
          body: jsonEncode({'fileBase64': base64File, 'fileType': fileType}),
        )
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return (data['text'] as String? ?? '').trim();
  }
```

Verify `dart:convert` is already imported (it is — `api_service.dart` already uses `jsonDecode`/`jsonEncode`/`base64Encode`).

- [ ] **Step 3: Verify the app still builds**

```bash
cd jarvis_mobile && flutter analyze lib/services/api_service.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add jarvis_mobile/pubspec.yaml jarvis_mobile/pubspec.lock jarvis_mobile/lib/services/api_service.dart
git commit -m "feat: add ApiService.askJarvisWithImage, transcribeAudio, parseDocument methods"
```

---

## Task 3: `ChatMessage` model + `ChatScreen` shell

**Files:**
- Create: `jarvis_mobile/lib/screens/chat/chat_screen.dart`

- [ ] **Step 1: Create the directory and file**

```bash
mkdir -p /home/user/jarvis-server-nadav/jarvis_mobile/lib/screens/chat
```

- [ ] **Step 2: Write `chat_screen.dart`**

Create `jarvis_mobile/lib/screens/chat/chat_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../home/home_dialogs.dart' show showAddReminderDialog;
import '../../screens/home/home_controller.dart' show HomeController;

// ─── Data model ──────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String sender; // 'user' | 'jarvis'
  final String text;
  final bool fromVoice;
  final String? fileName;
  final DateTime at;

  ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.fromVoice = false,
    this.fileName,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  static ChatMessage fromLegacy(Map<String, dynamic> m) => ChatMessage(
        id: UniqueKey().toString(),
        sender: (m['sender'] as String? ?? 'jarvis'),
        text: (m['text'] as String? ?? ''),
        fromVoice: m['fromVoice'] as bool? ?? false,
      );
}

// ─── Mode enum ────────────────────────────────────────────────────────────────

enum ChatMode { voice, text }

// ─── Shell ────────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  final String chatId;
  final AppSettings settings;
  final List<Map<String, dynamic>>? initialMessages;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.settings,
    this.initialMessages,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  ChatMode _mode = ChatMode.voice;

  // Keys so AnimatedSwitcher can distinguish the two panels.
  static const _voiceKey = ValueKey('voice');
  static const _textKey  = ValueKey('text');

  @override
  void initState() {
    super.initState();
    if (widget.initialMessages != null) {
      _messages.addAll(widget.initialMessages!.map(ChatMessage.fromLegacy));
    }
  }

  void _addMessage(ChatMessage msg) {
    if (!mounted) return;
    setState(() => _messages.add(msg));
  }

  void _switchMode(ChatMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ג׳רביס',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: JC.textSecondary),
          onPressed: () => Navigator.of(context)
              .pop(_messages.map((m) => {'sender': m.sender, 'text': m.text}).toList()),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: SegmentedButton<ChatMode>(
              segments: const [
                ButtonSegment(value: ChatMode.voice, label: Text('🎤 קול')),
                ButtonSegment(value: ChatMode.text,  label: Text('💬 טקסט')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _switchMode(s.first),
              style: ButtonStyle(
                textStyle: WidgetStateProperty.all(const TextStyle(
                  fontFamily: 'Heebo', fontSize: 12,
                )),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == (_mode == ChatMode.voice ? _voiceKey : _textKey);
          final offset = isIncoming
              ? Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(animation)
              : Tween(begin: Offset.zero, end: const Offset(0, 0.08)).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: _mode == ChatMode.voice
            ? _buildVoicePanel()
            : _buildTextPanel(),
      ),
    );
  }

  Widget _buildVoicePanel() {
    // VoicePanel is wired in Task 4.
    return const SizedBox.expand(key: _voiceKey);
  }

  Widget _buildTextPanel() {
    // TextPanel is wired in Task 5.
    return const SizedBox.expand(key: _textKey);
  }
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd jarvis_mobile && flutter analyze lib/screens/chat/chat_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!` (warnings about unused imports are OK if they'll be used in later tasks).

- [ ] **Step 4: Commit**

```bash
git add jarvis_mobile/lib/screens/chat/chat_screen.dart
git commit -m "feat: add ChatScreen shell with ChatMessage model and mode toggle"
```

---

## Task 4: `VoicePanel` — extract from `LiveTalkScreen`

**Files:**
- Create: `jarvis_mobile/lib/widgets/chat/voice_panel.dart`

The voice panel is the body of `LiveTalkScreen` with one change: instead of appending to its own `_messages` list, it calls `onNewMessage` on the parent.

- [ ] **Step 1: Create directory and file**

```bash
mkdir -p /home/user/jarvis-server-nadav/jarvis_mobile/lib/widgets/chat
```

Create `jarvis_mobile/lib/widgets/chat/voice_panel.dart`:

```dart
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
import '../chat/chat_screen.dart' show ChatMessage;

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
        // Ambient glow
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
            Expanded(child: const SizedBox.shrink()), // spacer
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
```

- [ ] **Step 2: Wire `VoicePanel` into `ChatScreen`**

In `jarvis_mobile/lib/screens/chat/chat_screen.dart`, add the import and replace `_buildVoicePanel()`:

```dart
// Add at top of imports:
import '../../widgets/chat/voice_panel.dart';

// Replace the placeholder _buildVoicePanel method:
final GlobalKey<VoicePanelState> _voicePanelKey = GlobalKey();

Widget _buildVoicePanel() {
  return VoicePanel(
    key: _voicePanelKey,
    chatId: widget.chatId,
    settings: widget.settings,
    messages: _messages,
    onNewMessage: _addMessage,
  );
}
```

Also update `_switchMode` to stop/resume voice when switching:

```dart
void _switchMode(ChatMode mode) {
  if (mode == _mode) return;
  if (_mode == ChatMode.voice) {
    _voicePanelKey.currentState?.stopVoice();
  }
  setState(() => _mode = mode);
  if (mode == ChatMode.voice) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _voicePanelKey.currentState?.resumeVoice();
    });
  }
}
```

- [ ] **Step 3: Verify compilation**

```bash
cd jarvis_mobile && flutter analyze lib/screens/chat/ lib/widgets/chat/voice_panel.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add jarvis_mobile/lib/widgets/chat/voice_panel.dart jarvis_mobile/lib/screens/chat/chat_screen.dart
git commit -m "feat: add VoicePanel widget extracted from LiveTalkScreen"
```

---

## Task 5: `TextPanel` — bubbles + text send + mic

**Files:**
- Create: `jarvis_mobile/lib/widgets/chat/text_panel.dart`

- [ ] **Step 1: Create `text_panel.dart`**

Create `jarvis_mobile/lib/widgets/chat/text_panel.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';
import '../chat/chat_screen.dart' show ChatMessage;

class TextPanel extends StatefulWidget {
  final List<ChatMessage> messages;
  final AppSettings settings;
  final String chatId;
  final void Function(ChatMessage msg) onNewMessage;

  const TextPanel({
    super.key,
    required this.messages,
    required this.settings,
    required this.chatId,
    required this.onNewMessage,
  });

  @override
  State<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends State<TextPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey();
  late final ApiService _api;

  // Mic animation
  late final AnimationController _micCtrl;
  late final Animation<double> _micScale;
  bool _micRecording = false;
  late final stt.SpeechToText _speech;

  bool _sending = false;
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _speech = stt.SpeechToText();
    _prevCount = widget.messages.length;

    _micCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _micScale = Tween<double>(begin: 1.0, end: 1.3)
        .animate(CurvedAnimation(parent: _micCtrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(TextPanel old) {
    super.didUpdateWidget(old);
    // Animate new messages as they arrive from the parent.
    final newCount = widget.messages.length;
    if (newCount > _prevCount) {
      for (var i = _prevCount; i < newCount; i++) {
        _listKey.currentState?.insertItem(i,
            duration: const Duration(milliseconds: 200));
      }
      _prevCount = newCount;
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _textCtrl.clear();
    setState(() => _sending = true);

    final userMsg = ChatMessage(
      id: 't-u-${DateTime.now().millisecondsSinceEpoch}',
      sender: 'user',
      text: text,
    );
    widget.onNewMessage(userMsg);

    try {
      final result = await _api.askJarvis(text, widget.settings);
      final answer = (result['answer'] as String? ?? '').trim();
      if (answer.isNotEmpty) {
        widget.onNewMessage(ChatMessage(
          id: 't-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'jarvis',
          text: answer,
        ));
      }
    } catch (_) {
      widget.onNewMessage(ChatMessage(
        id: 't-err-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'jarvis',
        text: '⚠️ שגיאת חיבור',
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleMic() async {
    if (_micRecording) {
      // Second tap: stop + send
      await _speech.stop();
      _micCtrl.stop();
      _micCtrl.reset();
      if (mounted) setState(() => _micRecording = false);
      return;
    }
    // First tap: start one-shot STT
    final available = await _speech.initialize();
    if (!available) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('מיקרופון לא זמין')));
      return;
    }
    if (mounted) setState(() => _micRecording = true);
    _micCtrl.repeat(reverse: true);

    _speech.listen(
      onResult: (val) {
        if (!val.finalResult) return;
        final text = val.recognizedWords.trim();
        _micCtrl.stop();
        _micCtrl.reset();
        if (mounted) setState(() => _micRecording = false);
        if (text.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('לא זוהה דיבור')));
          return;
        }
        _textCtrl.text = text;
        _sendText();
      },
      localeId: 'he_IL',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _micCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('text'),
      children: [
        Expanded(
          child: AnimatedList(
            key: _listKey,
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            initialItemCount: widget.messages.length,
            itemBuilder: (context, index, animation) {
              final msg = widget.messages[index];
              return _BubbleEntry(msg: msg, animation: animation);
            },
          ),
        ),
        _InputBar(
          controller: _textCtrl,
          micRecording: _micRecording,
          micScale: _micScale,
          sending: _sending,
          onSend: _sendText,
          onMic: _toggleMic,
        ),
      ],
    );
  }
}

// ─── Animated bubble entry ───────────────────────────────────────────────────

class _BubbleEntry extends StatelessWidget {
  final ChatMessage msg;
  final Animation<double> animation;
  const _BubbleEntry({required this.msg, required this.animation});

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: animation,
        child: _Bubble(msg: msg),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.sender == 'user';
    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Container(
        margin: EdgeInsetsDirectional.only(
          bottom: 10,
          start: isUser ? 0 : 48,
          end: isUser ? 48 : 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? JC.userBubble : JC.jarvisBubble,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(18),
            topEnd: const Radius.circular(18),
            bottomStart: Radius.circular(isUser ? 6 : 18),
            bottomEnd: Radius.circular(isUser ? 18 : 6),
          ),
          border: Border.all(
            color: isUser
                ? JC.blue400.withValues(alpha: 0.4)
                : JC.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.fromVoice)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Text(
                  '🎤',
                  style: TextStyle(fontSize: 10, color: JC.indigo500),
                ),
              ),
            Text(
              msg.text,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: JC.textPrimary,
                fontSize: 14.5,
                height: 1.55,
                fontFamily: 'Heebo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Input bar (no file attachment yet — added in Task 6) ───────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool micRecording;
  final Animation<double> micScale;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;

  const _InputBar({
    required this.controller,
    required this.micRecording,
    required this.micScale,
    required this.sending,
    required this.onSend,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      decoration: BoxDecoration(
        color: JC.bg,
        border: Border(top: BorderSide(color: JC.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Mic button with pulse animation
          ScaleTransition(
            scale: micScale,
            child: GestureDetector(
              onTap: onMic,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: micRecording
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: micRecording
                        ? Colors.red.withValues(alpha: 0.6)
                        : JC.border,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 18,
                  color: micRecording ? Colors.red : JC.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Text field
          Expanded(
            child: TextField(
              controller: controller,
              textDirection: TextDirection.rtl,
              onSubmitted: (_) => onSend(),
              style: TextStyle(color: JC.textPrimary, fontSize: 14, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: 'כתוב הודעה...',
                hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                filled: true,
                fillColor: JC.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sending ? JC.border : JC.indigo500,
              ),
              child: sending
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: JC.textPrimary,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Wire `TextPanel` into `ChatScreen`**

In `jarvis_mobile/lib/screens/chat/chat_screen.dart`, add the import and replace `_buildTextPanel()`:

```dart
// Add import:
import '../../widgets/chat/text_panel.dart';

// Replace placeholder:
Widget _buildTextPanel() {
  return TextPanel(
    key: const ValueKey('text'),
    messages: _messages,
    settings: widget.settings,
    chatId: widget.chatId,
    onNewMessage: _addMessage,
  );
}
```

- [ ] **Step 3: Verify compilation**

```bash
cd jarvis_mobile && flutter analyze lib/widgets/chat/text_panel.dart lib/screens/chat/chat_screen.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add jarvis_mobile/lib/widgets/chat/text_panel.dart jarvis_mobile/lib/screens/chat/chat_screen.dart
git commit -m "feat: add TextPanel with AnimatedList bubbles, text send, mic tap-to-toggle"
```

---

## Task 6: File Attachment

**Files:**
- Modify: `jarvis_mobile/lib/widgets/chat/text_panel.dart`

Add the 📎 button, bottom sheet, preview row, and file send logic to `TextPanel`.

- [ ] **Step 1: Add imports to `text_panel.dart`**

At the top of `text_panel.dart`, add:

```dart
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
```

- [ ] **Step 2: Add `_pendingFile` state and file-send logic to `_TextPanelState`**

Inside `_TextPanelState`, add these fields after `bool _sending = false;`:

```dart
String? _pendingFileName;
List<int>? _pendingFileBytes;
String? _pendingFileType; // 'image' | 'pdf' | 'docx' | 'audio'
```

Add these methods inside `_TextPanelState`:

```dart
void _clearPendingFile() {
  setState(() {
    _pendingFileName = null;
    _pendingFileBytes = null;
    _pendingFileType = null;
  });
}

Future<void> _showAttachmentSheet() async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: JC.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32, height: 3,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: JC.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(Icons.image_rounded, color: JC.blue400),
            title: Text('📷 תמונה', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
            onTap: () => Navigator.pop(context, 'image'),
          ),
          ListTile(
            leading: Icon(Icons.description_rounded, color: JC.indigo500),
            title: Text('📄 מסמך (PDF / Word)', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
            onTap: () => Navigator.pop(context, 'doc'),
          ),
          ListTile(
            leading: Icon(Icons.audiotrack_rounded, color: const Color(0xFF22C55E)),
            title: Text('🎵 אודיו', style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
            onTap: () => Navigator.pop(context, 'audio'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !mounted) return;

  if (choice == 'image') {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _pendingFileName = picked.name;
      _pendingFileBytes = bytes;
      _pendingFileType = 'image';
    });
  } else if (choice == 'doc') {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    setState(() {
      _pendingFileName = file.name;
      _pendingFileBytes = file.bytes;
      _pendingFileType = file.extension?.toLowerCase() == 'docx' ? 'docx' : 'pdf';
    });
  } else if (choice == 'audio') {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    setState(() {
      _pendingFileName = file.name;
      _pendingFileBytes = file.bytes;
      _pendingFileType = 'audio:${file.extension ?? 'mp3'}';
    });
  }
}

Future<void> _sendWithFile() async {
  final bytes = _pendingFileBytes;
  final fileType = _pendingFileType;
  final caption = _textCtrl.text.trim();
  if (bytes == null || fileType == null) return;
  _textCtrl.clear();
  _clearPendingFile();
  setState(() => _sending = true);

  final displayName = _pendingFileName ?? 'קובץ';
  widget.onNewMessage(ChatMessage(
    id: 't-u-${DateTime.now().millisecondsSinceEpoch}',
    sender: 'user',
    text: caption.isNotEmpty ? caption : '📎 $displayName',
    fileName: displayName,
  ));

  try {
    String command = caption.isNotEmpty ? caption : 'נתח את הקובץ הזה';
    String? answer;

    if (fileType == 'image') {
      final base64 = base64Encode(bytes);
      final result = await _api.askJarvisWithImage(command, base64, widget.settings);
      answer = result['answer'] as String?;
    } else if (fileType.startsWith('audio:')) {
      final format = fileType.split(':').last;
      final transcript = await _api.transcribeAudio(bytes, format);
      if (transcript.isEmpty) throw Exception('לא זוהה תוכן');
      final result = await _api.askJarvis('תמלול: $transcript\n\n$command', widget.settings);
      answer = result['answer'] as String?;
    } else {
      // pdf or docx
      final text = await _api.parseDocument(bytes, fileType);
      final result = await _api.askJarvis('תוכן הקובץ:\n$text\n\n$command', widget.settings);
      answer = result['answer'] as String?;
    }

    if ((answer ?? '').isNotEmpty) {
      widget.onNewMessage(ChatMessage(
        id: 't-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'jarvis',
        text: answer!.trim(),
      ));
    }
  } catch (e) {
    widget.onNewMessage(ChatMessage(
      id: 't-err-${DateTime.now().millisecondsSinceEpoch}',
      sender: 'jarvis',
      text: '⚠️ ${e.toString().replaceFirst('Exception: ', '')}',
    ));
  } finally {
    if (mounted) setState(() => _sending = false);
  }
}
```

Update `_sendText` to route through `_sendWithFile` when a file is pending:

```dart
Future<void> _sendText() async {
  if (_pendingFileBytes != null) { await _sendWithFile(); return; }
  // ... rest of existing _sendText unchanged
}
```

- [ ] **Step 3: Update `build` to show preview row and 📎 button**

Replace the `build` method's `Column` children in `_TextPanelState`:

```dart
@override
Widget build(BuildContext context) {
  return Column(
    key: const ValueKey('text'),
    children: [
      Expanded(
        child: AnimatedList(
          key: _listKey,
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          initialItemCount: widget.messages.length,
          itemBuilder: (context, index, animation) {
            final msg = widget.messages[index];
            return _BubbleEntry(msg: msg, animation: animation);
          },
        ),
      ),
      // File preview row (AnimatedSize hides/shows smoothly)
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: _pendingFileName == null
            ? const SizedBox.shrink()
            : _FilePreviewRow(
                fileName: _pendingFileName!,
                onDismiss: _clearPendingFile,
              ),
      ),
      _InputBar(
        controller: _textCtrl,
        micRecording: _micRecording,
        micScale: _micScale,
        sending: _sending,
        onSend: _sendText,
        onMic: _toggleMic,
        onAttach: _showAttachmentSheet,
      ),
    ],
  );
}
```

- [ ] **Step 4: Add `_FilePreviewRow` widget at the bottom of `text_panel.dart`**

```dart
class _FilePreviewRow extends StatelessWidget {
  final String fileName;
  final VoidCallback onDismiss;
  const _FilePreviewRow({required this.fileName, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.indigo500.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_file_rounded, size: 16, color: JC.indigo500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
              style: TextStyle(color: JC.textSecondary, fontSize: 12, fontFamily: 'Heebo'),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 16, color: JC.textMuted),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Add `onAttach` to `_InputBar`**

Update `_InputBar` to accept and show a 📎 button:

```dart
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool micRecording;
  final Animation<double> micScale;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final VoidCallback onAttach; // NEW

  const _InputBar({
    required this.controller,
    required this.micRecording,
    required this.micScale,
    required this.sending,
    required this.onSend,
    required this.onMic,
    required this.onAttach, // NEW
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      decoration: BoxDecoration(
        color: JC.bg,
        border: Border(top: BorderSide(color: JC.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Attachment button
          GestureDetector(
            onTap: onAttach,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.attach_file_rounded, size: 22, color: JC.textSecondary),
            ),
          ),
          const SizedBox(width: 4),
          // Mic button with pulse animation
          ScaleTransition(
            scale: micScale,
            child: GestureDetector(
              onTap: onMic,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: micRecording
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: micRecording
                        ? Colors.red.withValues(alpha: 0.6)
                        : JC.border,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 18,
                  color: micRecording ? Colors.red : JC.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textDirection: TextDirection.rtl,
              onSubmitted: (_) => onSend(),
              style: TextStyle(color: JC.textPrimary, fontSize: 14, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: 'כתוב הודעה...',
                hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                filled: true,
                fillColor: JC.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: sending ? JC.border : JC.indigo500,
              ),
              child: sending
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: JC.textPrimary),
                    )
                  : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Verify compilation**

```bash
cd jarvis_mobile && flutter analyze lib/widgets/chat/text_panel.dart 2>&1 | tail -10
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add jarvis_mobile/lib/widgets/chat/text_panel.dart
git commit -m "feat: add file attachment (image/doc/audio) with preview row and AnimatedSize"
```

---

## Task 7: Wire `live_talk_screen.dart` as wrapper + push to remote

**Files:**
- Modify: `jarvis_mobile/lib/live_talk_screen.dart`

- [ ] **Step 1: Replace `live_talk_screen.dart` with a thin wrapper**

Replace the entire contents of `jarvis_mobile/lib/live_talk_screen.dart` with:

```dart
// Thin wrapper — preserves all existing navigation call sites unchanged.
// All logic has moved to ChatScreen + VoicePanel + TextPanel.
export 'screens/chat/chat_screen.dart' show ChatScreen;

import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'screens/chat/chat_screen.dart';

class LiveTalkScreen extends StatelessWidget {
  final String chatId;
  final AppSettings settings;
  final List<Map<String, dynamic>>? initialMessages;

  const LiveTalkScreen({
    super.key,
    required this.chatId,
    required this.settings,
    this.initialMessages,
  });

  @override
  Widget build(BuildContext context) => ChatScreen(
        chatId: chatId,
        settings: settings,
        initialMessages: initialMessages,
      );
}
```

- [ ] **Step 2: Full project analyze**

```bash
cd jarvis_mobile && flutter analyze 2>&1 | grep -v "^Analyzing" | tail -20
```

Expected: `No issues found!` or only pre-existing warnings unrelated to our changes.

- [ ] **Step 3: Run all JS tests to confirm no regressions**

```bash
cd /home/user/jarvis-server-nadav && npm test 2>&1 | tail -15
```

Expected: All test suites pass (≥908 tests).

- [ ] **Step 4: Commit and push**

```bash
git add jarvis_mobile/lib/live_talk_screen.dart
git commit -m "feat: make LiveTalkScreen a thin wrapper for ChatScreen (all logic in new panels)"
git push -u origin claude/plugins-installation-ka1skx
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Shell: top bar + SegmentedButton toggle | Task 3 |
| Voice mode: orb fills screen, STT/TTS/WS unchanged | Task 4 |
| Text mode: AnimatedList bubbles, fromVoice 🎤 tag | Task 5 |
| Mic tap-to-toggle, one-shot STT, pulse animation | Task 5 |
| Text send via POST /ask-jarvis | Task 5 |
| File attachment: image/doc/audio, preview row | Task 6 |
| AnimatedSize on preview row | Task 6 |
| AnimatedSwitcher fade+slide on mode switch | Task 3 |
| Stop/resume voice on mode switch | Task 4 |
| New bubble AnimatedList slide+fade entry | Task 5 |
| POST /parse-document with pdf-parse + mammoth | Task 1 |
| ApiService.askJarvisWithImage / transcribeAudio / parseDocument | Task 2 |
| live_talk_screen.dart preserved as wrapper | Task 7 |
| file_picker added to pubspec.yaml | Task 2 |

All spec requirements covered. No placeholders. Type/method names consistent across all tasks.
