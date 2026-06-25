# Orb Center Position — Design Spec

**Goal:** Replace the bottom-left mini-orb FAB with a medium JarvisOrb (100px) permanently centered at the top of the text panel, tappable to switch to voice mode.

**Current state:** `TextPanel` wraps everything in a `Stack`; a `Positioned(bottom:70, left:14, width:42, height:42)` holds a mini-orb FAB.

---

## Layout Change

Replace the `Stack` root with a plain `Column`. Remove the `Positioned` FAB entirely.

New Column order (top → bottom):

1. **Center Orb** — `JarvisOrb(size: 100, state: JarvisState.idle, onTap: switchToVoice)` inside a `Padding(vertical: 16) → Center`
2. **Message list** — `Expanded` wrapping `AnimatedList` or empty-state widget
3. **File preview** — `AnimatedSize` (unchanged)
4. **Input bar** — `_InputBar` (unchanged)

## Orb Behaviour

- State: always `JarvisState.idle` while in text mode (no audio level input).
- `onTap`: `HapticFeedback.mediumImpact()` then `widget.onSwitchToVoice?.call()`.
- `explosionEnabled`: follow `widget.settings.orbExplosionEnabled` (same as voice panel).
- Color overrides: follow `widget.settings.orbCustomColors` (same as voice panel).
- Show orb regardless of whether `onSwitchToVoice` is null (just non-tappable if null).

## Empty State

Keep the existing `_buildEmptyState()` widget (star icon + "שלום! איך אוכל לעזור?") below the orb in the `Expanded` area when `widget.messages.isEmpty`. The orb is the primary visual CTA; the text is secondary.

## Removed Code

- `Positioned` mini-orb FAB block in `build()`
- `_showVoiceTooltip()` method
- `OverlayEntry? _fabTooltipEntry` field
- `_fabTooltipEntry?.remove()` in `dispose()`
- `Stack` wrapper (replaced by `Column`)
- Import of `package:flutter/services.dart` is still needed (HapticFeedback used in orb onTap)

## Files Changed

- Modify: `jarvis_mobile/lib/widgets/chat/text_panel.dart`
  - Remove Stack, Positioned FAB, tooltip overlay
  - Add center orb at top of Column

## Testing

- Tapping the center orb switches to VoicePanel
- Input bar buttons (send, mic, attach) remain fully responsive
- With messages: orb visible above the list, list scrolls independently
- Without messages: orb + empty-state hint visible
- Long press on orb: no special behaviour (tooltip removed)
