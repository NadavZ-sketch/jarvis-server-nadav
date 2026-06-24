# Chat Tab Overhaul — Design Spec
**Date:** 2026-06-24  
**Scope:** Flutter mobile app (`jarvis_mobile/lib/`)  
**Branch:** `claude/jarvis-chat-tab-b4wppq`

---

## Goal

שלושה שינויים במקביל לטאב השיחה:
1. **UX** — מעבר בין קול לטקסט על ידי הקשה על האורב (במקום SegmentedButton)
2. **Features** — Mini-Orb FAB, hint בתוך האורב, אנימציית מעבר
3. **Refactoring** — מחיקת `ChatScreen` מ-`main.dart` (1,800 שורות) ומיגרציה ל-`screens/chat/`

---

## Current State

### שני מימושי ChatScreen
| קובץ | בשימוש | גודל |
|------|---------|------|
| `main.dart` → `ChatScreen` | ✅ `main_shell.dart` | ~1,800 שורות |
| `screens/chat/chat_screen.dart` → `ChatScreen` | ❌ רק דרך `live_talk_screen.dart` | ~175 שורות |

`main_shell.dart` מייבא `ChatScreen` מ-`main.dart`. הגרסה ב-`screens/chat/` כבר מכילה `VoicePanel` ו-`TextPanel` כwidgets נפרדים, אבל חסרים בה ה-callbacks שמainShell מעביר.

### ChatMode enum (קיים ב-screens/chat/)
```dart
enum ChatMode { voice, text }
```

---

## Architecture Changes

### קבצים שמשתנים

```
jarvis_mobile/lib/
├── main_shell.dart                        ← שינוי import בלבד
├── main.dart                              ← מחיקת class ChatScreen (~שורות 744–2526)
├── screens/chat/
│   └── chat_screen.dart                   ← מקבל callbacks + AnimationController
└── widgets/chat/
    ├── voice_panel.dart                   ← onOrbTap + GestureDetector + hint
    └── text_panel.dart                    ← Mini-Orb FAB + onSwitchToVoice
```

---

## Feature Design

### 1. Orb Tap — Voice → Text

**VoicePanel** מקבל callback חדש:
```dart
final VoidCallback? onOrbTap;
```

`JarvisOrb` עטוף ב-`GestureDetector`:
```dart
GestureDetector(
  onTap: _handleOrbTap,
  child: JarvisOrb(state: _state, level: _soundLevel, size: 220, ...),
)
```

**`_handleOrbTap` לפי מצב:**

| מצב (`_state`) | פעולה |
|----------------|-------|
| `idle` / `listening` | `_speech.stop()` → `onOrbTap()` |
| `speaking` | barge-in (TTS stop + WS abort) → `onOrbTap()` |
| `thinking` | WS cancel → `onOrbTap()` |

**Hint "הקש לטקסט"** — `Stack` על גבי ה-JarvisOrb:
- גלוי רק ב-`idle` ו-`listening`
- `Text('הקש\nלטקסט')`, fontSize 10, opacity 0.55, centered
- נעלם ב-`speaking` ו-`thinking`

### 2. Mini-Orb FAB — Text → Voice

**TextPanel** מקבל callback חדש:
```dart
final VoidCallback? onSwitchToVoice;
```

ה-FAB הוא `Positioned` ב-`Stack` שעוטף את כל ה-TextPanel:
```dart
Positioned(
  bottom: 70, // מעל input bar
  left: 14,
  child: GestureDetector(
    onTap: () {
      HapticFeedback.mediumImpact();
      widget.onSwitchToVoice?.call();
    },
    onLongPress: () => _showFabTooltip(),
    child: JarvisOrb(
      state: JarvisState.idle,
      level: 0,
      size: 42,
      // same color settings as main orb
      baseColorOverride: widget.settings.orbCustomColors
          ? Color(widget.settings.orbBaseColor) : null,
      tipColorOverride: widget.settings.orbCustomColors
          ? Color(widget.settings.orbTipColor) : null,
    ),
  ),
)
```

Tooltip "חזרה לקול" — `OverlayEntry` פשוט ב-long press, נעלם אחרי 1.5 שניות.

**מיקום:** שמאל-תחתון (RTL — לא מכסה את שורת ה-input ואת כפתור השליחה בימין).

### 3. אנימציית מעבר

ב-`ChatScreen` (shell):
```dart
late final AnimationController _modeTransitionCtrl;
late final Animation<double> _modeAnim;

// initState:
_modeTransitionCtrl = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 300),
);
_modeAnim = CurvedAnimation(
  parent: _modeTransitionCtrl,
  curve: Curves.easeInOutCubic,
);
```

**Voice → Text** (`_switchMode(ChatMode.text)`):
1. `HapticFeedback.mediumImpact()`
2. `_voicePanelKey.currentState?.stopVoice()`
3. `_modeTransitionCtrl.forward()` → opacity 1→0 על VoicePanel, 0→1 על TextPanel
4. `setState(() => _mode = ChatMode.text)` בסוף animation

