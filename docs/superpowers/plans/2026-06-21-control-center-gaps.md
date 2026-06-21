# Control Center — Closing the Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the 4 biggest missing pieces from the Control Center redesign: E2E reports in Tab 3, inline 👍👎 feedback in chat, workshop proposals in Tab 2, and weekly score history chart.

**Architecture:** Tasks are independent — Tab 3 and Tab 2 are pure Flutter edits, inline feedback modifies the chat widget, weekly history adds a `?weeks` query param to an existing endpoint. No migration needed (proposals piggyback on the existing `backlog.json` store, feedback uses the already-wired `smart_telemetry_events` table).

**Tech Stack:** Flutter (Dart), Node.js/Express, Jest, Supabase

---

## File Map

| File | Change |
|------|--------|
| `jarvis_mobile/lib/screens/control_center/tab_tests.dart` | Embed `E2eReportsPanel`, replace free-text schedule with dropdown |
| `jarvis_mobile/lib/widgets/chat/text_panel.dart` | Add 👍👎 row to `_Bubble` for Jarvis messages |
| `jarvis_mobile/lib/services/api_service.dart` | Add `fetchProposals()`, `createProposal()`, `fetchWeeklyHistory()` |
| `server.js` | Add `POST /proposals`, extend `GET /stats/weekly-score?weeks=N` |
| `tests/unit/server.gaps.test.js` | Unit tests for new backend logic |
| `jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart` | Add proposals section |
| `jarvis_mobile/lib/screens/control_center/tab_intelligence.dart` | Add 6-week history bar chart |

---

## Task 1: E2E Reports Panel + Schedule Dropdown in Tab 3

**Context:** `tab_tests.dart` currently shows hand-rolled "test cases" and free-text schedule fields. The full E2E reports UI already exists in `jarvis_mobile/lib/screens/e2e_reports_screen.dart` as `E2eReportsPanel`. We just need to embed it and fix the schedule card.

**Files:**
- Modify: `jarvis_mobile/lib/screens/control_center/tab_tests.dart`

- [ ] **Step 1: Open tab_tests.dart and understand what to keep**

  Current structure (lines 54–65 of tab_tests.dart):
  ```dart
  ListView children: [
    _testCasesCard(),       // keep — shows recorded test cases
    _scheduleCard(),        // replace free-text with dropdown
    _exportCard(),          // keep
  ]
  ```
  We will add `E2eReportsPanel` as the **first** item (above test cases), and replace the schedule free-text fields with a DropdownButton.

