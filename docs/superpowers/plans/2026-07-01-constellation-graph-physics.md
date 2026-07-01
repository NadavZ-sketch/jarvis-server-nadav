# Constellation Graph Physics + Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the קונסטלציה tab's memory graph in `jarvis-brain.html` with 2D drag momentum, a real 3D node physics simulation (replacing the static rotating sphere), a click/press pulse effect in both views, and an entrance animation for nodes on every graph (re)build.

**Architecture:** All changes are in a single file (`jarvis-brain.html`). No new server endpoints. The existing 2D force loop (`startGraph2D`'s `frame()`) is extended in place; a brand-new `_stepGraph3DPhysics()` function gives the 3D graph the same kind of force simulation the 2D graph already has, called once per frame from `startGraph3D`'s `frame()` before `_draw3dFrame()`. Pulse and entrance-fade are per-node numeric fields (`pulse`, `spawnTime`) decayed/consumed each frame by the existing render loops — no CSS, matching this file's established "imperative per-frame redraw" style.

**Tech Stack:** Vanilla JS, SVG (2D), Canvas 2D (3D), `requestAnimationFrame`. Single file edit only.

---

## File Map

| File | Change |
|------|--------|
| `jarvis-brain.html:2504-2527` | 2D pointer handlers (`onpointerdown`/`onpointermove`/`onpointerup`/`onclick`) — momentum tracking + pulse trigger |
| `jarvis-brain.html:2445-2456` | 2D `leafNodes` creation — spawn at center + `spawnTime` |
| `jarvis-brain.html:2489-2494` | 2D node SVG markup — add `class="gn-main"` to the visible circle |
| `jarvis-brain.html:2580-2603` | 2D `frame()` per-node loop — release-glide, pulse decay/boost, fade-in |
| `jarvis-brain.html:2648-2663` | 3D node creation — physics fields, spawn near origin |
| `jarvis-brain.html:~2703` (new) | New `_stepGraph3DPhysics()` function |
| `jarvis-brain.html:2696-2701` | 3D `frame()` — call `_stepGraph3DPhysics()` |
| `jarvis-brain.html:2713-2720` | `_g3dHandleClick` — pulse trigger (via real node reference, not the projected copy) |
| `jarvis-brain.html:2759-2788` | `_draw3dFrame` node-drawing loop — fade-in, pulse decay/boost |

---

## Task 1: 2D — Drag momentum

**Files:**
- Modify: `jarvis-brain.html` inside `startGraph2D()` — `svg.onpointerdown`, `svg.onpointermove`, `svg.onpointerup`, and the `frame()` integration step

- [ ] **Step 1: Track velocity during the drag instead of forcing it to zero**

Find this exact block:
```js
  svg.onpointerdown = e => {
    const g = e.target.closest('[data-nidx]');
    if (!g) return;
    const idx = parseInt(g.dataset.nidx);
    const n = _g2dNodes[idx];
    if (!n || n.hub) return;
    _g2dDrag = { idx }; svg.setPointerCapture(e.pointerId); e.preventDefault();
  };
  svg.onpointermove = e => {
    if (!_g2dDrag) return;
    const rect = svg.getBoundingClientRect();
    const n = _g2dNodes[_g2dDrag.idx];
    if (n) { n.x = e.clientX - rect.left; n.y = e.clientY - rect.top; n.vx = 0; n.vy = 0; }
  };
  svg.onpointerup = e => { _g2dDrag = null; };
```
Replace with:
```js
  svg.onpointerdown = e => {
    const g = e.target.closest('[data-nidx]');
    if (!g) return;
    const idx = parseInt(g.dataset.nidx);
    const n = _g2dNodes[idx];
    if (!n || n.hub) return;
    _g2dDrag = { idx, lastT: performance.now() }; svg.setPointerCapture(e.pointerId); e.preventDefault();
  };
  svg.onpointermove = e => {
    if (!_g2dDrag) return;
    const rect = svg.getBoundingClientRect();
    const n = _g2dNodes[_g2dDrag.idx];
    if (n) {
      const now = performance.now();
      const dt = Math.max(1, now - _g2dDrag.lastT);
      const nx = e.clientX - rect.left, ny = e.clientY - rect.top;
      n.vx = (nx - n.x) / dt * 16;
      n.vy = (ny - n.y) / dt * 16;
      n.x = nx; n.y = ny;
      _g2dDrag.lastT = now;
    }
  };
  svg.onpointerup = e => {
    if (_g2dDrag) {
      const n = _g2dNodes[_g2dDrag.idx];
      if (n) n.releaseGlide = 20;
    }
    _g2dDrag = null;
  };
```

**Why:** Previously, releasing a drag left the node's velocity at exactly `0` (set every `pointermove` tick), so it stopped dead the instant you let go. Now `vx`/`vy` are derived from the actual pointer speed just before release, and a `releaseGlide` counter (consumed in Step 2) makes the first ~20 frames after release use a looser damping so the glide is noticeable before the simulation's normal centering force takes over.

- [ ] **Step 2: Apply the release-glide damping in the integration step**

Find this exact block:
```js
    _g2dNodes.forEach((n, gi) => {
      if (_g2dDrag && _g2dDrag.idx === gi) return;
      n.vx = ((n.vx||0) + (W/2 - n.x)*.003) * .85;
      n.vy = ((n.vy||0) + (H/2 - n.y)*.003) * .85;
```
Replace with:
```js
    _g2dNodes.forEach((n, gi) => {
      if (_g2dDrag && _g2dDrag.idx === gi) return;
      if (n.releaseGlide > 0) { n.vx *= 0.95; n.vy *= 0.95; n.releaseGlide--; }
      n.vx = ((n.vx||0) + (W/2 - n.x)*.003) * .85;
      n.vy = ((n.vy||0) + (H/2 - n.y)*.003) * .85;
```

- [ ] **Step 3: Run lint**
```bash
npm run lint
```
Expected: `lint: syntax ok for NNN files` (zero errors — the exact file count printed varies run to run in this repo)

- [ ] **Step 4: Commit**
```bash
git config user.email noreply@anthropic.com && git config user.name Claude
git add jarvis-brain.html
git commit -m "feat(brain): constellation 2D graph — drag release momentum"
```

---

## Task 2: 2D — Click/press pulse effect

**Files:**
- Modify: `jarvis-brain.html` inside `startGraph2D()` — `svg.onpointerdown`, `svg.onclick`, node SVG markup, and the `frame()` per-node loop

- [ ] **Step 1: Trigger a pulse on drag-start**

Find this exact block (this is the Task 1 result — note `lastT` is already there from Task 1):
```js
  svg.onpointerdown = e => {
    const g = e.target.closest('[data-nidx]');
    if (!g) return;
    const idx = parseInt(g.dataset.nidx);
    const n = _g2dNodes[idx];
    if (!n || n.hub) return;
    _g2dDrag = { idx, lastT: performance.now() }; svg.setPointerCapture(e.pointerId); e.preventDefault();
  };
```
Replace with:
```js
  svg.onpointerdown = e => {
    const g = e.target.closest('[data-nidx]');
    if (!g) return;
    const idx = parseInt(g.dataset.nidx);
    const n = _g2dNodes[idx];
    if (!n || n.hub) return;
    n.pulse = 1;
    _g2dDrag = { idx, lastT: performance.now() }; svg.setPointerCapture(e.pointerId); e.preventDefault();
  };
```

- [ ] **Step 2: Trigger a pulse on click**

Find this exact block:
```js
  svg.onclick = e => {
    const g = e.target.closest('[data-nidx]');
    if (!g) { closeGraphTooltip(); S.highlight = null; _g2dFocus = null; document.getElementById('focusPill').style.display='none'; return; }
    const idx = parseInt(g.dataset.nidx);
    const n = _g2dNodes[idx];
    if (!n) return;
    if (n.hub) { S.highlight = S.highlight === n.cat ? null : n.cat; closeGraphTooltip(); }
    else showGraphTooltip(n.id, e.clientX, e.clientY);
  };
```
Replace with:
```js
  svg.onclick = e => {
    const g = e.target.closest('[data-nidx]');
    if (!g) { closeGraphTooltip(); S.highlight = null; _g2dFocus = null; document.getElementById('focusPill').style.display='none'; return; }
    const idx = parseInt(g.dataset.nidx);
    const n = _g2dNodes[idx];
    if (!n) return;
    n.pulse = 1;
    if (n.hub) { S.highlight = S.highlight === n.cat ? null : n.cat; closeGraphTooltip(); }
    else showGraphTooltip(n.id, e.clientX, e.clientY);
  };
```

- [ ] **Step 3: Mark the main visible circle so the pulse can find it**

Find this exact block:
```js
    if (isOrphan) {
      h += `<circle r="${n.r}" fill="${n.c}" opacity=".35"/>`;
      h += `<circle r="${n.r+4}" fill="none" stroke="${n.c}" stroke-width=".6" opacity=".18" stroke-dasharray="2 2"/>`;
    } else {
      h += `<circle r="${n.r}" fill="${n.c}" opacity="${n.hub?.95:.82}"/>`;
    }
```
Replace with:
```js
    if (isOrphan) {
      h += `<circle class="gn-main" r="${n.r}" fill="${n.c}" opacity=".35"/>`;
      h += `<circle r="${n.r+4}" fill="none" stroke="${n.c}" stroke-width=".6" opacity=".18" stroke-dasharray="2 2"/>`;
    } else {
      h += `<circle class="gn-main" r="${n.r}" fill="${n.c}" opacity="${n.hub?.95:.82}"/>`;
    }
```

- [ ] **Step 4: Decay the pulse and boost the circle's radius each frame**

Find this exact block:
```js
      const el = document.getElementById('gn' + gi);
      if (!el) return;
      el.setAttribute('transform', `translate(${n.x.toFixed(1)},${n.y.toFixed(1)})`);
      // Opacity
      let op = 1;
```
Replace with:
```js
      const el = document.getElementById('gn' + gi);
      if (!el) return;
      el.setAttribute('transform', `translate(${n.x.toFixed(1)},${n.y.toFixed(1)})`);
      if (n.pulse > 0.01) {
        n.pulse *= 0.9;
        const mainCircle = el.querySelector('.gn-main');
        if (mainCircle) mainCircle.setAttribute('r', (n.r + n.pulse * 6).toFixed(1));
      } else if (n.pulse) {
        n.pulse = 0;
        const mainCircle = el.querySelector('.gn-main');
        if (mainCircle) mainCircle.setAttribute('r', n.r.toFixed(1));
      }
      // Opacity
      let op = 1;
```

**Why the `else if (n.pulse)` branch:** once decay brings `pulse` below the `0.01` threshold, this runs exactly once to snap the radius back to the exact base `n.r` (avoiding a permanently-slightly-off radius from floating-point decay, and avoiding a per-frame DOM write once the pulse is fully spent).

- [ ] **Step 5: Run lint**
```bash
npm run lint
```
Expected: syntax ok, zero errors

- [ ] **Step 6: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): constellation 2D graph — click/press pulse effect"
```

---

## Task 3: 2D — Entrance animation

**Files:**
- Modify: `jarvis-brain.html` inside `startGraph2D()` — `leafNodes` creation and the `frame()` opacity block

- [ ] **Step 1: Spawn leaf nodes at the center instead of a randomized ring**

Find this exact block:
```js
  const leafNodes = mems.map((m, i) => {
    const a = 2*Math.PI*i/mems.length + Math.random()*0.4;
    const rd = Math.min(W,H)*0.3 + (Math.random()-0.5)*60;
    return {
      id: m.id, cat: inferCat(m.content), label: m.content.slice(0,12),
      c: CAT_COLOR[inferCat(m.content)] || '#C8913A',
      r: recencyRadius(m.created_at), baseR: recencyRadius(m.created_at),
      hub: false, strength: 0,
      x: W/2 + rd*Math.cos(a), y: H/2 + rd*Math.sin(a),
      vx: 0, vy: 0,
    };
  });
