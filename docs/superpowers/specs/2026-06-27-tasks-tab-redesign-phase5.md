# Tasks Tab Redesign — Phase 5

**Date:** 2026-06-27  
**Status:** Approved  

---

## Problem

The current tasks tab (after Phase 1–2) has a unified toolbar and clean cards but the user still doesn't connect with the experience. Specific friction points:
- No checkbox-style completion gesture (tap circle)
- Add sheet is a generic bottom sheet, not a smart capture tool
- Task details live in a separate full-screen edit sheet rather than inline
- No AI planning / advice surface
- Swipe actions missing

## Goal

Rebuild the tasks tab around three interaction pillars:
1. **View** — flexible, switchable views with smart grouping
2. **Act** — tap circle to complete; tap card to expand inline; swipe to dismiss
3. **Capture** — FAB + natural-language with live token parsing

Plus a fourth pillar:
4. **Advise** — on-demand AI planning sheet surfaced via a ✨ badge button

---

## Screen Layout

### Header
- Large bold title: `"משימות"` (24px, w800)
- Avatar circle (user initial) on the left
- Below title: horizontal scrollable pill row for views

### View Pills
Four pills, one active at a time:

| Pill | Logic |
|------|-------|
| היום | Tasks due today + overdue |
| השבוע | Tasks due within 7 days |
| הכל | All open tasks |
| פרויקט | Group by project |

Active pill: `JC.blue500` background tint + blue text + blue border.  
Inactive: `JC.surfaceAlt` + muted text.

### AI Advisor Badge (✨)
- Small icon button in the top-right of the header row (or end of pill row)
- Shows a red dot badge when the AI has pending insights
- Tapping opens the AI Advisor sheet (see section below)

### Task List
Grouped by time-of-day when in **היום** / **השבוע** view:

| Group | Logic |
|-------|-------|
| בוקר | due_date time 06:00–12:00 |
| אחה"צ | 12:00–18:00 |
| ערב | 18:00–24:00 |
| ללא תאריך | due_date is null |
| פג תוקף | overdue (due_date < today) — shown first, red accent |

In **הכל** view: flat list ordered by created_at desc.  
In **פרויקט** view: one section per project name.

Section header: uppercase label (11px, muted) + count badge on left.

---

## Task Card

```
[●]  כותרת המשימה                    
     [📅 תאריך] [💼 פרויקט] [#תגית]
```

- **Circle (●)**: 22px, border-only, color = priority:
  - high → `JC.cancelRed`
  - medium → `JC.amber400`
  - low → `JC.green500`
  - no priority → `JC.border`
- Tap circle → mark done (strike-through title, circle fills blue ✓, row fades to 50% opacity)
- **Title**: 14px, w500, `JC.textPrimary`; done = line-through + `JC.textMuted`
- **Chips** (below title, 5px gap): date chip (green or red if overdue), project chip (purple), tag chips (blue, max 2 visible)

### Swipe Left
Reveals two action buttons sliding in from the left:
- **דחייה** (blue): sets due_date = tomorrow, collapses swipe
- **מחיקה** (red): deletes with undo snackbar (3s)

---

## Inline Expand Panel

Tap anywhere on the card body (not the circle) → expand panel slides open below the card. Tap again → collapses.

### Properties (each row is tappable → opens relevant picker/input)

| Icon | Label | Widget on tap |
|------|-------|---------------|
| 📅 | תאריך | Date + time picker |
| 🔴/🟡/🟢 | עדיפות | Three-chip selector |
| 🔁 | חזרה | Recurrence selector (חד-פעמי / יומי / שבועי / חודשי) |
| 📁 | פרויקט | Project dropdown |
| 🏷 | תגיות | Tag input (existing tag chips + text field) |

### Smart Subtasks
Below properties:

1. **AI suggestions strip** — appears immediately on expand (loaded lazily after first expand):
   - Shows 3–5 suggested subtask chips based on task title + project + tags
   - Tapping a chip adds it as a subtask instantly
   - Chips: `JC.indigo300` tint, prefix `＋`
   - Example: task "פגישה עם לקוח א׳" → suggests `＋ להכין מצגת`, `＋ לשלוח אג׳נדה`, `＋ לאשר נוכחות`

2. **Existing subtasks list** — checkbox rows; tap checkbox = toggle done

3. **Manual add field** — text input with autocomplete:
   - As user types, AI suggests completions inline (ghost text)
   - Press Tab or → to accept; Enter to save

### Action Row (bottom of expand panel)
`📝 הערה` · `🗑 מחק` — small text buttons, danger style for delete.

---

## FAB Capture Sheet

Floating action button (bottom-left, gradient blue→purple).  
Tap → bottom sheet slides up with dim overlay behind.