**Text → Voice** (`_switchMode(ChatMode.voice)`):
1. `HapticFeedback.mediumImpact()`
2. `_modeTransitionCtrl.reverse()`
3. `setState(() => _mode = ChatMode.voice)`
4. `addPostFrameCallback` → `_voicePanelKey.currentState?.resumeVoice()`

ה-`AnimatedSwitcher` הקיים (300ms) נשאר — ה-`AnimationController` מוסיף רק את ה-haptic ואת ה-orb-specific behavior.

---

## ChatScreen — Callbacks Migration

`screens/chat/chat_screen.dart` מקבל את כל הprops שקיימים ב-`main.dart`:

```dart
class ChatScreen extends StatefulWidget {
  final String? chatId;                                    // קיים
  final List<Map<String, dynamic>>? initialMessages;       // קיים
  final AppSettings? initialSettings;                      // 🆕
  final ValueChanged<AppSettings>? onSettingsChanged;      // 🆕
  final VoidCallback? onOpenDrawer;                        // 🆕
  final String? pendingCommand;                            // 🆕
  final VoidCallback? onCommandConsumed;                   // 🆕
  final void Function(Future<void> Function())? onRegisterArchive; // 🆕
  final void Function(String target)? onNavigate;          // 🆕

  // ...
}
```

**`onRegisterArchive`** — ChatScreen רושם `archiveCurrentSession()` שמוחק את ה-messages המקומיים ומתחיל session חדש (הלוגיקה הקיימת ב-`main.dart`).

**`pendingCommand`** — ב-`didUpdateWidget`, אם השתנה → inject ל-TextPanel כhodaa ומקרא `onCommandConsumed`.

**`onNavigate`** — מועבר ל-TextPanel שמפעיל אותו כשJarvis מחזיר action מסוג `navigate`.

**`initialSettings`** — אם מסופק, משמש כ-initial value ל-`_settings` במקום `AppSettings.load()`.

---

## main.dart — Cleanup

מוחקים את שורות **744–2526** (`ChatScreen` + `_ChatScreenState` + `_InputIconButton`).

נשאר ב-`main.dart`:
- `JC` design tokens
- `JarvisApp`, `_JarvisAppState`
- `JarvisState` enum ← **חובה** — מיובא על ידי `widgets/chat/voice_panel.dart`

נמחק יחד עם ChatScreen (dead code):
- `_TypingDots`, `_JarvisOrb`, `_ChatBubble`, `_ProviderBadge` — private widgets שרק ChatScreen השתמש בהם

**`main_shell.dart`** — שינוי אחד:
```dart
// לפני:
import 'main.dart' show JC, ChatScreen;

// אחרי:
import 'main.dart' show JC;
import 'screens/chat/chat_screen.dart' show ChatScreen;
```

---

## Removed UI Elements

| מה | איפה היה | למה מסירים |
|----|----------|------------|
| `SegmentedButton` (🎤 קול / 💬 טקסט) | AppBar של ChatScreen ב-`screens/chat/` | מוחלף על ידי orb-tap |
| `_voiceKey` / `_textKey` ValueKeys | ChatScreen | לא נדרשים יותר |

---

## State Management

`messages` list — נשאר ב-`ChatScreen` (shell) ומועבר ל-VoicePanel ו-TextPanel. המעבר בין מצבים **לא מאפס** את הרשימה — השיחה רציפה.

```
ChatScreen
  ├── List<ChatMessage> _messages        // shared
  ├── VoicePanel(messages: _messages)    // reads + appends
  └── TextPanel(messages: _messages)     // reads + appends
```

---

## Out of Scope

הפיצ׳רים הבאים **לא** כלולים בspread זה (יכולים להגיע בPR נפרד):
- History browser panel
- In-chat search
- Action chips לניווט
- Offline queue
- Survey system migration

---

## Testing

| Test | סוג | מה בודקים |
|------|-----|-----------|
| Orb tap → mode switches to text | Widget test | VoicePanel emits onOrbTap |
| Mini-FAB tap → mode switches to voice | Widget test | TextPanel emits onSwitchToVoice |
| messages persist across mode switch | Widget test | List לא מתאפסת |
| pendingCommand injected into TextPanel | Widget test | didUpdateWidget flow |
| main_shell compiles with new import | Build | אין regression |

---

## File Impact Summary

| קובץ | סוג שינוי | גודל שינוי |
|------|-----------|------------|
| `main.dart` | מחיקה | −1,800 שורות |
| `screens/chat/chat_screen.dart` | הרחבה | +80 שורות |
| `widgets/chat/voice_panel.dart` | עדכון | +40 שורות |
| `widgets/chat/text_panel.dart` | עדכון | +50 שורות |
| `main_shell.dart` | שינוי import | +1 / −1 שורות |
