# Constellation Graph Physics + Animation — Design Spec
**Date:** 2026-07-01
**File:** `jarvis-brain.html`
**Scope:** קונסטלציה tab — 2D drag momentum, real 3D node physics, click/press pulse effect, entrance animation

---

## 1. Background

The constellation tab's memory graph already shipped a v2 upgrade (2D physics simulation with repulsion/springs/hub-pull, drag, tooltip, focus mode, search highlight). This spec adds the remaining physics/animation polish the user asked for, kept deliberately separate from the Thinking + Profile tabs v2 work (a different subsystem — motion/physics rather than data visualization):

1. Momentum/inertia when releasing a dragged node in the 2D graph (currently velocity is force-reset to 0 on release, so the node stops dead)
2. Real node-to-node physics simulation in the 3D graph (currently nodes sit at fixed positions on a Fibonacci-lattice sphere; only the camera rotates — nothing about the layout is physics-driven)
3. A click/press pulse effect on node interaction, in both 2D and 3D
4. An entrance animation for nodes when the graph is (re)built

This spec does **not** touch the Knowledge or Thinking/Profile tabs (both already shipped), and does not add node-dragging to the 3D view (out of scope — the 3D ask was specifically "real physics," not "draggable nodes").

---

## 2. 2D Drag Momentum

### 2.1 Current behavior
`startGraph2D()`'s `svg.onpointermove` handler (while `_g2dDrag` is set) directly assigns `n.x`/`n.y` to the cursor position and resets `n.vx = 0; n.vy = 0;` every move event. `svg.onpointerup` just clears `_g2dDrag = null` — the node's velocity is already zero at that point, so it stops instantly.

### 2.2 Target behavior
Track the node's velocity from actual pointer movement during the drag, and preserve it on release so the existing per-frame integration loop (`n.vx = ((n.vx||0) + centering)*.85`) carries the motion forward and lets it decay naturally — friction factor **0.95** (user-selected "medium glide," between the existing loop's `.85` per-frame damping toward center and a fully free-floating feel).

- During `onpointermove` while dragging: instead of zeroing velocity, compute `vx`/`vy` from the delta between this move event and the last one (`(newX - lastX) / dt`, scaled to match the simulation's per-frame units), and store it on the node.
- On `onpointerup`: leave the node's `vx`/`vy` as-is (don't zero them), and set a new per-node counter `releaseGlide = 20` (frames). The existing `frame()` loop's damping (`* .85` toward center, plus repulsion/springs) already handles decay once the node re-enters the normal simulation — no separate momentum-decay loop is needed.
- The one addition, so the release feels like the demoed "0.95 glide" rather than the sharper `.85` used for ordinary center-seeking: inside `frame()`'s existing per-node integration step, if `releaseGlide > 0`, multiply the node's velocity by an extra `0.95` factor before the normal `*.85` damping is applied, and decrement `releaseGlide`. Once it reaches `0`, the node behaves exactly as before (normal simulation damping only, no special-casing).

### 2.3 What does NOT change
- Repulsion, semantic springs, hub-pull, and center-gravity forces are untouched
- Multi-touch / simultaneous drags — out of scope, matches existing single-drag (`_g2dDrag = { idx }`) limitation

---

## 3. Real 3D Node Physics

### 3.1 Current behavior
`startGraph3D()` builds `_g3dNodes` with `ox/oy/oz` as **fixed unit vectors** placed via a Fibonacci sphere lattice (`phi`/`theta` formula) — these values are set once at creation and never updated. Each animation frame, `_draw3dFrame()` only recomputes the camera rotation (`_g3dAngleH`/`_g3dAngleV`) and reprojects the same fixed 3D points to 2D screen space. There is no notion of nodes moving relative to each other.

### 3.2 Target behavior
`ox/oy/oz` become **live, physics-driven coordinates**, updated every frame before projection — mirroring the 2D simulation's force model, adapted to 3D:

- **Repulsion:** every leaf-node pair repels along the 3D vector between them (same inverse-distance-squared shape as 2D's `REPEL*REPEL/d`, scaled down to this space's unit-sphere coordinate range, e.g. `REPEL_3D ≈ 0.16`)
- **Semantic springs:** edges (already built via `buildSemanticEdges`, reused as-is) pull connected nodes toward a target distance, weighted by edge strength — same shape as 2D's spring force
- **Hub pull:** each leaf is pulled toward its category's hub node once it drifts past a target distance, same shape as 2D
- **Radial containment:** a gentle spring pulls each node's distance from the origin back toward `1.0` (the original unit-sphere radius), so the simulation stays inside the existing camera framing (`RW`/`RH`/perspective-scale constants in `_draw3dFrame` are untouched — this is what keeps them valid without retuning)
- **Damping:** velocity decays each frame (`~0.85`, matching 2D), reaching a stable equilibrium rather than oscillating forever

New per-node fields: `vx`, `vy`, `vz` (initialized to 0 at creation, alongside the existing `ox`/`oy`/`oz`).

A new function, `_stepGraph3DPhysics()`, runs once per animation frame **before** `_draw3dFrame()` inside `startGraph3D()`'s existing `frame()` loop — it mutates `ox/oy/oz` in place; `_draw3dFrame()` itself needs no changes beyond reading the now-live values it already reads.

