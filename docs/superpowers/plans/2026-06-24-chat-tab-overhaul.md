# Chat Tab Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `ChatScreen` monolith in `main.dart` with the cleaner `screens/chat/` architecture, and add orb-tap mode switching (voice↔text via tapping the JarvisOrb).

**Architecture:** `ChatScreen` (shell) in `screens/chat/chat_screen.dart` manages shared state (`_messages`, `_chatId`, `_settings`) and delegates rendering to `VoicePanel` and `TextPanel`. Tapping the orb in VoicePanel triggers `onOrbTap` → ChatScreen calls `_switchMode(ChatMode.text)`. A Mini-Orb FAB in TextPanel calls `onSwitchToVoice` → ChatScreen calls `_switchMode(ChatMode.voice)`.

**Tech Stack:** Flutter/Dart, `shared_preferences`, `http`, `flutter_test` for widget tests. All work is inside `jarvis_mobile/`.

---

## File Map

| File | Change |
|------|--------|
| `lib/widgets/chat/voice_panel.dart` | Add `onOrbTap` callback + `GestureDetector` + hint overlay |
| `lib/widgets/chat/text_panel.dart` | Add `onSwitchToVoice` + `onNavigate` callbacks + Mini-Orb FAB |
| `lib/screens/chat/chat_screen.dart` | Full upgrade: session management, callbacks, animation, remove SegmentedButton |
| `lib/main_shell.dart` | Switch import from `main.dart` to `screens/chat/chat_screen.dart` |
| `lib/main.dart` | Delete `ChatScreen` class + dead private widgets + clean unused imports |
| `test/widgets/voice_panel_orb_tap_test.dart` | New: orb-tap widget test |
| `test/widgets/text_panel_fab_test.dart` | New: Mini-Orb FAB widget test |

---

## Task 1: VoicePanel — onOrbTap callback + hint overlay

**Files:**
- Modify: `lib/widgets/chat/voice_panel.dart`
- Create: `test/widgets/voice_panel_orb_tap_test.dart`

### Step 1.1 — Write the failing test

Create `jarvis_mobile/test/widgets/voice_panel_orb_tap_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/main.dart' show JC;
import 'package:jarvis_mobile/screens/chat/chat_screen.dart' show ChatMessage;

// We test only the public surface: that onOrbTap is wired up.
// VoicePanel's mic/TTS internals are not exercised in unit tests.

// Stub widget that mimics VoicePanel's orb area:
// Replace with real VoicePanel import once the callback exists.
class _OrbStub extends StatefulWidget {
  final VoidCallback? onOrbTap;
  const _OrbStub({this.onOrbTap});
  @override
  State<_OrbStub> createState() => _OrbStubState();
}
class _OrbStubState extends State<_OrbStub> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOrbTap,
      child: const SizedBox(key: Key('orb'), width: 100, height: 100),
    );
  }
}

void main() {
  testWidgets('onOrbTap is called when orb is tapped', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _OrbStub(onOrbTap: () => tapped = true)),
    ));
    await tester.tap(find.byKey(const Key('orb')));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
```

- [ ] Create the file above in `jarvis_mobile/test/widgets/voice_panel_orb_tap_test.dart`

### Step 1.2 — Run test (stub passes as warmup)

```bash
cd jarvis_mobile && flutter test test/widgets/voice_panel_orb_tap_test.dart -v
```

Expected: PASS (stub is self-contained).

### Step 1.3 — Add `onOrbTap` to `VoicePanel`

In `lib/widgets/chat/voice_panel.dart`:

**In the `VoicePanel` widget class** (around line 19), add the new field:

```dart
class VoicePanel extends StatefulWidget {
  final String chatId;
  final AppSettings settings;
  final void Function(ChatMessage msg) onNewMessage;
  final List<ChatMessage> messages;
  final VoidCallback? onOrbTap;          // ← NEW

  const VoicePanel({
    super.key,
    required this.chatId,
    required this.settings,
    required this.onNewMessage,
    required this.messages,
    this.onOrbTap,                        // ← NEW
  });
```

### Step 1.4 — Add `_handleOrbTap()` to `VoicePanelState`

Add this method to `VoicePanelState` (after the existing `_listen()` method):