```
Replace with:
```js
  const leafNodes = mems.map((m, i) => {
    return {
      id: m.id, cat: inferCat(m.content), label: m.content.slice(0,12),
      c: CAT_COLOR[inferCat(m.content)] || '#C8913A',
      r: recencyRadius(m.created_at), baseR: recencyRadius(m.created_at),
      hub: false, strength: 0,
      x: W/2 + (Math.random()-0.5)*2, y: H/2 + (Math.random()-0.5)*2,
      vx: 0, vy: 0, spawnTime: performance.now(),
    };
  });
```

**Why the `±1px` jitter instead of an exact `(W/2, H/2)` for every node:** the repulsion force computes `dx = (b.x-a.x)||.01` — if every node starts at the *exact* same point, every pair has `dx=0, dy=0`, and the `||.01` fallback pushes every overlapping pair in the same fixed direction, producing a degenerate straight-line spread instead of an organic one. A sub-pixel random offset breaks that symmetry while still reading visually as "starting from the center." Hub nodes are unaffected — they keep their existing fixed ring positions and do not get a `spawnTime` (matching spec: hubs don't need an entrance flourish).

- [ ] **Step 2: Fade in based on time since spawn**

Find this exact block (the tail of the `frame()` opacity block):
```js
      } else {
        if (hl && n.cat !== hl) op = .12;
      }
      el.style.opacity = op;
    });