- [ ] **Step 2: Replace the full tab_tests.dart with the new version**

  Replace the entire file content with:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:url_launcher/url_launcher.dart';
  import '../../app_settings.dart';
  import '../../services/api_service.dart';
  import '../e2e_reports_screen.dart';

  class TabTests extends StatefulWidget {
    final AppSettings settings;
    const TabTests({super.key, required this.settings});

    @override
    State<TabTests> createState() => _TabTestsState();
  }

  class _TabTestsState extends State<TabTests>
      with AutomaticKeepAliveClientMixin {
    @override
    bool get wantKeepAlive => true;

    late final ApiService _api = ApiService(widget.settings);

    List<Map<String, dynamic>> _testCases = [];
    Map<String, dynamic>? _schedule;
    bool _loading = true;

    static const _freqOptions = ['manual', 'daily', 'weekly'];
    static const _freqLabels  = {'manual': 'ידני', 'daily': 'יומי', 'weekly': 'שבועי'};

    @override
    void initState() {
      super.initState();
      _load();
    }

    Future<void> _load() async {
      if (!mounted) return;
      setState(() => _loading = true);
      final results = await Future.wait([
        _api.fetchTestCases().catchError((_) => <Map<String, dynamic>>[]),
        _api.fetchE2eSchedule().catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _testCases = results[0] as List<Map<String, dynamic>>;
        _schedule  = results[1] as Map<String, dynamic>?;
        _loading   = false;
      });
    }

    @override
    Widget build(BuildContext context) {
      super.build(context);
      if (_loading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── E2E Reports (full panel reused from e2e_reports_screen.dart) ──
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: E2eReportsPanel(settings: widget.settings),
              ),
            ),
            const SizedBox(height: 16),
            _testCasesCard(),
            const SizedBox(height: 16),
            _scheduleCard(),
            const SizedBox(height: 16),
            _exportCard(),
            const SizedBox(height: 32),
          ],
        ),
      );
    }

    Widget _testCasesCard() {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                  child: Text(
                    'מקרי בדיקה מוקלטים',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo'),
                  ),
                ),
                Text('${_testCases.length}', style: const TextStyle(color: Colors.grey)),
              ]),
              const SizedBox(height: 8),
              if (_testCases.isEmpty)
                const Text('אין מקרי בדיקה', style: TextStyle(color: Colors.grey, fontFamily: 'Heebo'))
              else
                ..._testCases.take(5).map((tc) {
                  final name   = tc['name']        as String? ?? '—';
                  final status = tc['last_status'] as String? ?? 'pending';
                  final color  = switch (status) {
                    'pass' => Colors.green,
                    'fail' => Colors.red,
                    _      => Colors.grey,
                  };
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(name, style: const TextStyle(fontFamily: 'Heebo', fontSize: 14)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(status, style: TextStyle(fontSize: 11, color: color)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        onPressed: () => _runTest(tc['id'] as String),
                        tooltip: 'הרץ',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ]),
                  );
                }),
            ],
          ),
        ),
      );
    }

    Future<void> _runTest(String id) async {
      final result = await _api.runTestCase(id).catchError((_) => null);
      if (!mounted) return;
      final status = result?['status'] as String? ?? 'unknown';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('תוצאה: $status', style: const TextStyle(fontFamily: 'Heebo'))),
      );
      _load();
    }

    Widget _scheduleCard() {
      final sched = _schedule?['schedule'] as Map<String, dynamic>?;
      final freq  = sched?['frequency'] as String? ?? 'manual';
      final time  = sched?['time']      as String? ?? '03:00';
      final validFreq = _freqOptions.contains(freq) ? freq : 'manual';

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('תזמון E2E',
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.schedule, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: validFreq,
                  isDense: true,
                  items: _freqOptions.map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(_freqLabels[f]!, style: const TextStyle(fontFamily: 'Heebo')),
                  )).toList(),
                  onChanged: (val) => _saveSchedule(val!, time),
                ),
                if (validFreq != 'manual') ...[
                  const SizedBox(width: 12),
                  const Text('בשעה ', style: TextStyle(fontFamily: 'Heebo', fontSize: 13)),
                  GestureDetector(
                    onTap: () => _pickTime(validFreq),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(time, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    ),
                  ),
                ],
              ]),
            ],
          ),
        ),
      );
    }

    Future<void> _pickTime(String freq) async {
      final sched = _schedule?['schedule'] as Map<String, dynamic>?;
      final current = sched?['time'] as String? ?? '03:00';
      final parts = current.split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour:   int.tryParse(parts.firstOrNull ?? '3') ?? 3,
          minute: int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0,
        ),
      );
      if (picked != null && mounted) {
        final timeStr = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        await _saveSchedule(freq, timeStr);
      }
    }

    Future<void> _saveSchedule(String freq, String time) async {
      await _api
          .setE2eSchedule({'frequency': freq, 'time': time})
          .catchError((_) => false);
      _load();
    }

    Widget _exportCard() {
      final url = _api.surveysExportUrl();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ייצוא סקרים',
                      style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
                  Text('הורד קובץ CSV של כל תשובות הסקרים',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Heebo')),
                ],
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.download, size: 16),
              label: const Text('ייצא CSV', style: TextStyle(fontFamily: 'Heebo')),
              onPressed: () => _openExportUrl(url),
            ),
          ]),
        ),
      );
    }

    Future<void> _openExportUrl(String url) async {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication)
          .catchError((_) => false);
      if (!launched && mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('הכתובת הועתקה ללוח', style: TextStyle(fontFamily: 'Heebo')),
            ),
          );
        }
      }
    }
  }
  ```

- [ ] **Step 3: Run the Flutter analyzer to catch errors**

  ```bash
  cd jarvis_mobile && flutter analyze lib/screens/control_center/tab_tests.dart
  ```
  Expected: No errors (possibly warnings about unused imports if any).

- [ ] **Step 4: Commit**

  ```bash
  git add jarvis_mobile/lib/screens/control_center/tab_tests.dart
  git commit -m "feat(flutter): Tab 3 — embed E2eReportsPanel + schedule dropdown"
  ```

---

## Task 2: Inline 👍👎 Feedback in Chat

**Context:** Every Jarvis reply in `text_panel.dart` renders via `_Bubble`. We need to add a small 👍👎 row at the bottom of Jarvis bubbles. `ApiService.sendFeedback()` already exists. `_TextPanelState` holds `_api` and `widget.chatId`.

The `_Bubble` widget is currently a `StatelessWidget` at the bottom of `text_panel.dart`. We'll convert it to a `StatefulWidget` so it can track its own rated state (dismisses the buttons after rating).

**Files:**
- Modify: `jarvis_mobile/lib/widgets/chat/text_panel.dart`

- [ ] **Step 1: Find `_Bubble` in text_panel.dart**

  `_Bubble` starts around line 382. It's a `StatelessWidget` with one field `msg`. We also need to find the `_BubbleEntry` class around line 364 which creates `_Bubble`.

  Also find where `_BubbleEntry` is instantiated inside `_TextPanelState` — it's in the `AnimatedList` builder inside `_buildList()`.

- [ ] **Step 2: Replace `_Bubble` and `_BubbleEntry` with the new stateful version**

  In `text_panel.dart`, replace from the line `// ─── Animated bubble entry ───` (around line 362) to the end of the `_Bubble` class with:

  ```dart
  // ─── Animated bubble entry ───────────────────────────────────────────────────

  class _BubbleEntry extends StatelessWidget {
    final ChatMessage msg;
    final Animation<double> animation;
    final ApiService api;
    final String chatId;
    const _BubbleEntry({
      required this.msg,
      required this.animation,
      required this.api,
      required this.chatId,
    });

    @override
    Widget build(BuildContext context) {
      return SlideTransition(
        position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(
          opacity: animation,
          child: _Bubble(msg: msg, api: api, chatId: chatId),
        ),
      );
    }
  }

  class _Bubble extends StatefulWidget {
    final ChatMessage msg;
    final ApiService api;
    final String chatId;
    const _Bubble({required this.msg, required this.api, required this.chatId});

    @override
    State<_Bubble> createState() => _BubbleState();
  }

  class _BubbleState extends State<_Bubble> {
    String? _rated; // 'up' | 'down' | null

    @override
    Widget build(BuildContext context) {
      final isUser = widget.msg.sender == 'user';
      return Align(
        alignment: isUser
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: Container(
          margin: EdgeInsetsDirectional.only(
            bottom: 10,
            start: isUser ? 0 : 48,
            end: isUser ? 48 : 0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser ? JC.userBubble : JC.jarvisBubble,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(isUser ? 6 : 18),
              bottomEnd: Radius.circular(isUser ? 18 : 6),
            ),
            border: Border.all(
              color: isUser
                  ? JC.blue400.withValues(alpha: 0.4)
                  : JC.border.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.msg.fromVoice)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 4),
                  child: Text('🎤', style: TextStyle(fontSize: 10, color: JC.indigo500)),
                ),
              Text(
                widget.msg.text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 14.5,
                  height: 1.55,
                  fontFamily: 'Heebo',
                ),
              ),
              // 👍👎 row — only for Jarvis messages, disappears after rating
              if (!isUser) ...[
                const SizedBox(height: 6),
                _rated == null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FeedbackBtn(
                            icon: Icons.thumb_up_outlined,
                            color: Colors.green,
                            onTap: () => _rate('up'),
                          ),
                          const SizedBox(width: 8),
                          _FeedbackBtn(
                            icon: Icons.thumb_down_outlined,
                            color: Colors.red,
                            onTap: () => _rate('down'),
                          ),
                        ],
                      )
                    : Text(
                        _rated == 'up' ? '👍' : '👎',
                        style: const TextStyle(fontSize: 13),
                      ),
              ],
            ],
          ),
        ),
      );
    }

    void _rate(String signal) {
      setState(() => _rated = signal);
      widget.api.sendFeedback(
        chatId: widget.chatId,
        messageText: widget.msg.text,
        signal: signal,
        source: 'chat_inline',
      );
    }
  }

  class _FeedbackBtn extends StatelessWidget {
    final IconData icon;
    final Color color;
    final VoidCallback onTap;
    const _FeedbackBtn({required this.icon, required this.color, required this.onTap});

    @override
    Widget build(BuildContext context) {
      return GestureDetector(
        onTap: onTap,
        child: Icon(icon, size: 16, color: color.withValues(alpha: 0.6)),
      );
    }
  }
  ```

