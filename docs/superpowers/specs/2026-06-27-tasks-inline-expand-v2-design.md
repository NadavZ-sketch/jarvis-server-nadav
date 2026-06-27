# Tasks Inline Expand v2 — Suggestions Redesign + Ask Jarvis

**Date:** 2026-06-27
**Scope:** `task_inline_expand.dart`, `smart_task_card.dart`, `tasks_screen.dart`, `productivity_screen.dart`, `main_shell.dart`

---

## Goals

1. **Suggestions redesign** — the current compact suggestion rows feel noisy and equal-weight to the task content. Replace with a collapsible secondary section using larger, card-style items.
2. **Ask Jarvis deep-link** — any task or subtask should have a one-tap path to a Jarvis chat conversation pre-loaded with context.

---

## 1. Suggestions Redesign

### What changes

| Before | After |
|---|---|
| Always-visible compact rows at top of expand | Collapsible section at bottom of expand |
| Spinner + header always takes space | Badge shows count; user opens on demand |
| LLM enhance-on-type (debounce + ✨ chip below field) | **Removed entirely** |

### Layout of the new suggestions section

```
┌─────────────────────────────────────────┐
│ ✨  הצעות חכמות          [4]  ▾         │  ← toggle row (tappable)
├─────────────────────────────────────────┤
│  [📊]  איסוף נתוני מכירות Q2           │  ← card (hidden until opened)
│  [🎨]  עיצוב תבנית ויזואלית למצגת      │
│  [📝]  כתיבת תסריט לנרטיב...           │
│  [👥]  תיאום עם מנהל הכספים            │
└─────────────────────────────────────────┘
```

**Toggle row:** always visible, shows `✨ הצעות חכמות` label + count badge (`[4]`) + chevron.  
**Count badge:** indigo pill (`JC.indigo300` on `JC.indigo500.withValues(alpha:0.12)`).  
**Collapsed by default.** Spinner shown inside the toggle row while loading.

**Suggestion cards:**
- Full-width, rounded (`borderRadius: 11`)
- Background: `JC.indigo500.withValues(alpha:0.08)`, border: `JC.indigo300.withValues(alpha:0.18)`
- Left: emoji/icon in a 26×26 pill; right: text + "הוסף" label
- **Tap once:** card highlights (selected state — brighter border, slightly tinted bg). "הוסף" label becomes `JC.indigo300`.
- **Tap second time:** card animates out (height → 0), subtask added to list below.
- Animated expand/collapse of the section (`AnimatedCrossFade` or `AnimatedContainer` max-height).

### LLM enhance removal

Delete from `_TaskInlineExpandState`:
- `_enhanceDebounce`, `_enhancedText`, `_enhancing` fields
- `_onSubtaskChanged()`, `_enhance()` methods
- The ✨ chip widget below the add-subtask field
- `onChanged: _onSubtaskChanged` from the TextField

The add-subtask TextField remains for manual entry (no LLM).

---

## 2. Ask Jarvis Deep-Link

### User flow

1. User taps **🤖** icon on a task (in the action row) or a **💬** icon on a subtask row.
2. App switches to the Chat tab (index 1 in `MainShell`).
3. Chat input field is pre-filled with context — user reads, optionally edits, then sends.

### Message format

**For a task:**
```
עזור לי עם המשימה: "[task title]"
```
If description exists:
```
עזור לי עם המשימה: "[task title]"
פרטים: [description]
```

**For a subtask:**
```
עזור לי עם: "[subtask text]" (מתוך: "[parent task title]")
```

### Architecture — callback chain

The existing `pendingCommand` / `onCommandConsumed` pattern in `MainShell` already handles pre-filling chat. We thread a callback down:

```
MainShell._onAskJarvis(String msg)
  └─ setState(() { _pendingChatCommand = msg; _selectedIndex = 1; })

ProductivityScreen
  + prop: void Function(String)? onAskJarvis
  └─ passes to TasksScreen

TasksScreen
  + prop: void Function(String)? onAskJarvis
  └─ passes to SmartTaskCard

SmartTaskCard
  + prop: void Function(String)? onAskJarvis
  └─ passes to TaskInlineExpand

TaskInlineExpand
  + prop: void Function(String)? onAskJarvis
  ├─ action row: 🤖 button → onAskJarvis(_buildTaskMessage())
  └─ subtask rows: 💬 icon → onAskJarvis(_buildSubtaskMessage(sub))
```

All props are nullable (`void Function(String)?`) — the feature is silently absent if the callback isn't wired, so no breaking changes elsewhere.

### UI placement

**Action row** (bottom of inline expand) — three buttons:

```
[✏️ עוד פרטים]          [🤖 שוחח עם ג'רוויס]    [🗑 מחק]
```

Style: same `_actionBtn` helper, color `JC.indigo300`, icon `Icons.smart_toy_outlined` or similar.

**Subtask rows** — small chat icon at trailing end:

```
☐  כתיבת תסריט לנרטיב                              [💬]
```

Icon: `Icons.chat_bubble_outline_rounded`, size 13, color `JC.textMuted`.  
Tapping it calls `onAskJarvis(_buildSubtaskMessage(sub))`.

### Helper methods in `_TaskInlineExpandState`

```dart
String _buildTaskMessage() {
  final title = _taskTitle;
  final desc = _description; // already computed in build()
  if (desc.isEmpty) return 'עזור לי עם המשימה: "$title"';
  return 'עזור לי עם המשימה: "$title"\nפרטים: $desc';
}

String _buildSubtaskMessage(Map<String, dynamic> sub) {
  final text = sub['content']?.toString() ?? '';
  return 'עזור לי עם: "$text" (מתוך: "$_taskTitle")';
}
```

---

## Critical files

| File | Change |
|---|---|
| `task_inline_expand.dart` | Remove enhance-on-type; add collapsible suggestions; add `onAskJarvis` prop + task button + subtask icons |
| `smart_task_card.dart` | Add `onAskJarvis` prop, pass to `TaskInlineExpand` |
| `tasks_screen.dart` | Add `onAskJarvis` prop, pass to `SmartTaskCard` |
| `productivity_screen.dart` | Add `onAskJarvis` prop, pass to `TasksScreen` |
| `main_shell.dart` | Pass `onAskJarvis` to `ProductivityScreen` with the tab-switch logic |

---

## Verification

1. `flutter analyze` — no new errors.
2. Expand a task card → suggestions section is **collapsed** by default.
3. Tap the toggle → section expands with cards.
4. Tap a card once → highlights. Tap again → subtask added, card animates out.
5. Typing in the add-subtask field → **no** ✨ chip appears (enhance removed).
6. Tap 🤖 on a task → app switches to Chat tab, input pre-filled with task title.
7. Tap 💬 on a subtask → chat pre-filled with subtask text + parent title.
8. Tap send in chat → message sent normally.