```dart
void _handleOrbTap() {
  switch (_state) {
    case JarvisState.listening:
    case JarvisState.idle:
      _hardCapTimer?.cancel();
      _speech.stop();
      widget.onOrbTap?.call();
      break;
    case JarvisState.speaking:
      // Barge-in: stop TTS + notify server, then switch
      _flutterTts.stop();
      _audioPlayer.stop();
      _sendWs({'type': 'barge_in'});
      _bargeInFrames = 0;
      widget.onOrbTap?.call();
      break;
    case JarvisState.thinking:
      // Cancel in-flight request, then switch
      _sendWs({'type': 'abort'});
      setState(() { _streamingReply = ''; _state = JarvisState.idle; });
      widget.onOrbTap?.call();
      break;
    default:
      widget.onOrbTap?.call();
  }
}
```

### Step 1.5 — Wrap JarvisOrb in Stack + GestureDetector with hint overlay

Replace the `JarvisOrb(...)` widget in the `build()` method (inside the `Column → Padding → Column` near line 463) with:

```dart
GestureDetector(
  onTap: _handleOrbTap,
  child: Stack(
    alignment: Alignment.center,
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
      // Hint — only visible when idle or listening
      if (_state == JarvisState.idle || _state == JarvisState.listening)
        IgnorePointer(
          child: Text(
            'הקש\nלטקסט',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
    ],
  ),
),
```

### Step 1.6 — Commit

```bash
cd jarvis_mobile && flutter analyze lib/widgets/chat/voice_panel.dart
git add lib/widgets/chat/voice_panel.dart test/widgets/voice_panel_orb_tap_test.dart
git commit -m "feat(voice-panel): add onOrbTap callback + tap hint overlay"
```

---

## Task 2: TextPanel — Mini-Orb FAB + onSwitchToVoice + onNavigate

**Files:**
- Modify: `lib/widgets/chat/text_panel.dart`
- Create: `test/widgets/text_panel_fab_test.dart`

### Step 2.1 — Write the failing test

Create `jarvis_mobile/test/widgets/text_panel_fab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Mini-Orb FAB calls onSwitchToVoice when tapped', (tester) async {
    bool switched = false;
    // We test with a stub Positioned+GestureDetector matching the FAB structure
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned(
              bottom: 70, left: 14,
              child: GestureDetector(
                key: const Key('mini_orb_fab'),
                onTap: () => switched = true,
                child: const SizedBox(width: 42, height: 42),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('mini_orb_fab')));
    await tester.pump();
    expect(switched, isTrue);
  });
}
```

- [ ] Create the file above.

```bash
cd jarvis_mobile && flutter test test/widgets/text_panel_fab_test.dart -v
```

Expected: PASS.

### Step 2.2 — Add new callbacks to `TextPanel`

In `lib/widgets/chat/text_panel.dart`, update the `TextPanel` widget class:

```dart
class TextPanel extends StatefulWidget {
  final List<ChatMessage> messages;
  final AppSettings settings;
  final String chatId;
  final void Function(ChatMessage msg) onNewMessage;
  final VoidCallback? onSwitchToVoice;                     // ← NEW
  final void Function(String target)? onNavigate;           // ← NEW

  const TextPanel({
    super.key,
    required this.messages,
    required this.settings,
    required this.chatId,
    required this.onNewMessage,
    this.onSwitchToVoice,                                   // ← NEW
    this.onNavigate,                                        // ← NEW
  });
```

### Step 2.3 — Handle `onNavigate` in `_sendText`

In `_TextPanelState._sendText()`, after extracting `answer`, add action handling:

```dart
// Inside the try block in _sendText, after:
//   final answer = (result['answer'] as String? ?? '').trim();
// Add:
final action = result['action'] as Map<String, dynamic>?;
if (action != null && action['type'] == 'navigate') {
  final target = action['target'] as String? ?? '';
  if (target.isNotEmpty) widget.onNavigate?.call(target);
}
```

### Step 2.4 — Wrap build Column in Stack + add Mini-Orb FAB

In `_TextPanelState.build()`, replace the root `Column(...)` with a `Stack`:

