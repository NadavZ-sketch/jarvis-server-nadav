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

  // Section 2 — Test Recorder
  bool _recording = false;
  List<dynamic> _recordedTurns = [];
  final TextEditingController _saveNameCtrl = TextEditingController();

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
    _loadProposals();
  }

  @override
  void dispose() {
    _saveNameCtrl.dispose();
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

  // ── Test Recorder ───────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    await _api.startRecording('cc-session').catchError((_) => false);
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recordedTurns = [];
    });
  }

  Future<void> _stopRecording() async {
    final result =
        await _api.stopRecording('cc-session').catchError((_) => null);
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordedTurns = (result?['turns'] as List?) ?? [];
    });
  }

  Future<void> _saveTestCase() async {
    if (_saveNameCtrl.text.isEmpty) return;
    final turns = _recordedTurns.cast<Map<String, dynamic>>();
    await _api
        .saveTestCase(_saveNameCtrl.text, turns)
        .catchError((_) => null);
    if (!mounted) return;
    setState(() => _recordedTurns = []);
    _saveNameCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('נשמר!', style: TextStyle(fontFamily: 'Heebo'))),
    );
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
        _recorderCard(),
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

  Widget _recorderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('מקליט שיחה',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
            const SizedBox(height: 12),
            if (!_recording)
              ElevatedButton.icon(
                icon: const Icon(Icons.fiber_manual_record,
                    color: Colors.red),
                label: const Text('התחל הקלטה',
                    style: TextStyle(fontFamily: 'Heebo')),
                onPressed: _startRecording,
              )
            else ...[
              Row(children: [
                const Icon(Icons.fiber_manual_record,
                    color: Colors.red, size: 14),
                const SizedBox(width: 6),
                const Text('מקליט...',
                    style: TextStyle(
                        fontFamily: 'Heebo', color: Colors.red)),
                const Spacer(),
                ElevatedButton(
                  onPressed: _stopRecording,
                  child: const Text('עצור',
                      style: TextStyle(fontFamily: 'Heebo')),
                ),
              ]),
            ],
            if (_recordedTurns.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${_recordedTurns.length} תורות הוקלטו',
                  style: const TextStyle(
                      fontFamily: 'Heebo', fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _saveNameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'שם מקרה הבדיקה',
                      hintStyle: TextStyle(fontFamily: 'Heebo'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saveTestCase,
                  child: const Text('שמור',
                      style: TextStyle(fontFamily: 'Heebo')),
                ),
              ]),
            ],
          ],
        ),
      ),
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