### Sheet Contents

**NL Input field**
- Large text field, auto-focused, RTL
- Blue glow border while active
- Placeholder: `"מה צריך לעשות? (לדוגמה: פגישה מחר ב-10 עם דן)"`

**Live Token Row** (updates on every keystroke, debounced 150ms)
- Calls a local parser first (date/time regexes) for instant feedback
- Calls `/ask-jarvis` with intent `task_parse` for richer entity extraction (name, priority keywords, project name)
- Shows tokens as colored chips:
  - 📝 Title → blue
  - 📅 Date → green
  - ⏰ Time → cyan
  - 🔴 Priority → red
  - 💼 Project → purple
- Empty state: `"מקלד כדי לזהות..."` in muted text

**Submit Button**
- Full-width, gradient background
- Label: `"הוסף משימה ↑"`
- Disabled when text empty

---

## AI Advisor Sheet

Opened by tapping ✨ badge button in header.  
Full-height bottom sheet (90% of screen).

### Sections

**1. ניתוח נוכחי** (auto-loaded on open)
- Calls `/ask-jarvis` with the user's open task list as context
- Displays 3–5 bullet insights, e.g.:
  - "5 משימות עם עדיפות גבוה אין להן תאריך"
  - "עומס כבד ביום שלישי — 4 דדליינים"
  - "3 משימות לא נגעת בהן 14+ יום"

**2. המלצות פעולה**
- Tappable recommendation cards:
  - "סדר עדיפויות מחדש" → AI reorders open tasks by urgency
  - "הצע חלוקה לשבוע" → AI assigns tasks to days of the week
  - "מצא משימות לדחייה" → AI suggests low-priority tasks to postpone

**3. שאל את ה-AI**
- Open text field: "מה אתה רוצה לשפר?"
- Sends to `/ask-jarvis`, displays response below

### Badge Logic
The ✨ button shows a red dot badge when:
- Any task is overdue by more than 2 days
- More than 3 high-priority tasks have no due date
- The user hasn't opened the advisor in more than 7 days and has 5+ open tasks

Badge state is computed locally from the loaded task list (no extra API call).

---

## Removed / Changed vs Current

| Current | New |
|---------|-----|
| SmartDayHeader collapsible band | **Removed** — replaced by AI Advisor sheet |
| TasksToolbar with group-mode pills + filter icon | **Replaced** — view pills in header; filter icon kept as optional |
| Long-press → edit sheet | **Replaced** — tap → inline expand |
| `_showAddSheet` (simple bottom sheet) | **Replaced** — FAB + NL capture sheet |
| No swipe actions | **Added** — swipe left: postpone + delete |
| AI suggestions button inside edit sheet | **Moved** — to inline expand (smart subtasks) |

The full `TaskEditSheet` widget is **retained** as fallback (accessible from expand panel overflow or "עוד פרטים" link) for power-user editing.

---

## Files Changed

| File | Change |
|------|--------|
| `jarvis_mobile/lib/screens/tasks_screen.dart` | Full rewrite of build/list/add-sheet logic |
| `jarvis_mobile/lib/widgets/tasks/tasks_toolbar.dart` | May be simplified or removed |
| `jarvis_mobile/lib/widgets/tasks/smart_task_card.dart` | Replace with new card + expand panel |
| `jarvis_mobile/lib/widgets/tasks/smart_day_header.dart` | Remove from tasks tab (keep file for possible reuse) |
| `jarvis_mobile/lib/widgets/tasks/task_capture_sheet.dart` | **NEW** — NL capture with live token parsing |
| `jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart` | **NEW** — inline expand panel with properties + smart subtasks |
| `jarvis_mobile/lib/widgets/tasks/ai_advisor_sheet.dart` | **NEW** — AI planning/advice sheet |
| `jarvis_mobile/lib/services/api_service.dart` | Add `parseTaskNL()` and `getTaskInsights()` methods |

---

## Verification

1. `flutter analyze` — no new errors
2. View pills switch correctly; correct tasks appear per view
3. Tap circle → task marked done; tap again → undone
4. Swipe left → postpone sets tomorrow; delete removes with snack undo
5. Tap card body → expand opens; tap again → closes
6. Expand: tap date → picker opens; change persists on close
7. Smart subtasks: suggestions appear within 2s; tapping adds subtask
8. Manual subtask add with autocomplete ghost text
9. FAB → sheet opens; typing "מחר ב-10" → date+time tokens appear live
10. Submit → task created, sheet closes, list updates
11. ✨ badge shows when overdue tasks exist; sheet opens with analysis
12. AI advisor: "הצע חלוקה לשבוע" returns actionable plan