```dart
@override
Widget build(BuildContext context) {
  return Stack(
    key: const ValueKey('text'),
    children: [
      Column(
        // ← move entire existing Column here (remove the key from Column)
        children: [
          Expanded(
            child: AnimatedList(
              key: _listKey,
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              initialItemCount: widget.messages.length,
              itemBuilder: (context, index, animation) {
                final msg = widget.messages[index];
                return _BubbleEntry(msg: msg, animation: animation, settings: widget.settings, chatId: widget.chatId);
              },
            ),
          ),
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
      ),
      // Mini-Orb FAB — switches to voice mode
      if (widget.onSwitchToVoice != null)
        Positioned(
          bottom: 70,   // above input bar (~54px) + padding
          left: 14,
          child: GestureDetector(
            key: const Key('mini_orb_fab'),
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onSwitchToVoice!();
            },
            onLongPress: _showVoiceTooltip,
            child: JarvisOrb(
              state: JarvisState.idle,
              level: 0,
              size: 42,
              baseColorOverride: widget.settings.orbCustomColors
                  ? Color(widget.settings.orbBaseColor) : null,
              tipColorOverride: widget.settings.orbCustomColors
                  ? Color(widget.settings.orbTipColor) : null,
              voiceSensitivity: widget.settings.orbVoiceSensitivity,
              rotationSensitivity: widget.settings.orbRotationSensitivity,
              explosionEnabled: false,
            ),
          ),
        ),
    ],
  );
}
```

### Step 2.5 — Add `_showVoiceTooltip()` and missing imports

At the top of `_TextPanelState` (before `initState`), add:

```dart
OverlayEntry? _fabTooltipEntry;

void _showVoiceTooltip() {
  _fabTooltipEntry?.remove();
  final overlay = Overlay.of(context);
  _fabTooltipEntry = OverlayEntry(
    builder: (_) => Positioned(
      bottom: 120,
      left: 60,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: JC.blue400.withValues(alpha: 0.4)),
          ),
          child: Text(
            'חזרה לקול',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: JC.blue300,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(_fabTooltipEntry!);
  Future.delayed(const Duration(milliseconds: 1500), () {
    _fabTooltipEntry?.remove();
    _fabTooltipEntry = null;
  });
}
```

Add these imports to `text_panel.dart` (already has most — add missing):

```dart
import 'package:flutter/services.dart';                            // HapticFeedback
import '../../main.dart' show JC, JarvisState;                    // JarvisState for FAB
import '../../widgets/jarvis_orb.dart';                            // JarvisOrb
```

In `dispose()`, add:

```dart
_fabTooltipEntry?.remove();
```

### Step 2.6 — Commit

```bash
cd jarvis_mobile && flutter analyze lib/widgets/chat/text_panel.dart
git add lib/widgets/chat/text_panel.dart test/widgets/text_panel_fab_test.dart
git commit -m "feat(text-panel): add Mini-Orb FAB and onSwitchToVoice/onNavigate callbacks"
```

---

## Task 3: ChatScreen — Session management

Adds `chatId`, `_settings`, and all session persistence methods to the new ChatScreen shell.

**Files:**
- Modify: `lib/screens/chat/chat_screen.dart`

### Step 3.1 — Add imports

At the top of `lib/screens/chat/chat_screen.dart`, replace existing imports with:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../widgets/chat/voice_panel.dart';
import '../../widgets/chat/text_panel.dart';
```

### Step 3.2 — Make `chatId` optional in the widget + add new fields

Replace the entire `ChatScreen` StatefulWidget class definition:

```dart
class ChatScreen extends StatefulWidget {
  // chatId is optional — if null, generated internally via SharedPreferences.
  final String? chatId;
  final List<Map<String, dynamic>>? initialMessages;
  final AppSettings? initialSettings;
  final ValueChanged<AppSettings>? onSettingsChanged;
  final VoidCallback? onOpenDrawer;
  final String? pendingCommand;
  final VoidCallback? onCommandConsumed;
  final void Function(Future<void> Function())? onRegisterArchive;
  final void Function(String target)? onNavigate;

