# Tasks Inline Expand v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the AI suggestions section in the task inline expand (collapsible large cards, two-tap-to-add), remove the LLM enhance-on-type mechanism, and add an "Ask Jarvis" deep-link on every task and subtask that switches to the Chat tab with context pre-filled.

**Architecture:** Thread a nullable `void Function(String)` callback (`onAskJarvis`) from `MainShell` → `ProductivityScreen` → `TasksScreen` → `SmartTaskCard` → `TaskInlineExpand`. Re-use the existing `_pendingChatCommand` / `pendingCommand` flow already wired in `MainShell` — no new state needed. All five file changes are independent and stackable; each task can be verified with `flutter analyze`.

**Tech Stack:** Flutter/Dart, `AnimatedContainer` for collapsible section, existing `JC` colour tokens (`JC.indigo300/500`, `JC.textMuted`).

---

## File Map

| File | Change |
|---|---|
| `jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart` | Core redesign: remove enhance-on-type, add collapsible suggestions, add `onAskJarvis` prop + 🤖 action + 💬 subtask icons |
| `jarvis_mobile/lib/widgets/tasks/smart_task_card.dart` | Add `onAskJarvis` prop, pass to `TaskInlineExpand` |
| `jarvis_mobile/lib/screens/tasks_screen.dart` | Add `onAskJarvis` prop, pass to `SmartTaskCard` |
| `jarvis_mobile/lib/screens/productivity_screen.dart` | Add `onAskJarvis` prop, pass to `TasksScreen` |
| `jarvis_mobile/lib/main_shell.dart` | Pass `onAskJarvis` to `ProductivityScreen` |

---

## Task 1 — Remove enhance-on-type from `task_inline_expand.dart`

**Files:**
- Modify: `jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart`

- [ ] **Step 1.1 — Delete the three enhance state fields**

In `_TaskInlineExpandState`, remove:
```dart
Timer? _enhanceDebounce;
String? _enhancedText;
bool _enhancing = false;
```

- [ ] **Step 1.2 — Delete `_onSubtaskChanged` and `_enhance` methods**

Remove both methods entirely:
```dart
// DELETE this:
void _onSubtaskChanged(String text) { ... }
// DELETE this:
Future<void> _enhance(String text) async { ... }
```

- [ ] **Step 1.3 — Remove `onChanged` from the TextField and `dart:async` import if unused**

In the `TextField` widget inside `build()`, delete the `onChanged: _onSubtaskChanged` line.

Check if `Timer` is used anywhere else; if not, remove `import 'dart:async';`.

- [ ] **Step 1.4 — Delete the ✨ chip widget**

Remove the entire block guarded by `if (_enhancedText != null)` (the `GestureDetector` + `Container` with the indigo chip below the add-subtask row).

- [ ] **Step 1.5 — Remove enhance spinner from the input row**

In the row that contains the add-subtask `TextField`, the trailing widget has three branches:
- `if (_addingSubtask)` spinner — **keep**
- `else if (_enhancing)` spinner — **delete**
- `else` return button — **keep**

Simplify to two branches:
```dart
if (_addingSubtask)
  SizedBox(
    width: 16, height: 16,
    child: CircularProgressIndicator(strokeWidth: 1.5, color: JC.blue400),
  )
else
  GestureDetector(
    onTap: _addSubtask,
    child: Icon(Icons.keyboard_return_rounded, size: 16, color: JC.blue400),
  ),
```

