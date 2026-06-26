# Voice Panel UI Refresh — Design Spec

**Goal:** Refresh the VoicePanel layout — smaller orb, full chat history, less aggressive red button, gradient background.

**Current state:** 220px orb at bottom-center with "הקש לטקסט" text overlay, no message history, prominent 64px red button, radial gradient element at bottom.

---

## Layout Change (top → bottom)

Replace the current Stack-based layout with a cleaner Column:

1. **Background** — `Container` with `BoxDecoration(gradient: LinearGradient)` wrapping the full Column. Vertical gradient: `JC.bg` (top) → `Color(0xFF0D1B3E)` (dark blue, bottom). Replaces the `Positioned` radial gradient element.

2. **Message list** — `Expanded` wrapping a `ListView.builder` showing `widget.messages`. Same bubble style as TextPanel (`_Bubble` widget — duplicated into VoicePanel for now). Auto-scrolls to bottom on new messages. Empty state: plain `SizedBox.shrink()` (no empty-state widget needed — orb is the visual CTA).

3. **In-flight card** — `_InFlightCard` unchanged, shown only when `_partialUser` or `_streamingReply` is non-empty.

4. **Orb** — `JarvisOrb(size: 120)` centered in `Padding(vertical: 12)`. Remove the "הקש לטקסט" hint overlay entirely.

5. **Hint text** — unchanged (`מקשיב...` / `חושב...` / etc), `fontSize: 13`.

6. **End-call button** — `width: 44, height: 44` (was 64), `boxShadow blurRadius: 8` (was 18), icon `call_end_rounded size: 20` (was 28). `padding bottom: 16` (was 22).

---

## Removed Elements

- `Positioned` radial gradient background element
- "הקש לטקסט" text overlay inside the orb Stack
- `Stack(alignment: Alignment.center)` wrapping the orb (orb is now a plain widget)

## Scroll Behavior

Add a `ScrollController _voiceScrollCtrl` field. In `didUpdateWidget`, when `widget.messages.length` increases, call `_scrollToBottom()` (same pattern as TextPanel).

## Bubble Style

Use `_VoiceBubble` — a simplified version of TextPanel's `_Bubble`:
- Same colors (`JC.userBubble` / `JC.jarvisBubble`), same RTL text style
- No feedback buttons (👍👎) — voice conversation moves fast
- No `fromVoice` mic icon — all messages are from voice in this panel

## Files Changed

- Modify: `jarvis_mobile/lib/widgets/chat/voice_panel.dart`
  - Add `ScrollController _voiceScrollCtrl` + `_scrollToBottom()`
  - Add `_VoiceBubble` widget at bottom of file
  - Replace Stack layout with Column + gradient Container
  - Remove overlay text, resize orb to 120px
  - Resize end-call button to 44px

---

## Testing

- Messages scroll correctly in voice panel
- Auto-scroll triggers on new messages
- Orb size 120px, no "הקש לטקסט" overlay
- Red button 44px, less shadow
- Background gradient visible
- Switching voice ↔ text preserves message list