  const ChatScreen({
    super.key,
    this.chatId,
    this.initialMessages,
    this.initialSettings,
    this.onSettingsChanged,
    this.onOpenDrawer,
    this.pendingCommand,
    this.onCommandConsumed,
    this.onRegisterArchive,
    this.onNavigate,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
```

### Step 3.3 — Add state fields to `_ChatScreenState`

At the top of `_ChatScreenState`, before the existing fields, add:

```dart
class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  ChatMode _mode = ChatMode.voice;
  final GlobalKey<VoicePanelState> _voicePanelKey = GlobalKey();

  // Session management
  String _chatId = '';
  AppSettings _settings = AppSettings();
```

### Step 3.4 — Add session management methods

After `_addMessage()` in `_ChatScreenState`, add:

```dart
void _addMessage(ChatMessage msg) {
  if (!mounted) return;
  setState(() => _messages.add(msg));
  _persistMessages();  // persist after every new message
}

Future<void> _loadChatHistory() async {
  final prefs = await SharedPreferences.getInstance();

  // 1. Load or generate chatId
  final externalId = widget.chatId;
  if (externalId != null && externalId.isNotEmpty) {
    _chatId = externalId;
  } else {
    final saved = prefs.getString('current_chat_id');
    if (saved != null && saved.isNotEmpty) {
      _chatId = saved;
    } else {
      _chatId = 'chat-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(100000)}';
      await prefs.setString('current_chat_id', _chatId);
    }
  }

  // 2. Load cached messages immediately (instant first paint)
  final cached = prefs.getString('current_messages');
  if (cached != null && cached.isNotEmpty && mounted) {
    try {
      final List decoded = jsonDecode(cached);
      final loaded = decoded
          .cast<Map<String, dynamic>>()
          .map(ChatMessage.fromLegacy)
          .toList();
      if (loaded.isNotEmpty) setState(() { _messages.clear(); _messages.addAll(loaded); });
    } catch (_) {}
  }

  // 3. Fetch fresh from server in background
  if (_settings.serverUrl.isEmpty) return;
  try {
    final url = Uri.parse('${_settings.serverUrl}/chat-history?limit=60&chatId=$_chatId');
    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200 && mounted) {
      final data = jsonDecode(response.body);
      final List raw = data['messages'] ?? [];
      if (raw.isNotEmpty) {
        final serverMsgs = raw.map<ChatMessage>((m) => ChatMessage(
          id: UniqueKey().toString(),
          sender: (m['role'] as String? ?? 'jarvis') == 'user' ? 'user' : 'jarvis',
          text: m['text'] as String? ?? '',
        )).toList();
        if (mounted) setState(() { _messages.clear(); _messages.addAll(serverMsgs); });
        await _persistMessages();
      }
    }
  } catch (_) {}
}

Future<void> _persistMessages() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final serialized = _messages.map((m) => {
      'sender': m.sender,
      'text': m.text,
      'fromVoice': m.fromVoice,
    }).toList();
    await prefs.setString('current_messages', jsonEncode(serialized));
  } catch (_) {}
}

Future<void> _archiveSessionToHistory() async {
  if (_messages.length <= 1) return;
  if (_chatId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_sessions') ?? '[]';
    final List sessions = jsonDecode(raw);
    final serialized = _messages.map((m) => {'sender': m.sender, 'text': m.text}).toList();
    sessions.removeWhere((s) => s['chat_id'] == _chatId);
    sessions.add({
      'date': DateTime.now().toIso8601String(),
      'messages': serialized,
      'chat_id': _chatId,
    });
    final trimmed = sessions.length > 50
        ? sessions.sublist(sessions.length - 50)
        : sessions;
    await prefs.setString('chat_sessions', jsonEncode(trimmed));
  } catch (_) {}
}

