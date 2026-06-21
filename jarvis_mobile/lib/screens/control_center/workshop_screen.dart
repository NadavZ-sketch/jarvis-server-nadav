import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../app_settings.dart';
import '../../services/api_service.dart';

class WorkshopScreen extends StatefulWidget {
  final Map<String, dynamic> proposal;
  final AppSettings settings;
  final http.Client? httpClient;

  const WorkshopScreen({
    super.key,
    required this.proposal,
    required this.settings,
    this.httpClient,
  });

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  late final ApiService _api;
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _spec;
  bool _sending = false;
  bool _specExpanded = false;

  @override
  void initState() {
    super.initState();
    _api = widget.httpClient != null
        ? ApiService(widget.settings, client: widget.httpClient!)
        : ApiService(widget.settings);

    // Load prior workshop history from proposal
    final history = widget.proposal['workshopHistory'];
    if (history is List && history.isNotEmpty) {
      _messages = List<Map<String, dynamic>>.from(
          history.map((e) => {'role': e['role'] ?? 'user', 'content': e['content'] ?? ''}));
    }

    // Seed spec from proposal fields
    final desc = widget.proposal['plan'] as String? ?? '';
    final ac = widget.proposal['acceptanceCriteria'];
    if (desc.isNotEmpty || (ac is List && ac.isNotEmpty)) {
      _spec = {
        'name': widget.proposal['title'] as String? ?? '',
        'type': widget.proposal['type'] as String? ?? 'feature',
        'description': desc,
        'acceptanceCriteria': ac is List ? List<String>.from(ac.map((e) => e.toString())) : <String>[],
      };
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages = [..._messages, {'role': 'user', 'content': text}];
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    final history = _messages
        .take(_messages.length - 1)
        .map((m) => {'role': m['role'] as String, 'content': m['content'] as String})
        .toList();

    final result = await _api.workshopChat(
      proposalId: widget.proposal['id'] as int,
      message: text,
      history: history,
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result != null) {
        final reply = result['reply'] as String? ?? '';
        if (reply.isNotEmpty) {
          _messages = [..._messages, {'role': 'assistant', 'content': reply}];
        }
        final newSpec = result['spec'];
        if (newSpec is Map<String, dynamic>) {
          _spec = newSpec;
        }
      } else {
        _messages = [..._messages, {'role': 'assistant', 'content': 'שגיאה בתקשורת עם השרת. נסה שוב.'}];
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _buildSpecMarkdown() {
    final spec = _spec;
    if (spec == null) return '';
    final sb = StringBuffer();
    sb.writeln('# ${spec['name'] ?? widget.proposal['title']}');
    sb.writeln();
    sb.writeln('**סוג:** ${spec['type'] ?? 'feature'}');
    sb.writeln();
    sb.writeln('## תיאור');
    sb.writeln(spec['description'] ?? '');
    sb.writeln();
    sb.writeln('## קריטריוני קבלה');
    final ac = spec['acceptanceCriteria'];
    if (ac is List) {
      for (final item in ac) {
        sb.writeln('- $item');
      }
    }
    return sb.toString();
  }

  String _buildAiPrompt() {
    final claudePrompt = widget.proposal['claudePrompt'] as String?;
    if (claudePrompt != null && claudePrompt.isNotEmpty) return claudePrompt;
    final spec = _spec;
    if (spec == null) return 'Implement: ${widget.proposal['title']}';
    final sb = StringBuffer();
    sb.writeln('Implement: ${spec['name'] ?? widget.proposal['title']}');
    sb.writeln();
    sb.writeln('Description: ${spec['description'] ?? ''}');
    sb.writeln();
    sb.writeln('Acceptance Criteria:');
    final ac = spec['acceptanceCriteria'];
    if (ac is List) {
      for (final item in ac) {
        sb.writeln('- $item');
      }
    }
    return sb.toString();
  }

  Future<void> _exportSpec() async {
    final proposalId = widget.proposal['id'] as int;
    final result = await _api.saveWorkshopSpec(proposalId: proposalId, spec: _spec ?? {});
    if (!mounted) return;
    final msg = result != null ? 'ספק נשמר ב-docs/superpowers/specs/' : 'שגיאה בשמירת הספק';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Heebo'))),
    );
  }

  Future<void> _copyAiPrompt() async {
    final prompt = _buildAiPrompt();
    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI Prompt הועתק ללוח', style: TextStyle(fontFamily: 'Heebo'))),
    );
  }

  Future<void> _createGitHubIssue() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('GitHub Integration כבר בקרוב', style: TextStyle(fontFamily: 'Heebo'))),
    );
  }

  Future<void> _copyToClipboard() async {
    final md = _buildSpecMarkdown();
    await Clipboard.setData(ClipboardData(text: md));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הועתק ללוח', style: TextStyle(fontFamily: 'Heebo'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.proposal['title'] as String? ?? 'סדנה';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontFamily: 'Heebo', fontSize: 16)),
        actions: [
          IconButton(
            icon: Icon(
              Icons.description_outlined,
              color: _spec != null ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: 'ספק',
            onPressed: () => setState(() => _specExpanded = !_specExpanded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_specExpanded && _spec != null) _buildSpecPanel(),
          Expanded(child: _buildChatList()),
          _buildExportRow(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildSpecPanel() {
    final spec = _spec!;
    final ac = spec['acceptanceCriteria'];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const Icon(Icons.description_outlined, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  spec['name'] as String? ?? '',
                  style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  spec['type'] as String? ?? 'feature',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontFamily: 'Heebo'),
                ),
              ),
            ]),
            if ((spec['description'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                spec['description'] as String,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13, color: Colors.black87),
              ),
            ],
            if (ac is List && ac.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('קריטריוני קבלה:', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
              ...ac.map((item) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('• ', style: TextStyle(color: Colors.green)),
                      Expanded(child: Text(item.toString(), style: const TextStyle(fontFamily: 'Heebo', fontSize: 12))),
                    ]),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'התחל שיחה כדי לפתח את ההצעה',
          style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (_sending && i == _messages.length) {
          return const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }
        final msg = _messages[i];
        final isUser = (msg['role'] as String?) == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser ? Theme.of(context).colorScheme.primary : Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
                bottomRight: isUser ? Radius.zero : const Radius.circular(12),
              ),
            ),
            child: Text(
              msg['content'] as String? ?? '',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 14,
                color: isUser ? Colors.white : Colors.black87,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExportRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _exportBtn(icon: Icons.description, label: 'ספק', onTap: _spec != null ? _exportSpec : null),
          _exportBtn(icon: Icons.smart_toy_outlined, label: 'AI Prompt', onTap: _copyAiPrompt),
          _exportBtn(icon: Icons.code, label: 'GitHub', onTap: _createGitHubIssue),
          _exportBtn(icon: Icons.copy, label: 'העתק', onTap: _spec != null ? _copyToClipboard : null),
        ],
      ),
    );
  }

  Widget _exportBtn({required IconData icon, required String label, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey.shade400),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'Heebo',
              color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _focusNode,
              maxLines: null,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                hintText: 'שאל שאלה או הוסף פרטים...',
                hintStyle: TextStyle(fontFamily: 'Heebo', fontSize: 14),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'Heebo', fontSize: 14),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            tooltip: 'שלח',
          ),
        ]),
      ),
    );
  }
}