### 3.3 What does NOT change
- Camera orbit (drag-to-rotate the whole view), click-to-select, double-click-to-focus, and the `_g3dHandleClick`/`_g3dOrbit` interaction model are untouched
- No node dragging is added to the 3D view
- `RW`, `RH`, perspective-scale formula, and all rendering/highlighting logic in `_draw3dFrame()` are untouched

---

## 4. Click/Press Pulse Effect

### 4.1 Trigger points (per user selection)
- Clicking/tapping a node — both 2D (`svg.onclick`) and 3D (`_g3dHandleClick`)
- Starting a drag — 2D only (`svg.onpointerdown`, when a valid drag target is found)

### 4.2 Mechanism
A new per-node field, `pulse` (0 to 1, default 0), set to `1` at the trigger points above. Each animation frame, for any node with `pulse > 0`:
- Decay it (`pulse *= 0.9` per frame, or equivalent time-based decay so the effect lasts roughly 300-400ms regardless of frame rate)
- Temporarily boost the rendered radius by `pulse * pulseBoost` (e.g. `pulseBoost ≈ 6` for 2D SVG circles, scaled appropriately for 3D's screen-space radius)

This reuses the existing per-frame imperative rendering approach already used throughout this file (direct SVG attribute updates in 2D, direct canvas redraw in 3D) rather than introducing CSS animations, since neither the 2D nodes (attribute-driven `<circle r="...">`) nor the 3D nodes (canvas `ctx.arc()`, no DOM elements at all) have a CSS-animatable target.

### 4.3 What does NOT change
- Existing tooltip-on-click, hub-highlight-on-click, and focus-mode-on-double-click behavior — the pulse is purely additive visual feedback layered on top

---

## 5. Entrance Animation

### 5.1 Target behavior ("converge from center + fade," per user selection)
When `startGraph2D()` or `startGraph3D()` (re)builds the node list — on initial load and on every subsequent rebuild (memory approve/save/delete, filter/search change, tab switch, manual refresh) — nodes spawn at the exact center/origin instead of their current randomized-radius starting position, with opacity `0`. The **existing** repulsion/spring physics then organically spreads them out to their settled layout over the following ~1-2 seconds — no separate "animation path" or easing curve needs to be hand-built for the *position* side of this, since the physics simulation already in place does that work once the spawn point changes.

The **opacity** side is a straightforward fade-in: each node gets a `spawnTime` (`performance.now()` at creation). Each frame, compute `fadeIn = Math.min(1, (now - spawnTime) / 400)` and multiply it into the existing opacity calculation (2D: `el.style.opacity = op * fadeIn`; 3D: `ctx.globalAlpha = alpha * fadeIn`) — layered on top of, not replacing, the existing highlight/focus/search-dimming opacity logic.

### 5.2 Replay behavior (explicitly intended, not a bug)
Because `startGraph2D()`/`startGraph3D()` fully rebuild `_g2dNodes`/`_g3dNodes` from scratch on every call, and every rebuild now spawns nodes at center, the entrance animation replays on every rebuild — including routine ones triggered by user actions (approving a memory, deleting one, changing the category filter). This is intentional: it gives visible confirmation that "something changed" in the underlying data, consistent with how the rest of the dashboard already uses motion as feedback (e.g. Knowledge tab's card entrance stagger, avatar pulse).

### 5.3 What does NOT change
- Hub node positions — hubs are not part of this spawn-at-center treatment; they already sit at fixed, evenly-spaced positions around the category ring and don't need an entrance flourish since they don't move once placed today, in 2D or 3D

---

## 6. CSS Impact

None. All four features are driven by the existing per-frame JS render loops (SVG attribute manipulation in 2D, canvas redraw in 3D) — no new CSS classes, animations, or keyframes are needed.

---

## 7. What Does NOT Change

- `buildSemanticEdges`, `recencyRadius`, `inferCat`, `CAT_COLOR` — reused as-is by both 2D and 3D
- 2D: repulsion/spring/hub-pull/center-gravity force formulas, tooltip, focus mode, search-highlight, hub click-to-filter
- 3D: camera orbit, click-to-select/focus, tooltip, search-highlight, `RW`/`RH`/perspective-scale constants
- Knowledge and Thinking/Profile tabs — untouched (separate, already-shipped specs)
- No new server endpoints or data — purely client-side motion/physics

---

## 8. File Impact

Single file: `jarvis-brain.html`

Estimated additions: ~120 lines (2D momentum tracking in existing pointer handlers, new `_stepGraph3DPhysics()` function ~50 lines, pulse field + decay logic in both render loops, spawn-at-center + fade-in in both node-creation and render code)
Estimated removals: ~4 lines (the `n.vx = 0; n.vy = 0;` reset lines removed from the 2D drag handler)
Net: ~+116 lines

---

## 9. Out of Scope

- Node dragging in the 3D view
- Multi-touch / simultaneous multi-node dragging in 2D
- Persisting node positions between sessions or graph rebuilds
- Physics tuning UI (exposing friction/repulsion constants as user-facing settings)
- Changes to the Knowledge or Thinking/Profile tabs