```
Replace with:
```js
      } else {
        if (hl && n.cat !== hl) op = .12;
      }
      const fadeIn = n.spawnTime ? Math.min(1, (performance.now() - n.spawnTime) / 400) : 1;
      el.style.opacity = op * fadeIn;
    });
```

**Why `n.spawnTime ? ... : 1`:** hub nodes have no `spawnTime` field, so `fadeIn` is always `1` for them (no fade), matching the "hubs don't get an entrance flourish" rule from Step 1.

- [ ] **Step 3: Run lint**
```bash
npm run lint
```
Expected: syntax ok, zero errors

- [ ] **Step 4: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): constellation 2D graph — entrance animation (converge from center + fade)"
```

---

## Task 4: 3D — Node creation: physics fields + spawn near origin

**Files:**
- Modify: `jarvis-brain.html` inside `startGraph3D()` — `_g3dNodes` creation

- [ ] **Step 1: Replace the fixed Fibonacci-sphere seed with physics-ready fields spawned near the origin**

Find this exact block:
```js
  const count = mems.length;
  _g3dNodes = mems.map((m, i) => {
    const phi = Math.acos(1 - 2*(i+.5)/count), theta = Math.PI*(1+Math.sqrt(5))*i;
    return {
      mem: m, idx: i, cat: inferCat(m.content), c: CAT_COLOR[inferCat(m.content)]||'#C8913A',
      r: recencyRadius(m.created_at) * 0.65 + str[i] * 0.4,
      strength: str[i], hub: false,
      ox: Math.sin(phi)*Math.cos(theta), oy: Math.sin(phi)*Math.sin(theta), oz: Math.cos(phi),
    };
  });
  // Hub nodes
  const cats = [...new Set(mems.map(m => inferCat(m.content)))];
  cats.forEach((cat, i) => {
    const a = 2*Math.PI*i/cats.length;
    _g3dNodes.push({ hub: true, cat, label: cat, c: CAT_COLOR[cat]||'#C8913A', r: 7, strength: 0, idx: _g3dNodes.length, ox: Math.cos(a)*.35, oy: .8, oz: Math.sin(a)*.35, mem: null });
  });
```
Replace with:
```js
  _g3dNodes = mems.map((m, i) => {
    return {
      mem: m, idx: i, cat: inferCat(m.content), c: CAT_COLOR[inferCat(m.content)]||'#C8913A',
      r: recencyRadius(m.created_at) * 0.65 + str[i] * 0.4,
      strength: str[i], hub: false,
      ox: (Math.random()-0.5)*0.05, oy: (Math.random()-0.5)*0.05, oz: (Math.random()-0.5)*0.05,
      vx: 0, vy: 0, vz: 0, pulse: 0, spawnTime: performance.now(),
    };
  });
  // Hub nodes
  const cats = [...new Set(mems.map(m => inferCat(m.content)))];
  cats.forEach((cat, i) => {
    const a = 2*Math.PI*i/cats.length;
    _g3dNodes.push({ hub: true, cat, label: cat, c: CAT_COLOR[cat]||'#C8913A', r: 7, strength: 0, idx: _g3dNodes.length, ox: Math.cos(a)*.35, oy: .8, oz: Math.sin(a)*.35, mem: null, pulse: 0 });
  });
```