- [ ] **Step 1.6 — Verify**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && dart analyze lib/widgets/tasks/task_inline_expand.dart 2>&1 | grep -E "error|warning" | head -20
```
Expected: no errors.

- [ ] **Step 1.7 — Commit**

```bash
git add jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart
git commit -m "refactor(tasks): remove LLM enhance-on-type from inline expand"
```

---

## Task 2 — Redesign suggestions section (collapsible large cards)

**Files:**
- Modify: `jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart`

- [ ] **Step 2.1 — Add `_suggestionsOpen` state field**

In `_TaskInlineExpandState`, add:
```dart
bool _suggestionsOpen = false;
```

- [ ] **Step 2.2 — Add `_selectedSuggestion` state field for the two-tap mechanic**

```dart
int? _selectedSuggestionIndex;
```

- [ ] **Step 2.3 — Replace the current suggestions section in `build()`**

Find and replace the entire `// ── AI subtask suggestions ──` block (from the `if (suggestionsLoading || suggestions.isNotEmpty)` check through its closing `),`) with the new collapsible design below.

**New suggestions section:**

```dart
// ── AI subtask suggestions (collapsible) ─────────────────────────────
if (suggestionsLoading || suggestions.isNotEmpty)
  Container(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: JC.border, width: 0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toggle row
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _suggestionsOpen = !_suggestionsOpen;
            _selectedSuggestionIndex = null;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text('הצעות חכמות',
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 12,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 6),
                if (suggestionsLoading)
                  SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: JC.indigo300),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: JC.indigo500.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: JC.indigo300.withValues(alpha: 0.25),
                          width: 0.8),
                    ),
                    child: Text('${suggestions.length}',
                        style: TextStyle(
                            color: JC.indigo300,
                            fontSize: 10,
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700)),
                  ),
                const Spacer(),
                AnimatedRotation(
                  turns: _suggestionsOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: JC.textMuted),
                ),
              ],
            ),
          ),
        ),

        // Collapsible cards
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _suggestionsOpen
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              children: [
                for (var i = 0; i < suggestions.length && i < 5; i++)
                  _buildSuggestionCard(suggestions, i),
              ],
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    ),
  ),
```

- [ ] **Step 2.4 — Add `_buildSuggestionCard` helper method**

Add this method to `_TaskInlineExpandState`:

```dart
Widget _buildSuggestionCard(List<dynamic> suggestions, int i) {
  final isSelected = _selectedSuggestionIndex == i;
  final text = suggestions[i]['text']?.toString() ?? '';
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (isSelected) {
          // Second tap — add
          setState(() => _selectedSuggestionIndex = null);
          await _c.acceptSuggestionAsSubtask(_t, text);
          await _loadSubtasks();
        } else {
          // First tap — select
          setState(() => _selectedSuggestionIndex = i);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? JC.indigo500.withValues(alpha: 0.14)
              : JC.indigo500.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected
                ? JC.indigo300
                : JC.indigo300.withValues(alpha: 0.18),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: JC.indigo500.withValues(alpha: isSelected ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Center(
                child: Icon(Icons.add_task_rounded,
                    size: 13, color: JC.indigo300),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: isSelected ? JC.indigo300 : JC.textSecondary,
                    fontSize: 12.5,
                    fontFamily: 'Heebo',
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              opacity: isSelected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Text('הוסף',
                  style: TextStyle(
                      color: JC.indigo300,
                      fontSize: 10.5,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2.5 — Verify**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && dart analyze lib/widgets/tasks/task_inline_expand.dart 2>&1 | grep -E "error|warning" | head -20
```
Expected: no errors.

- [ ] **Step 2.6 — Commit**

```bash
git add jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart
git commit -m "feat(tasks): collapsible AI suggestion cards in inline expand"
```

---

## Task 3 — Add `onAskJarvis` to `TaskInlineExpand`

**Files:**
- Modify: `jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart`

- [ ] **Step 3.1 — Add prop to `TaskInlineExpand`**

In the `TaskInlineExpand` widget class, add:
```dart
final void Function(String)? onAskJarvis;
```

And in the constructor:
```dart
const TaskInlineExpand({
  super.key,
  required this.controller,
  required this.task,
  this.onAskJarvis,       // ← add this
});
```

- [ ] **Step 3.2 — Add `_buildTaskMessage` and `_buildSubtaskMessage` helpers**

Add to `_TaskInlineExpandState`:

```dart
String _buildTaskMessage() {
  final desc = _description; // computed in build() — pull out to a getter
  if (desc.isEmpty) return 'עזור לי עם המשימה: "$_taskTitle"';
  return 'עזור לי עם המשימה: "$_taskTitle"\nפרטים: $desc';
}

String _buildSubtaskMessage(Map<String, dynamic> sub) {
  final text = sub['content']?.toString() ?? '';
  return 'עזור לי עם: "$text" (מתוך: "$_taskTitle")';
}
```

Also extract the description computation from `build()` into a getter so both `build()` and `_buildTaskMessage()` can use it:

```dart
String get _description {
  final rawContent = _t['content']?.toString() ?? '';
  final withoutAI = rawContent.contains('\n<<<AI_PROMPT>>>\n')
      ? rawContent.split('\n<<<AI_PROMPT>>>\n').first
      : rawContent;
  final lines = withoutAI.split('\n');
  return lines.length > 1 ? lines.skip(1).join('\n').trim() : '';
}
```

Then in `build()` replace the four lines that compute `rawContent / withoutAI / contentLines / description` with:
```dart
final description = _description;
```

- [ ] **Step 3.3 — Add 🤖 button to the action row**

In `build()`, find the action row `Container` at the bottom. Replace:
```dart
child: Row(
  children: [
    _actionBtn(
        icon: Icons.edit_note_rounded,
        label: 'עוד פרטים',
        color: JC.blue400,
        onTap: () => _openFullEdit(context)),
    const Spacer(),
    _actionBtn(
        icon: Icons.delete_outline_rounded,
        label: 'מחק',
        color: JC.cancelRed,
        onTap: () {
          Navigator.of(context, rootNavigator: false);
          _c.deleteTask(_t);
        }),
  ],
),
```

With:
```dart
child: Row(
  children: [
    _actionBtn(
        icon: Icons.edit_note_rounded,
        label: 'עוד פרטים',
        color: JC.blue400,
        onTap: () => _openFullEdit(context)),
    if (widget.onAskJarvis != null) ...[
      const Spacer(),
      _actionBtn(
          icon: Icons.smart_toy_outlined,
          label: 'שוחח עם ג\'רוויס',
          color: JC.indigo300,
          onTap: () => widget.onAskJarvis!(_buildTaskMessage())),
    ],
    const Spacer(),
    _actionBtn(
        icon: Icons.delete_outline_rounded,
        label: 'מחק',
        color: JC.cancelRed,
        onTap: () {
          Navigator.of(context, rootNavigator: false);
          _c.deleteTask(_t);
        }),
  ],
),
```

- [ ] **Step 3.4 — Add 💬 icon to each subtask row**

In `build()`, find the subtask rows section:
```dart
for (final sub in _subtasks)
  _SubtaskRow(
    subtask: sub,
    onToggle: () => _toggleSubtask(sub),
  ),
```

Replace with:
```dart
for (final sub in _subtasks)
  _SubtaskRow(
    subtask: sub,
    onToggle: () => _toggleSubtask(sub),
    onAskJarvis: widget.onAskJarvis != null
        ? () => widget.onAskJarvis!(_buildSubtaskMessage(sub))
        : null,
  ),
```

- [ ] **Step 3.5 — Add `onAskJarvis` to `_SubtaskRow`**

Find the `_SubtaskRow` class at the bottom of the file and update it:

```dart
class _SubtaskRow extends StatelessWidget {
  final Map<String, dynamic> subtask;
  final VoidCallback onToggle;
  final VoidCallback? onAskJarvis;    // ← add

  const _SubtaskRow({
    required this.subtask,
    required this.onToggle,
    this.onAskJarvis,                 // ← add
  });

  @override
  Widget build(BuildContext context) {
    final done = subtask['done'] == true;
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 3, 14, 3),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: done ? JC.blue400.withValues(alpha: 0.6) : JC.border,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtask['content']?.toString() ?? '',
                style: TextStyle(
                  color: done ? JC.textMuted : JC.textSecondary,
                  fontSize: 12.5,
                  fontFamily: 'Heebo',
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (onAskJarvis != null)         // ← add trailing icon
              GestureDetector(
                onTap: onAskJarvis,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Icon(Icons.chat_bubble_outline_rounded,
                      size: 13, color: JC.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3.6 — Verify**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && dart analyze lib/widgets/tasks/task_inline_expand.dart 2>&1 | grep -E "error|warning" | head -20
```
Expected: no errors.

- [ ] **Step 3.7 — Commit**

```bash
git add jarvis_mobile/lib/widgets/tasks/task_inline_expand.dart
git commit -m "feat(tasks): Ask Jarvis button on task + subtask rows"
```

---

## Task 4 — Thread `onAskJarvis` through `SmartTaskCard`

**Files:**
- Modify: `jarvis_mobile/lib/widgets/tasks/smart_task_card.dart`

- [ ] **Step 4.1 — Add prop to `SmartTaskCard`**

In `SmartTaskCard`:
```dart
class SmartTaskCard extends StatefulWidget {
  final TasksController controller;
  final Map<String, dynamic> task;
  final bool dense;
  final bool draggableMode;
  final void Function(String)? onAskJarvis;   // ← add

  const SmartTaskCard({
    super.key,
    required this.controller,
    required this.task,
    this.dense = false,
    this.draggableMode = false,
    this.onAskJarvis,                          // ← add
  });
```

- [ ] **Step 4.2 — Pass `onAskJarvis` to `TaskInlineExpand`**

In `_SmartTaskCardState.build()`, find:
```dart
if (_expanded)
  TaskInlineExpand(
    controller: widget.controller,
    task: widget.task,
  ),
```

Replace with:
```dart
if (_expanded)
  TaskInlineExpand(
    controller: widget.controller,
    task: widget.task,
    onAskJarvis: widget.onAskJarvis,
  ),
```

- [ ] **Step 4.3 — Verify**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && dart analyze lib/widgets/tasks/smart_task_card.dart 2>&1 | grep -E "error|warning" | head -20
```
Expected: no errors.

- [ ] **Step 4.4 — Commit**

```bash
git add jarvis_mobile/lib/widgets/tasks/smart_task_card.dart
git commit -m "feat(tasks): thread onAskJarvis through SmartTaskCard"
```

---

## Task 5 — Thread `onAskJarvis` through `TasksScreen`

**Files:**
- Modify: `jarvis_mobile/lib/screens/tasks_screen.dart`

- [ ] **Step 5.1 — Add prop to `TasksScreen`**

```dart
class TasksScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;
  final ValueListenable<int>? addTrigger;
  final void Function(String)? onAskJarvis;   // ← add

  const TasksScreen({
    super.key,
    required this.settings,
    this.onCountUpdate,
    this.addTrigger,
    this.onAskJarvis,                          // ← add
  });