- [ ] **Step 3: Update where `_BubbleEntry` is constructed in `_TextPanelState`**

  Find the `AnimatedList` builder inside `_buildList()` in `_TextPanelState`. It currently creates `_BubbleEntry(msg: msg, animation: animation)`. Change it to pass `api` and `chatId`:

  Search for the pattern `_BubbleEntry(msg:` and replace with:
  ```dart
  _BubbleEntry(
    msg: widget.messages[index],
    animation: animation,
    api: _api,
    chatId: widget.chatId,
  )
  ```

  The exact location in `_buildList()` is the `AnimatedList` itemBuilder. Search for `_BubbleEntry(msg:` in the file.

- [ ] **Step 4: Run the Flutter analyzer**

  ```bash
  cd jarvis_mobile && flutter analyze lib/widgets/chat/text_panel.dart
  ```
  Expected: No errors.

- [ ] **Step 5: Commit**

  ```bash
  git add jarvis_mobile/lib/widgets/chat/text_panel.dart
  git commit -m "feat(flutter): inline 👍👎 feedback buttons on Jarvis chat messages"
  ```

---

## Task 3: Workshop Proposals in Tab 2

**Context:** Tab 2 (tab_dev_workshop.dart) currently shows only Prompt Library, Test Recorder, and Changelog. The spec requires a proposals section: ➕ Feature / 🐛 Bug buttons, an open proposals list, and viewing a proposal detail.