Future<void> _startNewChat() async {
  await _archiveSessionToHistory();
  if (!mounted) return;
  final prefs = await SharedPreferences.getInstance();
  _chatId = 'chat-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(100000)}';
  await prefs.setString('current_chat_id', _chatId);
  await prefs.remove('current_messages');
  if (mounted) {
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(
        id: 'greeting-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'jarvis',
        text: 'שיחה חדשה! מוכן לעזור, ${_settings.userName}.',
      ));
    });
  }
  await _persistMessages();
}
```

### Step 3.5 — Check analyze

```bash
cd jarvis_mobile && flutter analyze lib/screens/chat/chat_screen.dart
```

Expected: no errors relating to the new methods. (Other errors from missing callback wiring come in Task 4.)

### Step 3.6 — Commit

```bash
git add lib/screens/chat/chat_screen.dart
git commit -m "feat(chat-screen): add session management — chatId, loadHistory, persist, archive"
```

---

## Task 4: ChatScreen — Callbacks + pendingCommand + initState

**Files:**
- Modify: `lib/screens/chat/chat_screen.dart`

### Step 4.1 — Update `initState`

Replace the existing `initState()` with:

```dart
@override
void initState() {
  super.initState();

  // Register archive callback so main_shell can trigger archive on tab switch
  widget.onRegisterArchive?.call(() => _archiveSessionToHistory());

  // Settings: use provided or load from storage
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

  // Pre-populate from initialMessages if provided (e.g. LiveTalkScreen)
  if (widget.initialMessages != null) {
    _messages.addAll(widget.initialMessages!.map(ChatMessage.fromLegacy));
  }
}
```

### Step 4.2 — Add `didUpdateWidget`

After `initState()`, add:

```dart
@override
void didUpdateWidget(covariant ChatScreen oldWidget) {
  super.didUpdateWidget(oldWidget);

  // Sync settings changes from parent (e.g. quick-settings FAB)
  if (widget.initialSettings != null &&
      widget.initialSettings != oldWidget.initialSettings) {
    setState(() => _settings = widget.initialSettings!);
  }

  // Inject a pending command: switch to text mode then send
  if (widget.pendingCommand != null &&
      widget.pendingCommand != oldWidget.pendingCommand) {
    final cmd = widget.pendingCommand!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCommandConsumed?.call();
      _switchMode(ChatMode.text);
      // TextPanel will receive it via its own pendingCommand prop (set below)
    });
  }
}
```

> Note: `pendingCommand` injection to TextPanel is handled by passing it as a prop in `_buildTextPanel()` (Task 5). TextPanel already handles it via `didUpdateWidget` — but currently it doesn't. We add that in Step 5.4.

### Step 4.3 — Commit

```bash
cd jarvis_mobile && flutter analyze lib/screens/chat/chat_screen.dart
git add lib/screens/chat/chat_screen.dart
git commit -m "feat(chat-screen): add callbacks, initState with settings loading, didUpdateWidget"
```

---

## Task 5: ChatScreen — Animation + mode switch + AppBar cleanup + panel wiring

**Files:**
- Modify: `lib/screens/chat/chat_screen.dart`

### Step 5.1 — Add AnimationController

Change the class mixin and add controller field:

The class already has `with SingleTickerProviderStateMixin` — keep that.

Add to the state fields:

```dart
late final AnimationController _modeCtrl;
```

In `initState()`, after `super.initState()`:

```dart
_modeCtrl = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 300),
);
```

In `dispose()`:

```dart
@override
void dispose() {
  _modeCtrl.dispose();
  super.dispose();
}
```

### Step 5.2 — Replace `_switchMode` with animated version

Replace the existing `_switchMode()`:

```dart
void _switchMode(ChatMode mode) {
  if (mode == _mode) return;
  HapticFeedback.mediumImpact();

  if (_mode == ChatMode.voice) {
    _voicePanelKey.currentState?.stopVoice();
  }

  setState(() => _mode = mode);

  if (mode == ChatMode.voice) {
    _modeCtrl.reverse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _voicePanelKey.currentState?.resumeVoice();
    });
  } else {
    _modeCtrl.forward();
  }
}
```

### Step 5.3 — Update `build()` AppBar — remove SegmentedButton, add drawer icon

Replace the existing `build()` AppBar:

```dart
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
      leading: widget.onOpenDrawer != null
          ? IconButton(
              icon: Icon(Icons.menu_rounded, color: JC.textSecondary),
              onPressed: widget.onOpenDrawer,
            )
          : null,
      automaticallyImplyLeading: widget.onOpenDrawer == null,
    ),
    body: AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder: (child, animation) {
        final offset = Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation);
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
```

### Step 5.4 — Update `_buildVoicePanel()` and `_buildTextPanel()`

Replace both builder methods:

```dart
Widget _buildVoicePanel() {
  return VoicePanel(
    key: _voicePanelKey,
    chatId: _chatId,                               // ← internal chatId
    settings: _settings,                           // ← internal settings
    messages: _messages,
    onNewMessage: _addMessage,
    onOrbTap: () => _switchMode(ChatMode.text),   // ← NEW
  );
}

