# Chat Screen Redesign — Design Spec

## Goal

Replace the current voice-only `LiveTalkScreen` with a unified chat screen that supports both voice and text modes, file/image/audio uploads, and smooth animated transitions — all within a single screen.

---

## Architecture

### Files

**New:**
- `lib/screens/chat/chat_screen.dart` — Shell: top bar, mode toggle, shared message list, IndexedStack of panels
- `lib/widgets/chat/voice_panel.dart` — Voice mode: JarvisOrb + STT/TTS (extracted from LiveTalkScreen)
- `lib/widgets/chat/text_panel.dart` — Text mode: chat bubbles + text input + mic + file attachment

**Modified:**
- `lib/live_talk_screen.dart` — Becomes a thin wrapper that pushes to `ChatScreen` (preserves existing nav call sites)

**Backend (new):**
- `POST /parse-document` — Extracts text from PDF/Word, returns plain text for LLM

### Data Flow

```
ChatScreen
  ├── messages: List<ChatMessage>   ← shared between both panels
  ├── mode: ChatMode.voice | ChatMode.text
  ├── VoicePanel(messages, onNewMessage)
  └── TextPanel(messages, onSendText, onSendVoice, onSendFile)
```

`ChatMessage` model:
```dart
class ChatMessage {
  final String id;
  final String sender;   // 'user' | 'jarvis'
  final String text;
  final bool fromVoice;  // true → shows 🎤 tag in text mode
  final String? fileUrl; // attachment thumbnail/name
  final DateTime at;
}
```

---

## Feature 1: Top Bar + Mode Toggle

```
┌──────────────────────────────────────────────┐
│  ←   ג'רביס       [  🎤 קול  |  💬 טקסט  ]  │
└──────────────────────────────────────────────┘
```

- `SegmentedButton<ChatMode>` (Material 3) — two segments
- Switching voice → text: STT stops, TTS stops; `ScrollController` snaps to bottom of bubble list
- Switching text → voice: text field clears; STT restarts

---

## Feature 2: Voice Panel

Content extracted from `LiveTalkScreen` unchanged:

- `JarvisOrb` fills the screen, receives `state` + `level`
- Continuous STT (`he_IL`, `pauseFor: 2500ms`)
- Barge-in detection (4.0 dB threshold, 4 sustained frames)
- WebSocket primary (`/ws-jarvis`) + SSE fallback (`/stream-jarvis`)
- TTS playback via `flutter_tts` + `audioplayers`
- On utterance final → `onNewMessage(userText)` called on parent
- On assistant reply → `onNewMessage` called again with bot text + `fromVoice: true`

**No bubbles shown in voice mode** — the orb is the full UI.

---

## Feature 3: Text Panel

### Layout
```
┌─────────────────────────────────────┐
│  [bubble]  אני צריך לחזור לאביב 🎤 │  ← fromVoice tag
│  [bubble]  בוודאי, אוסיף תזכורת ✓  │
│  [bubble]  מה מזג האוויר?           │
│  [bubble]  ☁ 26° מעונן חלקית        │
├─────────────────────────────────────┤
│ [preview: file.pdf  ✕]              │  ← visible when file selected
├─────────────────────────────────────┤
│  [📎]  [כתוב הודעה...]  [🎤]  [➤]  │
└─────────────────────────────────────┘
```

### Bubble List
- `AnimatedList` — each new bubble slides in from bottom + fades in (200ms, `Curves.easeOut`)
- Voice messages tagged with small `🎤` badge (right side of bubble, 10px, indigo)
- Auto-scroll to bottom on each new message

### Mic Button (tap-to-toggle)
- **Idle:** mic icon, `JC.border` ring
- **Recording:** red, pulsing ring (`ScaleTransition` 1.0→1.3, repeat) + small waveform row above input field
- First tap → starts one-shot STT (not continuous); button turns red + pulse animation begins
- Second tap → stops STT, sends recognized text as message; animation stops
- If STT returns empty → shows snackbar "לא זוהה דיבור"

### Text Send
- `POST /ask-jarvis` (sync) with full `settings` object
- Response appended to shared `messages` list
- Triggers `AnimatedList` insert animation

### File Attachment (📎)
Opens `showModalBottomSheet` with three options:

| Option | Source | Backend |
|--------|--------|---------|
| 📷 תמונה | `image_picker` (gallery/camera) | `POST /ask-jarvis` with `imageBase64` → `callGeminiVision` (existing) |
| 📄 מסמך | `file_picker` (PDF, .docx) | `POST /parse-document` (new) → extracted text → LLM |
| 🎵 אודיו | `file_picker` (.mp3, .m4a, .wav) | `POST /transcribe` (existing Whisper) → transcript text → LLM |

**Preview row** (shown above input bar after selection):
```
[ thumbnail / 📄 filename.pdf ]   [✕ dismiss]
```
Sending with ➤ attaches the file payload + any typed text to the request.

---

## Feature 4: Animations

### Mode Switch (voice ↔ text)
`AnimatedSwitcher` wrapping the panel area:
- Outgoing panel: `FadeTransition` (opacity 1→0) + `SlideTransition` (offset 0→0.08 downward)
- Incoming panel: `FadeTransition` (opacity 0→1) + `SlideTransition` (offset 0.08 below → 0)
- Duration: 300ms, `Curves.easeInOut`

### Mic Recording Pulse
`ScaleTransition` on the mic button ring:
- `AnimationController` repeats with `reverse: true`, 800ms cycle
- Scale 1.0 → 1.3, `Curves.easeInOut`
- Ring color: `Colors.red.withValues(alpha: 0.6)`

### New Bubble Entry
`AnimatedList` insert with custom builder:
```dart
SlideTransition(
  position: Tween(begin: Offset(0, 0.3), end: Offset.zero).animate(animation),
  child: FadeTransition(opacity: animation, child: bubble),
)
```
Duration: 200ms per bubble.

### File Preview Slide-Up
`AnimatedSize` wrapping the preview row — height animates from 0 to natural height (250ms, `Curves.easeOut`) when a file is selected; collapses back when dismissed.

---

## Backend: `POST /parse-document`

New endpoint in `server.js`:

**Request:** `multipart/form-data` with `file` field (PDF or .docx, max 10MB)

**Response:** `{ text: string, pages?: number, wordCount?: number }`

**Dependencies needed:**
- `pdf-parse` — already in `package.json`
- `mammoth` — `npm install mammoth` (new)
- `file_picker: ^8.0.0` — add to `pubspec.yaml` (new; `image_picker` already present)

**Implementation:**
- PDF: `pdf-parse` → extracts plain text
- .docx: `mammoth` → extracts plain text
- On success: text truncated to 8000 chars before sending to LLM (fits context window)
- On error: returns `{ error: 'לא ניתן לקרוא את הקובץ' }`

**Rate limit:** `_rl(5)` (5 req/min — document parsing is heavy)

---

## Navigation

`ChatScreen` receives the same props as current `LiveTalkScreen`:
```dart
ChatScreen({
  required String chatId,
  required AppSettings settings,
  List<ChatMessage>? initialMessages,
})
```

`live_talk_screen.dart` becomes:
```dart
class LiveTalkScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      ChatScreen(chatId: chatId, settings: settings);
}
```

---

## Non-Goals

- No persistent mode preference between sessions (always opens in voice mode)
- No file storage — files are sent inline (base64 / multipart) and not saved server-side
- No multi-file selection — one attachment per message
- No markdown rendering in bubbles — plain text only
- No read receipts or delivery indicators
