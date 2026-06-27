# Reminders Empty State — Design Spec

**Date:** 2026-06-27
**Status:** Approved

## Problem

The reminders screen shows a minimal icon + text when no reminders exist. The screen feels bare and offers no path forward beyond the FAB.

## Goal

Turn the empty state into an engaging, action-oriented surface with three layers:
1. A polished visual banner
2. A prominent primary CTA
3. Quick-template chips + smart-idea cards that pre-fill the add sheet

Once any reminder exists the standard list renders as normal — the empty state is fully replaced.

## Layout (top → bottom)

### 1. Visual Banner
- Light indigo/blue gradient background, ~120px tall, rounded corners
- `Icons.notifications_none_rounded` centered, 48px, indigo color
- Headline: `"אין תזכורות עדיין"` (16px, bold, textPrimary)
- Sub-copy: `"הוסף את הראשונה שלך או בחר רעיון"` (13px, textSecondary)

### 2. Primary CTA Button
- `FilledButton`, full width, `JC.blue500` background
- Label: `"＋ הוסף תזכורת"`
- Tapping opens `_showReminderSheet()` with no pre-fill (standard flow)

### 3. Quick-Template Chips
- Section label: `"תבניות מהירות"` (12px, secondary, right-aligned)
- `Wrap` of 6 `GestureDetector` chips (same style as task category chips)
- Each chip taps → `_showReminderSheet(initialText: '...')`

| Chip | Pre-fill text |
|------|---------------|
| 💊 תרופות | `"תרופות"` |
| 💧 לשתות מים | `"לשתות מים"` |
| 📞 שיחה | `"שיחת טלפון"` |
| 🏃 ספורט | `"פעילות גופנית"` |
| 🛒 קניות | `"קניות"` |
| ☀️ בוקר טוב | `"בוקר טוב"` |

### 4. Smart-Idea Cards
- Section label: `"רעיונות"` (12px, secondary, right-aligned)
- 3 tappable cards; each opens `_showReminderSheet(initialText, initialRecurrence)`
- Card layout: left accent bar (indigo) + icon + title + recurrence badge

| Card | Text | Recurrence |
|------|------|------------|
| 💧 שתיית מים | `"לשתות מים"` | יומי |
| 💊 ויטמינים | `"ויטמינים"` | יומי |
| 🏃 פעילות גופנית | `"פעילות גופנית"` | שבועי |

## Implementation Notes

### `_showReminderSheet` signature change
Add optional named params to the existing function:
```dart
void _showReminderSheet({
  Map<String, dynamic>? existing,
  String? initialText,
  String? initialRecurrence,
})
```
The sheet's `TextEditingController` initialises with `initialText ?? existing?['text'] ?? ''`.
The recurrence selector initialises with `initialRecurrence ?? _normalizeRecurrence(existing?['recurrence'])`.

### Empty-state widget
Extract into a private `_EmptyState` widget inside `reminders_screen.dart`.
Receives `onAdd` callback (opens sheet normally) and `onTemplate(text, recurrence)` callback.
Keeps the screen's existing `_loading` / `_error` / `_reminders.isEmpty` guard logic.

### No new API calls
Templates and idea cards are static — no network dependency.
The existing `_showReminderSheet` flow handles persistence unchanged.

## Files changed

| File | Change |
|------|--------|
| `jarvis_mobile/lib/screens/reminders_screen.dart` | Replace inline empty-state with `_EmptyState` widget; extend `_showReminderSheet` signature |

No backend changes needed.

## Verification

1. `flutter analyze` — no new errors
2. Open reminders screen with zero reminders → banner + button + chips + cards visible
3. Tap primary button → sheet opens blank
4. Tap a chip → sheet opens with text pre-filled
5. Tap a smart-idea card → sheet opens with text + recurrence pre-filled
6. Add any reminder → empty state disappears, list renders normally
7. Delete all reminders → empty state reappears