**Why:** `ox/oy/oz` were fixed unit-sphere coordinates that never changed after creation (only the camera rotated around them). They now start as near-zero jitter (spawn near the origin — same "converge from center" entrance behavior as 2D) and become live physics coordinates, updated every frame by `_stepGraph3DPhysics()` (Task 5), which includes a radial-containment spring pulling them back out toward radius `1.0` — the same equilibrium the old fixed sphere sat at, so `_draw3dFrame`'s `RW`/`RH`/perspective-scale constants (which assume roughly unit-scale coordinates) stay valid without retuning. Hub nodes keep their existing fixed positions (unaffected by the physics step, added in Task 5) and gain only a `pulse: 0` field for Task 6's click-pulse effect. Leaf nodes drop the now-unused `count`/`phi`/`theta` Fibonacci-lattice variables entirely.

- [ ] **Step 2: Run lint**
```bash
npm run lint
```
Expected: syntax ok, zero errors

- [ ] **Step 3: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): constellation 3D graph — node fields for physics, pulse, and spawn-near-origin entrance"
```

---

## Task 5: 3D — Physics simulation

**Files:**
- Add: `_stepGraph3DPhysics()` function in `jarvis-brain.html`, immediately before `_g3dHandleClick`
- Modify: `startGraph3D()`'s `frame()` to call it

- [ ] **Step 1: Add the 3D physics step function**

Find this exact line:
```js
function _g3dHandleClick(clientX, clientY) {
```
Insert the following function immediately BEFORE it:
```js
function _stepGraph3DPhysics() {
  if (!_g3dNodes) return;
  const leafs = _g3dNodes.filter(n => !n.hub);
  const hubNodes = _g3dNodes.filter(n => n.hub);
  const REPEL_3D = 0.16;

  // Repulsion
  for (let i = 0; i < leafs.length; i++) for (let j = i+1; j < leafs.length; j++) {
    const a = leafs[i], b = leafs[j];
    const dx = (b.ox-a.ox)||.001, dy = (b.oy-a.oy)||.001, dz = (b.oz-a.oz)||.001;
    const d = Math.sqrt(dx*dx+dy*dy+dz*dz) || .001;
    if (d < REPEL_3D * 2) {
      const f = REPEL_3D*REPEL_3D/d*.08;
      a.vx -= f*dx/d; a.vy -= f*dy/d; a.vz -= f*dz/d;
      b.vx += f*dx/d; b.vy += f*dy/d; b.vz += f*dz/d;
    }
  }
  // Semantic spring
  _g3dEdges.forEach(e => {
    const a = leafs[e.a], b = leafs[e.b]; if (!a||!b) return;
    const dx = b.ox-a.ox, dy = b.oy-a.oy, dz = b.oz-a.oz;
    const d = Math.sqrt(dx*dx+dy*dy+dz*dz)||.001;
    const f = (d - (0.5 - e.w*0.05)) * .01;
    a.vx += f*dx/d; a.vy += f*dy/d; a.vz += f*dz/d;
    b.vx -= f*dx/d; b.vy -= f*dy/d; b.vz -= f*dz/d;
  });
  // Hub pull
  leafs.forEach(n => {
    const hub = hubNodes.find(h => h.cat === n.cat); if (!hub) return;
    const dx = hub.ox-n.ox, dy = hub.oy-n.oy, dz = hub.oz-n.oz;
    const d = Math.sqrt(dx*dx+dy*dy+dz*dz)||.001;
    if (d > 0.5) { const f=(d-0.5)*.015; n.vx+=f*dx/d; n.vy+=f*dy/d; n.vz+=f*dz/d; }
  });
  // Radial containment + damping + integrate
  leafs.forEach(n => {
    const dist = Math.sqrt(n.ox*n.ox + n.oy*n.oy + n.oz*n.oz) || .001;
    const f = (1.0 - dist) * .02;
    n.vx += f*n.ox/dist; n.vy += f*n.oy/dist; n.vz += f*n.oz/dist;
    n.vx *= 0.85; n.vy *= 0.85; n.vz *= 0.85;
    n.ox += n.vx; n.oy += n.vy; n.oz += n.vz;
  });
}

```

**Note on structure:** this mirrors the 2D `frame()` loop's shape exactly (repulsion → semantic spring → hub pull → damped integration), scaled down to the unit-sphere coordinate range 3D already uses (`REPEL_3D = 0.16` vs 2D's pixel-scale `REPEL = 40`; spring/hub-pull target distances of `0.5` vs 2D's `70`/`80` pixels). Hub nodes are read (as spring/pull targets) but never written to — they stay exactly where they were placed, matching the "hubs don't move" behavior already true of the existing 2D graph and explicitly called out in the spec.

- [ ] **Step 2: Call it once per frame, before drawing**

Find this exact block:
```js
  function frame() {
    if (!_g3dPaused) _g3dAngleH += .006;
    _draw3dFrame(canvas, W, H);
    _g3dRaf = requestAnimationFrame(frame);
  }
```
Replace with:
```js
  function frame() {
    if (!_g3dPaused) _g3dAngleH += .006;
    _stepGraph3DPhysics();
    _draw3dFrame(canvas, W, H);
    _g3dRaf = requestAnimationFrame(frame);
  }
```

- [ ] **Step 3: Run lint**
```bash
npm run lint
```
Expected: syntax ok, zero errors

- [ ] **Step 4: Manual sanity check**

Since there's no test harness for this HTML file, do a quick logic trace instead: with `_g3dEdges` and `_g3dNodes` both populated (as they are immediately after `startGraph3D()` builds them in Task 4's code), confirm `leafs[e.a]`/`leafs[e.b]` indices in the spring step line up with how `buildSemanticEdges` numbers nodes — it's called as `buildSemanticEdges(mems)` in `startGraph3D()`, so edge indices `e.a`/`e.b` are indices into the `mems` array, which is exactly the order `leafs` is derived in (both come from mapping over `mems` with `hub: false`, and hub nodes are appended after, so `leafs` preserves the original `mems` order). No index mismatch.

- [ ] **Step 5: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): constellation 3D graph — real node physics simulation"
```

---

## Task 6: 3D — Click/press pulse + entrance fade-in

**Files:**
- Modify: `jarvis-brain.html` — `_g3dHandleClick` and `_draw3dFrame`

- [ ] **Step 1: Trigger a pulse on click, via the real node (not the projected copy)**

Find this exact block:
```js
  let best = null, bestD = 28;
  _g3dProjected.forEach(p => {
    const d = Math.sqrt((p.sx-cx)**2 + (p.sy-cy)**2);
    if (d < bestD + p.r*.5) { bestD = d; best = p; }
  });
  if (best) {
    if (best.hub) { _g3dHighlight = _g3dHighlight === best.cat ? null : best.cat; }
    else {
      _g3dPaused = true;
      showGraphTooltip(best.mem.id, clientX, clientY);
      const pill = document.getElementById('focusPill');
      pill.textContent = '▶ המשך סיבוב — לחץ לביטול'; pill.style.display = 'block';
    }
  } else {
```
Replace with:
```js
  let best = null, bestD = 28;
  _g3dProjected.forEach(p => {
    const d = Math.sqrt((p.sx-cx)**2 + (p.sy-cy)**2);
    if (d < bestD + p.r*.5) { bestD = d; best = p; }
  });
  if (best) {
    const clickedNode = _g3dNodes[best.idx];
    if (clickedNode) clickedNode.pulse = 1;
    if (best.hub) { _g3dHighlight = _g3dHighlight === best.cat ? null : best.cat; }
    else {
      _g3dPaused = true;
      showGraphTooltip(best.mem.id, clientX, clientY);
      const pill = document.getElementById('focusPill');
      pill.textContent = '▶ המשך סיבוב — לחץ לביטול'; pill.style.display = 'block';
    }
  } else {
```

**Why not just `best.pulse = 1`:** `best` is an entry from `_g3dProjected`, which `_draw3dFrame` rebuilds from scratch every single frame (`_g3dProjected = _g3dNodes.map(...)`) — it's a fresh plain object each time, not a reference to the real node. Setting a field on it would be silently discarded on the very next frame. `best.idx` does correctly carry the original node's array index, so `_g3dNodes[best.idx]` is the object that actually needs the mutation.

- [ ] **Step 2: Fade in on spawn, decay pulse and boost radius, in the node-drawing loop**

Find this exact block:
```js
  // Draw nodes
  _g3dProjected.forEach(p => {
    const n = _g3dNodes[p.idx]; if (!n) return;
    const alpha = Math.max(.2,.35+(p.z+1)*.3);
    let dimmed = false;
    if (_g3dHighlight && n.cat !== _g3dHighlight) dimmed = true;
    if (focusSet && !n.hub && !focusSet.has(p.idx)) dimmed = true;
    if (sq && !n.hub) { const matches = n.mem && n.mem.content.toLowerCase().includes(sq); if (!matches) dimmed = true; }
    ctx.save();
    ctx.globalAlpha = dimmed ? .08 : alpha;
    if (!dimmed) {
      if (n.strength >= 3 || n.hub) { ctx.shadowBlur = n.hub?12:7; ctx.shadowColor = n.c; }
      if (sq && n.mem && n.mem.content.toLowerCase().includes(sq)) { ctx.shadowBlur = 14; ctx.shadowColor = '#fbbf24'; }
    }
    const r = Math.max(p.r, n.hub ? 5 : 2);
    ctx.beginPath(); ctx.arc(p.sx,p.sy,r,0,Math.PI*2);
    ctx.fillStyle = n.c + (Math.round((dimmed?.1:alpha)*255).toString(16).padStart(2,'0'));
    ctx.fill();
    if (!n.hub && n.strength === 0 && !dimmed) {
      ctx.beginPath(); ctx.arc(p.sx,p.sy,r+3,0,Math.PI*2);
      ctx.strokeStyle = n.c+'40'; ctx.lineWidth=.6;
      ctx.setLineDash([2,2]); ctx.stroke(); ctx.setLineDash([]);
    }
    if (n.hub) {
      ctx.globalAlpha = dimmed?.08:.88; ctx.shadowBlur=0;
      ctx.fillStyle='rgba(224,212,190,.9)';
      ctx.font = `700 ${Math.max(8,8*p.scale)}px Heebo,sans-serif`;
      ctx.textAlign='center'; ctx.fillText(n.label,p.sx,p.sy-r-3);
    }
    ctx.restore();
  });
```
Replace with:
```js
  // Draw nodes
  _g3dProjected.forEach(p => {
    const n = _g3dNodes[p.idx]; if (!n) return;
    const alpha = Math.max(.2,.35+(p.z+1)*.3);
    let dimmed = false;
    if (_g3dHighlight && n.cat !== _g3dHighlight) dimmed = true;
    if (focusSet && !n.hub && !focusSet.has(p.idx)) dimmed = true;
    if (sq && !n.hub) { const matches = n.mem && n.mem.content.toLowerCase().includes(sq); if (!matches) dimmed = true; }
    const fadeIn = n.spawnTime ? Math.min(1, (performance.now() - n.spawnTime) / 400) : 1;
    if (n.pulse > 0.01) n.pulse *= 0.9; else if (n.pulse) n.pulse = 0;
    ctx.save();
    ctx.globalAlpha = (dimmed ? .08 : alpha) * fadeIn;
    if (!dimmed) {
      if (n.strength >= 3 || n.hub) { ctx.shadowBlur = n.hub?12:7; ctx.shadowColor = n.c; }
      if (sq && n.mem && n.mem.content.toLowerCase().includes(sq)) { ctx.shadowBlur = 14; ctx.shadowColor = '#fbbf24'; }
    }
    const r = Math.max(p.r, n.hub ? 5 : 2) + (n.pulse || 0) * 4;
    ctx.beginPath(); ctx.arc(p.sx,p.sy,r,0,Math.PI*2);
    ctx.fillStyle = n.c + (Math.round((dimmed?.1:alpha)*255).toString(16).padStart(2,'0'));
    ctx.fill();
    if (!n.hub && n.strength === 0 && !dimmed) {
      ctx.beginPath(); ctx.arc(p.sx,p.sy,r+3,0,Math.PI*2);
      ctx.strokeStyle = n.c+'40'; ctx.lineWidth=.6;
      ctx.setLineDash([2,2]); ctx.stroke(); ctx.setLineDash([]);
    }
    if (n.hub) {
      ctx.globalAlpha = (dimmed?.08:.88) * fadeIn; ctx.shadowBlur=0;
      ctx.fillStyle='rgba(224,212,190,.9)';
      ctx.font = `700 ${Math.max(8,8*p.scale)}px Heebo,sans-serif`;
      ctx.textAlign='center'; ctx.fillText(n.label,p.sx,p.sy-r-3);
    }
    ctx.restore();
  });
```

**Why `n.pulse` decay lives here, not in `_stepGraph3DPhysics()`:** this drawing loop already runs exactly once per node per frame, and canvas has no DOM to "reset" the way 2D's `<circle>` attribute needed resetting in Task 2 — every frame is a full redraw from scratch, so there's no equivalent need for an explicit reset branch beyond clamping `pulse` to exactly `0` once it's negligible (avoiding it lingering at a tiny non-zero float forever).

- [ ] **Step 3: Run lint**
```bash
npm run lint
```
Expected: syntax ok, zero errors

- [ ] **Step 4: Commit**
```bash
git add jarvis-brain.html
git commit -m "feat(brain): constellation 3D graph — click/press pulse + entrance fade-in"
```

---

## Task 7: Verify, push, PR

- [ ] **Step 1: Final lint**
```bash
npm run lint
```
Expected: syntax ok, zero errors

- [ ] **Step 2: Grep for the old Fibonacci-lattice variables to confirm they're fully removed**
```bash
grep -n "Math.acos(1 - 2\*(i+.5)/count)\|Math.PI\*(1+Math.sqrt(5))\*i" jarvis-brain.html
```
Expected: no output (both `phi`/`theta` computations were removed in Task 4, replaced by near-origin jitter)

- [ ] **Step 3: Grep to confirm `_stepGraph3DPhysics` is defined exactly once and called exactly once**
```bash
grep -n "_stepGraph3DPhysics" jarvis-brain.html
```
Expected: exactly 2 matches — the `function _stepGraph3DPhysics() {` definition (Task 5) and the `_stepGraph3DPhysics();` call site inside `frame()` (Task 5)

- [ ] **Step 4: Verify `stopGraph2D()`/`stopGraph3D()` still fully tear down event handlers**

Confirm both functions (unchanged by this plan) still null out all the handlers they always did:
```js
function stopGraph2D() {
  if (_g2dRaf) { cancelAnimationFrame(_g2dRaf); _g2dRaf = null; }
  const svg = document.getElementById('graphSvg');
  if (svg) { svg.onpointerdown = svg.onpointermove = svg.onpointerup = svg.onclick = svg.ondblclick = null; }
}
```
No changes needed here — Tasks 1-2 modified what the handlers *do*, not the teardown logic, and `stopGraph2D()`/`stopGraph3D()` reference the handler properties generically (`svg.onpointerdown = null`, etc.), so they clean up the new logic exactly the same way they cleaned up the old.

- [ ] **Step 5: Push**
```bash
git push -u origin claude/control-center-tab-hz66rf
```

- [ ] **Step 6: Open PR if none exists**

Check for an open PR on branch `claude/control-center-tab-hz66rf` (the previous two PRs on this branch, #436 and #437, were both merged — this will be a new PR). If none open: create a draft PR via GitHub MCP with title "feat(brain): constellation graph physics — drag momentum, 3D node simulation, pulse effect, entrance animation".