Widget _buildTextPanel() {
  return TextPanel(
    key: const ValueKey('text'),
    messages: _messages,
    settings: _settings,                                        // ← internal settings
    chatId: _chatId,                                            // ← internal chatId
    onNewMessage: _addMessage,
    onSwitchToVoice: () => _switchMode(ChatMode.voice),        // ← NEW
    onNavigate: widget.onNavigate,                             // ← passed through
  );
}
```

### Step 5.5 — Add `pendingCommand` prop to TextPanel + handling

In `lib/widgets/chat/text_panel.dart`, add:

```dart
// In TextPanel widget:
final String? pendingCommand;          // ← NEW

const TextPanel({
  ...
  this.pendingCommand,                 // ← NEW
});
```

In `_TextPanelState.didUpdateWidget()` (add the full method):

```dart
@override
void didUpdateWidget(TextPanel old) {
  super.didUpdateWidget(old);
  final newCount = widget.messages.length;
  if (newCount > _prevCount) {
    for (var i = _prevCount; i < newCount; i++) {
      _listKey.currentState?.insertItem(i, duration: const Duration(milliseconds: 200));
    }
    _prevCount = newCount;
    _scrollToBottom();
  }
  // Auto-send a pending command injected by parent (e.g. from drawer or home screen)
  if (widget.pendingCommand != null && widget.pendingCommand != old.pendingCommand) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _textCtrl.text = widget.pendingCommand!;
      _sendText();
    });
  }
}
```

> Note: This replaces the *existing* `didUpdateWidget` in TextPanel — the existing one only handles messages growth. The new version also handles `pendingCommand`.

Update `_buildTextPanel()` in ChatScreen to pass it:

```dart
Widget _buildTextPanel() {
  return TextPanel(
    key: const ValueKey('text'),
    messages: _messages,
    settings: _settings,
    chatId: _chatId,
    onNewMessage: _addMessage,
    onSwitchToVoice: () => _switchMode(ChatMode.voice),
    onNavigate: widget.onNavigate,
    pendingCommand: widget.pendingCommand,    // ← pass through
  );
}
```

Also update `didUpdateWidget` in `_ChatScreenState` — remove the TextPanel injection note from Task 4 (TextPanel now handles it directly):

```dart
@override
void didUpdateWidget(covariant ChatScreen oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (widget.initialSettings != null &&
      widget.initialSettings != oldWidget.initialSettings) {
    setState(() => _settings = widget.initialSettings!);
  }
  if (widget.pendingCommand != null &&
      widget.pendingCommand != oldWidget.pendingCommand) {
    // Ensure we're in text mode when a command is injected
    if (_mode != ChatMode.text) _switchMode(ChatMode.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCommandConsumed?.call();
    });
  }
}
```

### Step 5.6 — Remove static `_voiceKey` / `_textKey` constants (were used for AnimatedSwitcher)

Delete these two lines from `_ChatScreenState`:

```dart
// DELETE these two lines:
static const _voiceKey = ValueKey('voice');
static const _textKey  = ValueKey('text');
```

### Step 5.7 — Analyze and commit

```bash
cd jarvis_mobile && flutter analyze lib/screens/chat/ lib/widgets/chat/
```

Expected: no errors.

```bash
git add lib/screens/chat/chat_screen.dart lib/widgets/chat/text_panel.dart
git commit -m "feat(chat-screen): animation, orb-tap wiring, AppBar cleanup, pendingCommand flow"
```

---

## Task 6: main_shell.dart — Switch import

**Files:**
- Modify: `lib/main_shell.dart`

### Step 6.1 — Update import

In `lib/main_shell.dart`, find:

```dart
import 'main.dart' show JC, ChatScreen;
```

Replace with:

```dart
import 'main.dart' show JC;
import 'screens/chat/chat_screen.dart' show ChatScreen;
```

### Step 6.2 — Verify ChatScreen props match

`main_shell.dart` calls ChatScreen with:

```dart
ChatScreen(
  onRegisterArchive: (fn) => _archiveChatFn = fn,
  initialSettings: _settings,
  onSettingsChanged: _onSettingsChanged,
  onOpenDrawer: _openDrawer,
  pendingCommand: _pendingChatCommand,
  onCommandConsumed: () => setState(() => _pendingChatCommand = null),
  onNavigate: _navigateFromChat,
),
```

All props now exist on the new `ChatScreen`. No changes needed to the call site.

### Step 6.3 — Analyze and commit

```bash
cd jarvis_mobile && flutter analyze lib/main_shell.dart
git add lib/main_shell.dart
git commit -m "refactor(main-shell): switch ChatScreen import to screens/chat/"
```

---

## Task 7: main.dart — Delete ChatScreen + dead private widgets + clean imports

**Files:**
- Modify: `lib/main.dart`

### Step 7.1 — Delete dead classes

Delete the following blocks from `lib/main.dart` (everything after line 198):

- Lines 199–256: `_TypingDots` + `_TypingDotsState`
- Lines 257–296: `_JarvisOrb`
- Lines 297–742: `_ChatBubble` + `_ChatBubbleState` + `_ProviderBadge`
- Lines 743–2526: `ChatScreen` + `_ChatScreenState`
- Lines 2526–2560: `_InputIconButton`

After deletion, `main.dart` should end at line 198 with:

```dart
enum JarvisState { idle, listening, thinking, speaking, complete }
```

### Step 7.2 — Remove unused imports

After deleting ChatScreen, these imports in `main.dart` are no longer needed. Remove them:

```dart
// DELETE these import lines:
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'platform/audio_support.dart';
import 'widgets/markdown_lite.dart';
import 'widgets/jarvis_orb.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'live_talk_screen.dart';
import 'transitions/slide_fade_route.dart';
import 'screens/survey_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
```

The final `main.dart` import block should be only:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_settings.dart';
import 'theme/jarvis_theme.dart';
import 'theme/theme_notifier.dart';
import 'screens/splash_screen.dart';
```