```

- [ ] **Step 5.2 — Pass to `SmartTaskCard`**

In `_TasksScreenState`, find every place `SmartTaskCard` is constructed (search for `SmartTaskCard(`) and add `onAskJarvis: widget.onAskJarvis` to each call site. There are typically 1–2 locations inside the list-building helpers.

To find them:
```bash
grep -n "SmartTaskCard(" /home/user/jarvis-server-nadav/jarvis_mobile/lib/screens/tasks_screen.dart
```

For each result, add the prop:
```dart
SmartTaskCard(
  controller: _c,
  task: task,
  onAskJarvis: widget.onAskJarvis,   // ← add
),
```

- [ ] **Step 5.3 — Verify**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && dart analyze lib/screens/tasks_screen.dart 2>&1 | grep -E "error|warning" | head -20
```
Expected: no errors.

- [ ] **Step 5.4 — Commit**

```bash
git add jarvis_mobile/lib/screens/tasks_screen.dart
git commit -m "feat(tasks): thread onAskJarvis through TasksScreen"
```

---

## Task 6 — Thread `onAskJarvis` through `ProductivityScreen` and `MainShell`

**Files:**
- Modify: `jarvis_mobile/lib/screens/productivity_screen.dart`
- Modify: `jarvis_mobile/lib/main_shell.dart`

- [ ] **Step 6.1 — Add prop to `ProductivityScreen`**

```dart
class ProductivityScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onTasksCountUpdate;
  final ValueChanged<int>? onRemindersCountUpdate;
  final VoidCallback? onOpenDrawer;
  final ValueListenable<int>? jumpToTab;
  final void Function(String)? onAskJarvis;   // ← add

  const ProductivityScreen({
    super.key,
    required this.settings,
    this.onTasksCountUpdate,
    this.onRemindersCountUpdate,
    this.onOpenDrawer,
    this.jumpToTab,
    this.onAskJarvis,                          // ← add
  });
```

- [ ] **Step 6.2 — Pass to `TasksScreen` inside `ProductivityScreen`**

Find the `TasksScreen(` constructor call inside `_ProductivityScreenState.build()`:
```dart
TasksScreen(
  settings: widget.settings,
  onCountUpdate: widget.onTasksCountUpdate,
  addTrigger: _addTaskNotifier,
),
```

Add:
```dart
TasksScreen(
  settings: widget.settings,
  onCountUpdate: widget.onTasksCountUpdate,
  addTrigger: _addTaskNotifier,
  onAskJarvis: widget.onAskJarvis,   // ← add
),
```

- [ ] **Step 6.3 — Wire up in `MainShell`**

In `main_shell.dart`, find the `ProductivityScreen(` instantiation:
```dart
ProductivityScreen(
  settings: _settings,
  onOpenDrawer: _openDrawer,
  jumpToTab: _productivityTab,
),
```

Replace with:
```dart
ProductivityScreen(
  settings: _settings,
  onOpenDrawer: _openDrawer,
  jumpToTab: _productivityTab,
  onAskJarvis: (msg) {
    setState(() {
      _pendingChatCommand = msg;
      _selectedIndex = 1;
    });
  },
),
```

- [ ] **Step 6.4 — Verify full project**

```bash
cd /home/user/jarvis-server-nadav/jarvis_mobile && dart analyze lib/ 2>&1 | grep -E "error|warning" | head -30
```
Expected: no errors.

- [ ] **Step 6.5 — Commit**

```bash
git add jarvis_mobile/lib/screens/productivity_screen.dart jarvis_mobile/lib/main_shell.dart
git commit -m "feat(tasks): wire onAskJarvis to MainShell chat tab switch"
```

---

## Task 7 — Push and open PR

- [ ] **Step 7.1 — Push branch**

```bash
git push -u origin fix/tasks-card-ux-and-cleanup
```

- [ ] **Step 7.2 — Open draft PR**

Title: `feat(tasks): inline expand v2 — collapsible AI suggestions + Ask Jarvis`

Body:
```
## Summary
- Removes LLM enhance-on-type from the add-subtask field (debounce/✨ chip)
- Redesigns AI suggestions as a collapsible section (collapsed by default):
  - Toggle row shows count badge + chevron
  - Full-width card items; tap once to select, tap again to add
- Adds "שוחח עם ג'רוויס" button in the task action row
- Adds 💬 icon on each subtask row
- Both open the Chat tab (tab 1) with context pre-filled in the input field

## Test plan
- [ ] Expand a task → suggestions section collapsed by default
- [ ] Tap toggle → cards animate open
- [ ] Tap a card once → highlights; tap again → subtask added, card gone
- [ ] Type in add-subtask field → no ✨ chip appears
- [ ] Tap 🤖 → Chat tab opens, input has "עזור לי עם המשימה: ..."
- [ ] Tap 💬 on subtask → Chat input has subtask + parent context
```
