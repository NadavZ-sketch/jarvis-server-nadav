# jarvis_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Web build

The app also runs in the browser as a PWA (text-only chat experience).

```bash
flutter build web --release        # output in build/web/
flutter run -d chrome              # local dev against a running server
```

In the app's settings, point the server URL at the cloud server
(`https://jarvis-server-nadav.onrender.com`) or a reachable local server.

### Web limitations

Voice features depend on mobile-only plugins, so on web they degrade
gracefully rather than break:

- **Microphone / speech-to-text** — the mic button is hidden (`speech_to_text`
  has no web support).
- **Live Talk** — tapping the orb shows a notice and keeps the user on text
  input (live audio recording is unavailable in the browser).
- **TTS audio** — server-generated MP3 is played directly via `BytesSource`
  (no temp files on web; see `lib/platform/audio_support.dart`).
- **Local notifications / Ollama setup** — disabled on web.

Everything else (chat, tasks, reminders, notes, shopping, contacts, history,
image upload via file picker) works the same as on mobile.