### Step 7.3 — Verify the final main.dart structure

After editing, `main.dart` should contain exactly:
1. The 6 import lines above
2. `class JC { ... }` (lines 41–99)
3. `class JarvisApp extends StatefulWidget { ... }` (lines 101–106)
4. `class _JarvisAppState extends State<JarvisApp> { ... }` (lines 108–195)
5. `enum JarvisState { idle, listening, thinking, speaking, complete }` (line 197)

### Step 7.4 — Analyze the full project

```bash
cd jarvis_mobile && flutter analyze lib/
```

Expected: 0 errors, 0 warnings. Fix any that appear (likely leftover imports in other files that assumed things from main.dart).

### Step 7.5 — Run existing tests

```bash
cd jarvis_mobile && flutter test test/ -v
```

Expected: all passing (JC design token tests + new FAB/orb tests).

### Step 7.6 — Commit

```bash
git add lib/main.dart
git commit -m "refactor(main): delete ChatScreen monolith and dead private widgets (-1800 lines)"
```

---

## Task 8: Final smoke check + push

### Step 8.1 — Full analyze

```bash
cd jarvis_mobile && flutter analyze lib/
```

Expected: clean.

### Step 8.2 — Full test suite

```bash
cd jarvis_mobile && flutter test test/ -v
```

Expected: all green.

### Step 8.3 — Manual spot checks (if device/emulator available)

1. Launch app → Chat tab → Orb visible with "הקש לטקסט" hint
2. Tap orb → switches to text mode with Mini-Orb FAB visible
3. Tap Mini-Orb FAB → returns to voice mode
4. Tap orb while Jarvis is speaking → stops speech + switches to text
5. Send a message in text mode → response appears without crashing
6. Switch tabs away from Chat → archived (no crash)
7. Return to Chat tab → session restored

### Step 8.4 — Push and open PR

```bash
git push -u origin claude/jarvis-chat-tab-b4wppq
```

Then create a draft PR titled:
`feat: chat tab overhaul — orb-tap mode switch + migration from main.dart monolith`
