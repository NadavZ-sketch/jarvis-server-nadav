import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';
import 'workshop_screen.dart';

class TabDevWorkshop extends StatefulWidget {
  final AppSettings settings;
  const TabDevWorkshop({super.key, required this.settings});

  @override
  State<TabDevWorkshop> createState() => _TabDevWorkshopState();
}

class _TabDevWorkshopState extends State<TabDevWorkshop>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  // Section 1 — Prompt Library
  List<Map<String, dynamic>> _prompts = [];
  bool _promptsLoading = true;

  // Section 2 — Router Trainer
  List<Map<String, dynamic>> _trainingEvents = [];
  List<Map<String, dynamic>> _routerKeywords = [];
  bool _routerLoading = false;
  int? _openRowIndex;
  final Set<String> _handledEventIds = {};
  String? _selectedIntent;
  final TextEditingController _kwCtrl = TextEditingController();
  int _routerTabIndex = 0;

  // Section 3 — Changelog
  List<Map<String, dynamic>> _changelog = [];
  bool _changelogLoading = false;

  // Section 4 — Proposals
  List<Map<String, dynamic>> _proposals = [];
  bool _proposalsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPrompts();
    _loadRouterData();
    _loadProposals();
  }

  @override
  void dispose() {
    _kwCtrl.dispose();
    super.dispose();
  }

  // ── Prompt Library ──────────────────────────────────────────────────────────

  Future<void> _loadPrompts() async {
    if (!mounted) return;
    setState(() => _promptsLoading = true);
    final prompts = await _api
        .fetchPrompts()
        .catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    setState(() {
      _prompts = prompts;
      _promptsLoading = false;
    });
  }

  Future<void> _showCreatePromptDialog() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('פרומפט חדש',
            style: TextStyle(fontFamily: 'Heebo')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'שם'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contentCtrl,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'תוכן'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('שמור')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.isNotEmpty && mounted) {
      await _api
          .createPrompt(nameCtrl.text, contentCtrl.text)
          .catchError((_) => null);
      _loadPrompts();
    }
  }

  Future<void> _showEditPromptDialog(Map<String, dynamic> p) async {
    final nameCtrl =
        TextEditingController(text: p['name'] as String? ?? '');
    final contentCtrl =
        TextEditingController(text: p['content'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ערוך פרומפט',
            style: TextStyle(fontFamily: 'Heebo')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'שם'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contentCtrl,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'תוכן'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('שמור')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _api
          .updatePrompt(p['id'] as String,
              {'name': nameCtrl.text, 'content': contentCtrl.text})
          .catchError((_) => null);
      _loadPrompts();
    }
  }

  Future<void> _deletePrompt(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחק פרומפט?',
            style: TextStyle(fontFamily: 'Heebo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('מחק',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _api.deletePrompt(id).catchError((_) => false);
      _loadPrompts();
    }
  }

  // ── Router Trainer ──────────────────────────────────────────────────────────

  Future<void> _loadRouterData() async {
    if (!mounted) return;
    setState(() => _routerLoading = true);
    final results = await Future.wait([
      _api.fetchRouterTrainingEvents().catchError((_) => <Map<String, dynamic>>[]),
      _api.fetchRouterKeywords().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _trainingEvents = results[0] as List<Map<String, dynamic>>;
      _routerKeywords = results[1] as List<Map<String, dynamic>>;
      _routerLoading = false;
    });
  }

  Future<void> _saveRouterKeyword(Map<String, dynamic> event) async {
    final kw = _kwCtrl.text.trim();
    final intent = _selectedIntent;
    if (kw.isEmpty || intent == null) return;
    final ok = await _api
        .addRouterKeyword(keyword: kw, intent: intent)
        .catchError((_) => false);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _handledEventIds.add(event['id']?.toString() ?? '');
        _routerKeywords = [
          ..._routerKeywords,
          {'keyword': kw, 'intent': intent},
        ];
        _openRowIndex = null;
        _selectedIntent = null;
        _kwCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ "$kw" ← $intent — פעיל מיד',
              style: const TextStyle(fontFamily: 'Heebo')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteRouterKeyword(Map<String, dynamic> kw) async {
    final ok = await _api
        .deleteRouterKeyword(
          keyword: kw['keyword'] as String,
          intent: kw['intent'] as String,
        )
        .catchError((_) => false);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _routerKeywords = _routerKeywords
            .where((k) => !(k['keyword'] == kw['keyword'] && k['intent'] == kw['intent']))
            .toList();
      });
    }
  }

  // ── Changelog ───────────────────────────────────────────────────────────────

  Future<void> _loadChangelog() async {
    if (!mounted) return;
    setState(() => _changelogLoading = true);
    final entries = await _api
        .generateChangelog()
        .catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    setState(() {
      _changelog = entries;
      _changelogLoading = false;
    });
  }

  // ── Proposals ───────────────────────────────────────────────────────────────

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

  Future<void> _showCreateProposalDialog(String type) async {
    final titleCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(type == 'bug' ? '🐛 דיווח באג' : '✨ הצעת פיצ\'ר',
              style: const TextStyle(fontFamily: 'Heebo')),
          content: TextField(
            controller: titleCtrl,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'תאר את הבקשה...',
              hintStyle: TextStyle(fontFamily: 'Heebo'),
            ),
            style: const TextStyle(fontFamily: 'Heebo'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול', style: TextStyle(fontFamily: 'Heebo'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('שלח', style: TextStyle(fontFamily: 'Heebo'))),
          ],
        ),
      );
      if (ok == true && titleCtrl.text.isNotEmpty && mounted) {
        await _api.createProposal(titleCtrl.text, type);
        if (mounted) _loadProposals();
      }
    } finally {
      titleCtrl.dispose();
    }
  }

  Future<void> _openWorkshop(Map<String, dynamic> proposal) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WorkshopScreen(
          proposal: proposal,
          settings: widget.settings,
        ),
      ),
    );
    if (mounted) _loadProposals();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _promptLibraryCard(),
        const SizedBox(height: 16),
        _routerTrainerCard(),
        const SizedBox(height: 16),
        _changelogCard(),
        const SizedBox(height: 16),
        _proposalsCard(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _promptLibraryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('ספריית פרומפטים',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Heebo')),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _showCreatePromptDialog,
                tooltip: 'הוסף פרומפט',
              ),
            ]),
            if (_promptsLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()))
            else if (_prompts.isEmpty)
              const Text('אין פרומפטים',
                  style: TextStyle(
                      color: Colors.grey, fontFamily: 'Heebo'))
            else
              ..._prompts.map((p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      p['name'] as String? ?? '—',
                      style: const TextStyle(
                          fontFamily: 'Heebo', fontSize: 14),
                    ),
                    subtitle: Text(
                      'גרסה ${p['version'] ?? 1}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 16),
                          onPressed: () =>
                              _showEditPromptDialog(p),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete,
                              size: 16, color: Colors.red),
                          onPressed: () =>
                              _deletePrompt(p['id'] as String),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  static const _intentChips = [
    ('📅', 'reminder'), ('✅', 'task'),       ('🧠', 'memory'),
    ('🛒', 'shopping'), ('💬', 'messaging'),  ('⚽', 'sports'),
    ('🌤', 'weather'),  ('📰', 'news'),       ('🌍', 'translate'),
    ('🎵', 'music'),    ('📝', 'notes'),      ('📈', 'stocks'),
    ('🔁', 'habit'),    ('🗂', 'project'),    ('📆', 'calendar'),
    ('✍️', 'draft'),
  ];

  Widget _routerTrainerCard() {
    final unhandled = _trainingEvents
        .where((e) => !_handledEventIds.contains(e['id']?.toString() ?? ''))
        .toList();
    final unhandledCount = unhandled.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(children: [
              const Expanded(
                child: Text('🧠 מאמן Router',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
              ),
              if (unhandledCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$unhandledCount פתוחות',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Heebo'),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadRouterData,
                tooltip: 'רענן',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ]),
            const SizedBox(height: 8),
            // Inner tab row
            Row(children: [
              _routerTab('הודעות', 0),
              const SizedBox(width: 8),
              _routerTab('Keywords שלי', 1),
            ]),
            const Divider(height: 16),
            // Content
            if (_routerLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (_routerTabIndex == 0)
              _messagesTabContent(unhandled)
            else
              _keywordsTabContent(),
          ],
        ),
      ),
    );
  }

  Widget _routerTab(String label, int index) {
    final active = _routerTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() {
        _routerTabIndex = index;
        _openRowIndex = null;
        _selectedIntent = null;
        _kwCtrl.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _messagesTabContent(List<Map<String, dynamic>> unhandled) {
    if (unhandled.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('אין הודעות לטיפול',
            style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 13),
            textAlign: TextAlign.center),
      );
    }
    return Column(
      children: List.generate(unhandled.length, (i) {
        final event = unhandled[i];
        final isOpen = _openRowIndex == i;
        final msg = event['message'] as String? ?? '';
        return _messageRow(event: event, index: i, isOpen: isOpen, msg: msg, isLast: i == unhandled.length - 1);
      }),
    );
  }

  Widget _messageRow({
    required Map<String, dynamic> event,
    required int index,
    required bool isOpen,
    required String msg,
    required bool isLast,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() {
              if (_openRowIndex == index) {
                _openRowIndex = null;
                _selectedIntent = null;
                _kwCtrl.clear();
              } else {
                _openRowIndex = index;
                _selectedIntent = null;
                // Pre-fill keyword from first 3 words
                final words = msg.split(' ').take(3).join(' ');
                _kwCtrl.text = words;
              }
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOpen
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    color: isOpen ? null : Colors.grey.shade600,
                  ),
                  maxLines: isOpen ? null : 1,
                  overflow: isOpen ? null : TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
        if (isOpen) _expandedPanel(event),
        if (!isLast)
          const Divider(height: 1),
      ],
    );
  }

  Widget _expandedPanel(Map<String, dynamic> event) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Intent chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _intentChips.map(((emoji, name)) {
              final selected = _selectedIntent == name;
              return GestureDetector(
                onTap: () => setState(() => _selectedIntent = name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                    ),
                    color: selected
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                        : null,
                  ),
                  child: Text(
                    '$emoji $name',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Heebo',
                      color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade600,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Keyword input + save
          Row(children: [
            Expanded(
              child: TextField(
                controller: _kwCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'keyword לזיהוי...',
                  hintStyle: TextStyle(fontFamily: 'Heebo', fontSize: 13),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_selectedIntent != null && _kwCtrl.text.trim().isNotEmpty)
                  ? () => _saveRouterKeyword(event)
                  : null,
              child: const Text('שמור', style: TextStyle(fontFamily: 'Heebo')),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _keywordsTabContent() {
    if (_routerKeywords.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('עדיין לא הוספת keywords',
            style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 13),
            textAlign: TextAlign.center),
      );
    }
    return Column(
      children: _routerKeywords.map((kw) {
        final keyword = kw['keyword'] as String? ?? '';
        final intent = kw['intent'] as String? ?? '';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(intent,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Heebo',
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700)),
          ),
          title: Text(keyword,
              style: const TextStyle(fontFamily: 'Heebo', fontSize: 13)),
          subtitle: const Text('←', style: TextStyle(color: Colors.grey)),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
            onPressed: () => _deleteRouterKeyword(kw),
            tooltip: 'מחק',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        );
      }).toList(),
    );
  }

  Widget _changelogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Changelog',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Heebo')),
              ),
              if (_changelogLoading)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('צור',
                      style: TextStyle(fontFamily: 'Heebo')),
                  onPressed: _loadChangelog,
                ),
            ]),
            if (_changelog.isEmpty)
              const Text(
                'לחץ "צור" לייצור Changelog',
                style: TextStyle(
                    color: Colors.grey,
                    fontFamily: 'Heebo',
                    fontSize: 13),
              )
            else
              ..._changelog.map((e) {
                final raw = e['hash'] as String? ?? '';
                final hash =
                    raw.substring(0, 7.clamp(0, raw.length));
                final message = e['message'] as String? ?? '—';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        hash,
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _proposalsCard() {
    final statusLabel = {
      'proposal': 'הצעה',
      'accepted': 'מאושר',
      'in_progress': 'בביצוע',
      'done': 'הושלם',
      'deferred': 'נדחה',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('הצעות ובאגים',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
              ),
              IconButton(
                icon: const Icon(Icons.bug_report, size: 20),
                tooltip: 'דיווח באג',
                onPressed: () => _showCreateProposalDialog('bug'),
              ),
              IconButton(
                icon: const Icon(Icons.lightbulb_outline, size: 20),
                tooltip: 'הצע פיצ\'ר',
                onPressed: () => _showCreateProposalDialog('feature'),
              ),
            ]),
            if (_proposalsLoading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()))
            else if (_proposals.isEmpty)
              const Text('אין הצעות עדיין',
                  style: TextStyle(color: Colors.grey, fontFamily: 'Heebo'))
            else
              ..._proposals.take(10).map((p) {
                final isFeature = (p['type'] as String?) != 'bug';
                final status = p['status'] as String? ?? 'proposal';
                final label = statusLabel[status] ?? status;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _openWorkshop(p),
                  leading: Text(isFeature ? '✨' : '🐛',
                      style: const TextStyle(fontSize: 18)),
                  title: Text(
                    p['title'] as String? ?? '—',
                    style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(label,
                        style: const TextStyle(fontSize: 11, fontFamily: 'Heebo')),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