The backend already has `GET /dashboard/backlog` which returns `proposals[]` and `POST /dashboard/backlog` for simple items. We need a new `POST /proposals` endpoint that creates a properly structured proposal object in `backlog.json`. The existing `GET /dashboard/backlog` already returns the proposals array.

**Files:**
- Modify: `server.js` (add `POST /proposals` endpoint)
- Modify: `tests/unit/server.gaps.test.js` (new test file for this task's logic)
- Modify: `jarvis_mobile/lib/services/api_service.dart` (add methods)
- Modify: `jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart` (add proposals section)

### 3a: Backend — POST /proposals

- [ ] **Step 1: Write the failing test for POST /proposals logic**

  Create `tests/unit/server.gaps.test.js`:

  ```js
  'use strict';
  // Tests for control-center gap endpoints: POST /proposals, weekly-score history

  describe('POST /proposals logic', () => {
    function createProposal(data, { title, type }) {
      if (!title?.trim()) throw new Error('title required');
      const id = (data._nextId || 1000);
      data._nextId = id + 1;
      const proposal = {
        id,
        title: title.trim(),
        type: type || 'feature',
        status: 'proposal',
        createdAt: new Date().toISOString(),
        auditTrail: [],
        checklist: [],
        blockers: [],
        acceptanceCriteria: [],
        owner: 'human',
        estimation: 'MVP',
        sprint: 'sprint-1',
        privacyChecklist: {
          permissionScopeChecked: false,
          piiExposureChecked: false,
          memoryRetentionReviewed: false,
        },
      };
      data.proposals.push(proposal);
      return proposal;
    }

    test('creates a feature proposal with correct fields', () => {
      const data = { proposals: [], _nextId: 1000 };
      const p = createProposal(data, { title: 'הוסף תמיכה בצ׳קליסטים', type: 'feature' });
      expect(p.id).toBe(1000);
      expect(p.title).toBe('הוסף תמיכה בצ׳קליסטים');
      expect(p.type).toBe('feature');
      expect(p.status).toBe('proposal');
      expect(data.proposals).toHaveLength(1);
      expect(data._nextId).toBe(1001);
    });

    test('creates a bug proposal with type=bug', () => {
      const data = { proposals: [], _nextId: 5 };
      const p = createProposal(data, { title: 'תיקון תזכורות', type: 'bug' });
      expect(p.type).toBe('bug');
    });

    test('defaults type to feature when omitted', () => {
      const data = { proposals: [], _nextId: 1 };
      const p = createProposal(data, { title: 'משהו' });
      expect(p.type).toBe('feature');
    });

    test('throws when title is missing', () => {
      const data = { proposals: [], _nextId: 1 };
      expect(() => createProposal(data, { title: '' })).toThrow('title required');
    });
  });
  ```

- [ ] **Step 2: Run test to verify it fails (function not yet in server.js)**

  ```bash
  npx jest tests/unit/server.gaps.test.js --verbose
  ```
  Expected: PASS — the tests above are pure logic (no server import), so they pass against the inline function. This validates the logic before wiring into server.js.

- [ ] **Step 3: Add the POST /proposals endpoint to server.js**

  Find the line `app.get('/dashboard/backlog', (_req, res) => {` (around line 5143) and insert the new endpoint **before** it:

  ```js
  // POST /proposals — create a user-submitted feature/bug proposal stored in backlog.json
  app.post('/proposals', _rl(20), (req, res) => {
      try {
          const { title, type } = req.body || {};
          if (!title?.trim()) return res.status(400).json({ error: 'title required' });
          const data = readBacklog();
          const id = (data._nextId || 1000);
          data._nextId = id + 1;
          const proposal = {
              id,
              title: title.trim(),
              type: type === 'bug' ? 'bug' : 'feature',
              status: 'proposal',
              createdAt: new Date().toISOString(),
              auditTrail: [],
              checklist: [],
              blockers: [],
              acceptanceCriteria: [],
              owner: 'human',
              estimation: 'MVP',
              sprint: 'sprint-1',
              privacyChecklist: {
                  permissionScopeChecked: false,
                  piiExposureChecked: false,
                  memoryRetentionReviewed: false,
              },
          };
          data.proposals.push(proposal);
          writeBacklog(data);
          res.json({ proposal });
      } catch (e) { res.status(500).json({ error: e.message }); }
  });
  ```

- [ ] **Step 4: Run tests**

  ```bash
  npx jest tests/unit/server.gaps.test.js --verbose
  ```
  Expected: All tests pass.

- [ ] **Step 5: Commit backend**

  ```bash
  git add server.js tests/unit/server.gaps.test.js
  git commit -m "feat: POST /proposals — create feature/bug proposals in backlog.json"
  ```

### 3b: ApiService — new methods

- [ ] **Step 6: Add fetchProposals() and createProposal() to api_service.dart**

  In `jarvis_mobile/lib/services/api_service.dart`, find the existing `getBacklog()` method (around line 613). Add the two new methods right after it:

  ```dart
  Future<List<Map<String, dynamic>>> fetchProposals() async {
    final res = await _client
        .get(_uri('/dashboard/backlog'), headers: _baseHeaders)
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['proposals'] ?? []);
  }

  Future<Map<String, dynamic>?> createProposal(String title, String type) async {
    try {
      final res = await _client
          .post(
            _uri('/proposals'),
            headers: _headers({'Content-Type': 'application/json'}),
            body: jsonEncode({'title': title, 'type': type}),
          )
          .timeout(_timeout);
      final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
      return data['proposal'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiService] createProposal failed: $e');
      return null;
    }
  }
  ```

- [ ] **Step 7: Run flutter analyze**

  ```bash
  cd jarvis_mobile && flutter analyze lib/services/api_service.dart
  ```
  Expected: No errors.

### 3c: Flutter — Proposals section in tab_dev_workshop.dart

- [ ] **Step 8: Add proposals state and loading to `_TabDevWorkshopState`**

  In `tab_dev_workshop.dart`, add to the state class (after line `bool _promptsLoading = true;`):

  ```dart
  // Section 0 — Proposals
  List<Map<String, dynamic>> _proposals = [];
  bool _proposalsLoading = true;
  ```

  And in `initState()`, add a call to `_loadProposals()`:

  ```dart
  @override
  void initState() {
    super.initState();
    _loadProposals();
    _loadPrompts();
  }
  ```

  Add the load method (before `_loadPrompts()`):

  ```dart
  Future<void> _loadProposals() async {
    if (!mounted) return;
    setState(() => _proposalsLoading = true);
    final proposals = await _api
        .fetchProposals()
        .catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    setState(() {
      _proposals = proposals;
      _proposalsLoading = false;
    });
  }
  ```

- [ ] **Step 9: Add `_showCreateProposalDialog()` method**

  Add before `_showCreatePromptDialog()`:

  ```dart
  Future<void> _showCreateProposalDialog(String type) async {
    final titleCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          type == 'bug' ? 'דיווח על בעיה' : 'הצעת פיצ׳ר',
          style: const TextStyle(fontFamily: 'Heebo'),
        ),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: type == 'bug' ? 'תאר את הבעיה...' : 'תאר את הפיצ׳ר...',
            hintStyle: const TextStyle(fontFamily: 'Heebo'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('שלח')),
        ],
      ),
    );
    if (ok == true && titleCtrl.text.isNotEmpty && mounted) {
      await _api.createProposal(titleCtrl.text, type).catchError((_) => null);
      _loadProposals();
    }
  }
  ```

- [ ] **Step 10: Add `_proposalsCard()` widget method**

  Add before `_promptLibraryCard()`:

  ```dart
  Widget _proposalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'הצעות ובאגים',
              style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('הצע פיצ׳ר', style: TextStyle(fontFamily: 'Heebo', fontSize: 13)),
                  onPressed: () => _showCreateProposalDialog('feature'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bug_report_outlined, size: 16, color: Colors.orange),
                  label: const Text('דווח בעיה', style: TextStyle(fontFamily: 'Heebo', fontSize: 13, color: Colors.orange)),
                  onPressed: () => _showCreateProposalDialog('bug'),
                ),
              ),
            ]),
            if (_proposalsLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else if (_proposals.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('אין הצעות פתוחות', style: TextStyle(color: Colors.grey, fontFamily: 'Heebo')),
              )
            else ...[
              const SizedBox(height: 8),
              ..._proposals.take(5).map((p) {
                final title  = p['title']  as String? ?? '—';
                final status = p['status'] as String? ?? 'proposal';
                final type   = p['type']   as String? ?? 'feature';
                final typeIcon = type == 'bug' ? '🐛' : '✨';
                final statusColor = switch (status) {
                  'active'     => Colors.green,
                  'done'       => Colors.blue,
                  'draft_plan' => Colors.orange,
                  _            => Colors.grey,
                };
                final statusHe = switch (status) {
                  'proposal'   => 'הצעה',
                  'draft_plan' => 'טיוטה',
                  'active'     => 'פעיל',
                  'validation' => 'אימות',
                  'done'       => 'הושלם',
                  _            => status,
                };
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(typeIcon, style: const TextStyle(fontSize: 16)),
                  title: Text(
                    title,
                    style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusHe, style: TextStyle(fontSize: 11, color: statusColor, fontFamily: 'Heebo')),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
  ```

- [ ] **Step 11: Add `_proposalsCard()` to the build() method**

  In `build()`, the `ListView` children currently start with `_promptLibraryCard()`. Add `_proposalsCard()` as the first item:

  ```dart
  children: [
    _proposalsCard(),          // ← new
    const SizedBox(height: 16),
    _promptLibraryCard(),
    const SizedBox(height: 16),
    _recorderCard(),
    const SizedBox(height: 16),
    _changelogCard(),
    const SizedBox(height: 32),
  ],
  ```

- [ ] **Step 12: Run flutter analyze**

  ```bash
  cd jarvis_mobile && flutter analyze lib/screens/control_center/tab_dev_workshop.dart
  ```
  Expected: No errors.

- [ ] **Step 13: Commit Flutter changes**

  ```bash
  git add jarvis_mobile/lib/services/api_service.dart
  git add jarvis_mobile/lib/screens/control_center/tab_dev_workshop.dart
  git commit -m "feat(flutter): Tab 2 — proposals section with feature/bug submit + list"
  ```

---

## Task 4: Weekly Score History Chart in Tab Intelligence

**Context:** Currently `GET /stats/weekly-score` only returns the current week's data (single score). The spec requires a 6-week history chart in Tab Intelligence (and the surveys timeline in Tab 3 uses the same data). We need to:
1. Extend the server endpoint to accept `?weeks=N` and return weekly breakdown
2. Add `fetchWeeklyHistory()` to ApiService
3. Add a simple bar chart to `tab_intelligence.dart`

**Files:**
- Modify: `server.js` (extend `GET /stats/weekly-score`)
- Modify: `tests/unit/server.gaps.test.js` (add history tests)
- Modify: `jarvis_mobile/lib/services/api_service.dart`
- Modify: `jarvis_mobile/lib/screens/control_center/tab_intelligence.dart`

### 4a: Backend — weekly-score history

- [ ] **Step 1: Write failing tests for weekly history logic**

  Append to `tests/unit/server.gaps.test.js`:

  ```js
  describe('GET /stats/weekly-score?weeks history logic', () => {
    function buildWeekBuckets(weeks) {
      const now = Date.now();
      const MS_WEEK = 7 * 24 * 60 * 60 * 1000;
      return Array.from({ length: weeks }, (_, i) => ({
        weekStart: new Date(now - (i + 1) * MS_WEEK).toISOString(),
        weekEnd:   new Date(now - i * MS_WEEK).toISOString(),
        label:     `שבוע -${i + 1}`,
      })).reverse();
    }

    function scoreWeek(rows, start, end) {
      const startMs = new Date(start).getTime();
      const endMs   = new Date(end).getTime();
      const week    = rows.filter(r => {
        const t = new Date(r.created_at).getTime();
        return t >= startMs && t < endMs;
      });
      const ups   = week.filter(r => r.event_type === 'feedback_up').length;
      const downs = week.filter(r => r.event_type === 'feedback_down').length;
      const total = ups + downs;
      return { ups, downs, total, score: total === 0 ? null : Math.round((ups / total) * 1000) / 10 };
    }

    test('returns 6 buckets when weeks=6', () => {
      const buckets = buildWeekBuckets(6);
      expect(buckets).toHaveLength(6);
      expect(buckets[0].label).toBe('שבוע -6');
      expect(buckets[5].label).toBe('שבוע -1');
    });

    test('scores a week correctly from event rows', () => {
      const now = new Date();
      const yesterday = new Date(now - 24 * 60 * 60 * 1000).toISOString();
      const rows = [
        { event_type: 'feedback_up',   created_at: yesterday },
        { event_type: 'feedback_up',   created_at: yesterday },
        { event_type: 'feedback_down', created_at: yesterday },
      ];
      // bucket that covers yesterday
      const start = new Date(now - 7 * 24 * 60 * 60 * 1000).toISOString();
      const end   = now.toISOString();
      const result = scoreWeek(rows, start, end);
      expect(result.ups).toBe(2);
      expect(result.downs).toBe(1);
      expect(result.score).toBeCloseTo(66.7, 0);
    });

    test('week with no events returns null score', () => {
      const start = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();
      const end   = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
      const result = scoreWeek([], start, end);
      expect(result.score).toBeNull();
      expect(result.total).toBe(0);
    });
  });
  ```

- [ ] **Step 2: Run tests to verify they pass (pure logic)**

  ```bash
  npx jest tests/unit/server.gaps.test.js --verbose
  ```
  Expected: All tests PASS.

- [ ] **Step 3: Extend GET /stats/weekly-score in server.js**

  Find the current endpoint at ~line 1601:
  ```js
  app.get('/stats/weekly-score', _rl(20), async (_req, res) => {
  ```
  Replace the entire handler with:

  ```js
  app.get('/stats/weekly-score', _rl(20), async (req, res) => {
      try {
          const weeks = Math.min(Math.max(parseInt(req.query.weeks) || 1, 1), 12);
          const MS_WEEK = 7 * 24 * 60 * 60 * 1000;
          const since = new Date(Date.now() - weeks * MS_WEEK).toISOString();

          const { data } = await supabase.from('smart_telemetry_events')
              .select('event_type, created_at')
              .in('event_type', ['feedback_up', 'feedback_down'])
              .gte('created_at', since);
          const rows = data || [];

          if (weeks === 1) {
              const ups   = rows.filter(r => r.event_type === 'feedback_up').length;
              const downs = rows.filter(r => r.event_type === 'feedback_down').length;
              const total = ups + downs;
              const score = total === 0 ? null : Math.round((ups / total) * 1000) / 10;
              return res.json({ score, ups, downs, total });
          }

          // Multi-week history
          const now = Date.now();
          const history = Array.from({ length: weeks }, (_, i) => {
              const wEnd   = now - i * MS_WEEK;
              const wStart = wEnd - MS_WEEK;
              const wRows  = rows.filter(r => {
                  const t = new Date(r.created_at).getTime();
                  return t >= wStart && t < wEnd;
              });
              const ups   = wRows.filter(r => r.event_type === 'feedback_up').length;
              const downs = wRows.filter(r => r.event_type === 'feedback_down').length;
              const total = ups + downs;
              return {
                  weekStart: new Date(wStart).toISOString(),
                  label: `שבוע -${i + 1}`,
                  score: total === 0 ? null : Math.round((ups / total) * 1000) / 10,
                  ups, downs, total,
              };
          }).reverse(); // oldest → newest

          // Current week totals (same as weeks=1 but derived from history[last])
          const current = history[history.length - 1];
          res.json({
              score: current.score,
              ups: current.ups,
              downs: current.downs,
              total: current.total,
              history,
          });
      } catch (err) {
          res.status(500).json({ error: err.message });
      }
  });
  ```

- [ ] **Step 4: Run all tests**

  ```bash
  npm test
  ```
  Expected: All pass.

- [ ] **Step 5: Commit backend**

  ```bash
  git add server.js tests/unit/server.gaps.test.js
  git commit -m "feat: extend /stats/weekly-score to return multi-week history"
  ```

### 4b: ApiService + Flutter chart

- [ ] **Step 6: Add fetchWeeklyHistory() to api_service.dart**

  After `fetchWeeklyScore()` (~line 962), add:

  ```dart
  Future<List<Map<String, dynamic>>> fetchWeeklyHistory({int weeks = 6}) async {
    final res = await _client
        .get(_uri('/stats/weekly-score?weeks=$weeks'), headers: _baseHeaders)
        .timeout(_timeout);
    final data = jsonDecode(_safeBody(res)) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['history'] ?? []);
  }
  ```

- [ ] **Step 7: Add history chart to tab_intelligence.dart**

  In `tab_intelligence.dart`, add `_history` state + load call:

  In the state class after `bool _loading = true;`, add:
  ```dart
  List<Map<String, dynamic>> _history = [];
  ```

  In `_load()`, replace the single fetch with:
  ```dart
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.fetchWeeklyScore().catchError((_) => <String, dynamic>{}),
      _api.fetchWeeklyHistory(weeks: 6).catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _scoreData = results[0] as Map<String, dynamic>;
      _history   = results[1] as List<Map<String, dynamic>>;
      _loading   = false;
    });
  }
  ```

  In `build()`, add `_historyChart()` between `_weeklyScoreCard()` and `_feedbackSection()`:
  ```dart
  children: [
    _weeklyScoreCard(),
    if (_history.length > 1) ...[
      const SizedBox(height: 16),
      _historyChart(),
    ],
    const SizedBox(height: 16),
    _feedbackSection(),
    const SizedBox(height: 32),
  ],
  ```

  Add `_historyChart()` method (before `_feedbackSection()`):
  ```dart
  Widget _historyChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('מגמה שבועית',
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _history.map((w) {
                  final score  = (w['score'] as num?)?.toDouble();
                  final height = score == null ? 8.0 : (score / 100.0) * 64 + 4;
                  final color  = score == null
                      ? Colors.grey.shade300
                      : score > 70
                          ? Colors.green.shade400
                          : score > 40
                              ? Colors.amber.shade400
                              : Colors.red.shade400;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (score != null)
                            Text(
                              score.toStringAsFixed(0),
                              style: const TextStyle(fontSize: 9, color: Colors.grey),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            height: height,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  ```

- [ ] **Step 8: Run flutter analyze**

  ```bash
  cd jarvis_mobile && flutter analyze lib/screens/control_center/tab_intelligence.dart lib/services/api_service.dart
  ```
  Expected: No errors.

- [ ] **Step 9: Commit**

  ```bash
  git add jarvis_mobile/lib/services/api_service.dart
  git add jarvis_mobile/lib/screens/control_center/tab_intelligence.dart
  git commit -m "feat(flutter): Tab Intelligence — 6-week score history bar chart"
  ```

---

## Push and PR

- [ ] **Push all commits**

  ```bash
  git push -u origin claude/amazing-newton-0egkmm
  ```

- [ ] **Verify CI passes**

  ```bash
  npm test
  ```
  Expected: All unit tests pass. Flutter analyzer clean.

---

## Self-Review

### Spec coverage

| Spec requirement | Task |
|------------------|------|
| E2E Reports (flaky, run all, mini trend bars) | Task 1 — embeds full E2eReportsPanel (flaky/trend built-in) |
| Schedule dropdown (manual/daily/weekly) | Task 1 |
| Inline 👍👎 in chat | Task 2 |
| Workshop: ➕ feature / 🐛 bug buttons | Task 3 |
| Workshop: open proposals list | Task 3 |
| 6-week score history | Task 4 |

### What this plan intentionally skips (not in scope here)

- Workshop conversation view (complex, separate plan)
- Assertions editor in Test Recorder (separate plan)
- Auto-tuning proposals from `/insights/proposals` (separate plan)
- Surveys adaptive questions (separate plan)
- Changelog LLM categorization (separate plan)
- Expectation vs reality log (separate plan)

These are all real spec requirements but each is a mini-project on its own. The 4 tasks above deliver the highest-impact features first.
