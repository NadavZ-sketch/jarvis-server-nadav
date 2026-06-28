// improve_workshop.dart — Slice 3: survey modal + dynamic interview sheet.
//
// Exposes two library-level functions imported by tab_improve.dart:
//   showSmartSurveySheet(context, api, userName)
//   showImproveInterviewSheet(context, api, {initialGoal})
//
// Style mirrors tab_overview.dart / tab_agents.dart (JC tokens, Heebo, RTL).

import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the "סקר חכם" bottom sheet.
/// Fetches questions from [api.getSurveyCheck], renders chips / text-fields,
/// and POSTs answers via [api.submitSurvey] on confirm.
Future<void> showSmartSurveySheet(
  BuildContext context,
  ApiService api,
  String userName,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SurveySheet(api: api, userName: userName),
  );
}

/// Shows the "תחקיר שיפור" dynamic-interview bottom sheet.
/// Optionally pre-fills the goal field with [initialGoal].
Future<void> showImproveInterviewSheet(
  BuildContext context,
  ApiService api, {
  String? initialGoal,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InterviewSheet(api: api, initialGoal: initialGoal),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Survey sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SurveySheet extends StatefulWidget {
  final ApiService api;
  final String userName;

  const _SurveySheet({required this.api, required this.userName});

  @override
  State<_SurveySheet> createState() => _SurveySheetState();
}

class _SurveySheetState extends State<_SurveySheet> {
  List<Map<String, dynamic>> _questions = [];
  bool _loading = true;
  bool _submitting = false;

  // responses map: questionId -> answer string
  final Map<String, String> _responses = {};
  // text controllers for free-text questions
  final Map<String, TextEditingController> _textCtrl = {};

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  @override
  void dispose() {
    for (final c in _textCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchQuestions() async {
    try {
      final qs = await widget.api.getSurveyCheck(widget.userName);
      if (!mounted) return;
      setState(() {
        _questions = qs;
        _loading = false;
        // Pre-create text controllers for free-text questions
        for (int i = 0; i < qs.length; i++) {
          final q = qs[i];
          if (_isFreeText(q)) {
            final id = _qId(q, i);
            // Listener so the send button enables for free-text-only surveys.
            _textCtrl[id] = TextEditingController()
              ..addListener(() {
                if (mounted) setState(() {});
              });
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ── Helpers to handle dynamic question shape ──────────────────────────────

  /// Returns the question id, falling back to index string.
  String _qId(Map<String, dynamic> q, int index) {
    final id = q['id'];
    if (id != null) return id.toString();
    return index.toString();
  }

  /// Returns the question text from any of the known keys.
  String _qText(Map<String, dynamic> q) {
    return (q['question'] as String? ??
            q['text'] as String? ??
            q['title'] as String? ??
            q['label'] as String? ??
            '')
        .trim();
  }

  /// Returns chip option strings from any of the known keys.
  List<String> _qOptions(Map<String, dynamic> q) {
    final raw = q['options'] ?? q['choices'] ?? q['chips'];
    if (raw is! List) return [];
    return raw.map<String>((e) {
      if (e is String) return e;
      if (e is Map) {
        return (e['label'] as String? ?? e['value'] as String? ?? e.toString());
      }
      return e.toString();
    }).toList();
  }

  /// True if this question expects free-text input.
  bool _isFreeText(Map<String, dynamic> q) {
    final type = (q['type'] as String? ?? '').toLowerCase();
    if (type == 'text' || type == 'free' || type == 'open') return true;
    // No options → treat as free text
    return _qOptions(q).isEmpty;
  }

  bool get _hasAnyAnswer {
    if (_responses.isNotEmpty) return true;
    for (final c in _textCtrl.values) {
      if (c.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _submit() async {
    // Merge text-field values into responses
    _textCtrl.forEach((id, ctrl) {
      final txt = ctrl.text.trim();
      if (txt.isNotEmpty) _responses[id] = txt;
    });

    if (!_hasAnyAnswer) return;

    setState(() => _submitting = true);
    try {
      final result = await widget.api
          .submitSurvey(responses: _responses, userName: widget.userName);
      if (!mounted) return;
      Navigator.of(context).pop();
      final summary = result['summary'] as String? ?? 'תודה על המשוב';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(summary, style: const TextStyle(fontFamily: 'Heebo')),
          backgroundColor: JC.green500,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('שגיאה בשליחת התשובות',
              style: TextStyle(fontFamily: 'Heebo')),
          backgroundColor: JC.cancelRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: JC.shadow.withOpacity(0.25),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            _DragHandle(),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'סקר חכם',
                          style: TextStyle(
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: JC.amber400,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'השאלות נבחרו לפי השימוש האחרון שלך בג\'רוויס.',
                          style: TextStyle(
                              fontFamily: 'Heebo',
                              fontSize: 12,
                              color: JC.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: JC.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _questions.isEmpty
                      ? _emptyState()
                      : _questionList(),
            ),
            // Footer buttons
            if (!_loading && _questions.isNotEmpty) _footerButtons(),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: JC.green500),
          const SizedBox(height: 12),
          Text(
            'אין סקר זמין כרגע',
            style: TextStyle(
                fontFamily: 'Heebo', fontSize: 15, color: JC.textMuted),
          ),
          const SizedBox(height: 20),
          _actionButton(
            label: 'סגור',
            color: JC.blue400,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _questionList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      itemCount: _questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 18),
      itemBuilder: (_, i) {
        final q = _questions[i];
        final id = _qId(q, i);
        return _QuestionCard(
          number: i + 1,
          questionText: _qText(q),
          options: _qOptions(q),
          isFreeText: _isFreeText(q),
          selected: _responses[id],
          textController: _textCtrl[id],
          onSelect: (val) => setState(() => _responses[id] = val),
        );
      },
    );
  }

  Widget _footerButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Row(
          children: [
            _actionButton(
              label: 'שמור להמשך',
              color: JC.textMuted,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            _actionButton(
              label: 'דלג',
              color: JC.blue400,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            _submitting
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: JC.green500),
                  )
                : _actionButton(
                    label: 'שלח תשובות',
                    color: JC.green500,
                    onPressed: _hasAnyAnswer ? _submit : null,
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual question card
// ─────────────────────────────────────────────────────────────────────────────

class _QuestionCard extends StatelessWidget {
  final int number;
  final String questionText;
  final List<String> options;
  final bool isFreeText;
  final String? selected;
  final TextEditingController? textController;
  final ValueChanged<String> onSelect;

  const _QuestionCard({
    required this.number,
    required this.questionText,
    required this.options,
    required this.isFreeText,
    required this.selected,
    required this.textController,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border.all(color: JC.border.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Number badge + question text
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsetsDirectional.only(end: 10),
                decoration: BoxDecoration(
                  color: JC.amber400.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: JC.amber400.withOpacity(0.5)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: JC.amber400,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  questionText,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: JC.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Options or text field
          if (isFreeText && textController != null)
            TextField(
              controller: textController,
              minLines: 2,
              maxLines: 4,
              style: TextStyle(
                  fontFamily: 'Heebo', fontSize: 13, color: JC.textPrimary),
              decoration: InputDecoration(
                hintText: 'כתוב כאן…',
                hintStyle: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 12,
                    color: JC.textMuted),
                filled: true,
                fillColor: JC.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: JC.border.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: JC.border.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: JC.amber400),
                ),
                contentPadding: const EdgeInsets.all(10),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: options.map((opt) {
                final isSelected = selected == opt;
                return GestureDetector(
                  onTap: () => onSelect(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? JC.amber400.withOpacity(0.22)
                          : JC.surface,
                      border: Border.all(
                        color: isSelected
                            ? JC.amber400
                            : JC.border.withOpacity(0.35),
                        width: isSelected ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isSelected ? JC.amber400 : JC.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Interview sheet
// ─────────────────────────────────────────────────────────────────────────────

class _InterviewSheet extends StatefulWidget {
  final ApiService api;
  final String? initialGoal;

  const _InterviewSheet({required this.api, this.initialGoal});

  @override
  State<_InterviewSheet> createState() => _InterviewSheetState();
}

class _InterviewSheetState extends State<_InterviewSheet> {
  late final TextEditingController _goalCtrl;
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  int? _proposalId;
  bool _starting = false;
  bool _sending = false;
  bool _sessionActive = false;

  final List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _latestSpec;

  @override
  void initState() {
    super.initState();
    _goalCtrl =
        TextEditingController(text: widget.initialGoal?.trim() ?? '');
    // Rebuild so the "התחל תחקיר" button enables/disables as the goal is typed.
    _goalCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Start session ──────────────────────────────────────────────────────────
  Future<void> _startSession() async {
    final goal = _goalCtrl.text.trim();
    if (goal.isEmpty) return;

    setState(() => _starting = true);

    final proposal = await widget.api.createProposal(goal, 'feature');
    if (proposal == null) {
      if (!mounted) return;
      setState(() => _starting = false);
      _showError('לא ניתן ליצור הצעה. נסה שוב.');
      return;
    }

    // (x as num?)?.toInt() — never `as int`
    final id = (proposal['id'] as num?)?.toInt();
    if (id == null) {
      if (!mounted) return;
      setState(() => _starting = false);
      _showError('תשובה לא תקינה מהשרת.');
      return;
    }

    _proposalId = id;
    // Append user's goal as first user turn
    _history.add({'role': 'user', 'content': goal});

    final reply =
        await widget.api.workshopChat(proposalId: id, message: goal, history: []);

    if (!mounted) return;

    if (reply == null) {
      setState(() {
        _sessionActive = true;
        _starting = false;
        _history.add({
          'role': 'assistant',
          'content': 'לא הצלחתי ליצור שאלה כרגע. נסה לשלוח הודעה.',
        });
      });
      return;
    }

    final replyText = reply['reply'] as String? ?? '';
    final spec = reply['spec'] as Map<String, dynamic>?;

    setState(() {
      _history.add({'role': 'assistant', 'content': replyText});
      if (spec != null) _latestSpec = spec;
      _sessionActive = true;
      _starting = false;
    });

    _scrollToBottom();
  }

  // ── Send a chat message ────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty || _proposalId == null) return;

    _msgCtrl.clear();
    setState(() {
      _history.add({'role': 'user', 'content': msg});
      _sending = true;
    });
    _scrollToBottom();

    final reply = await widget.api.workshopChat(
      proposalId: _proposalId!,
      message: msg,
      history: List<Map<String, dynamic>>.from(_history),
    );

    if (!mounted) return;

    if (reply == null) {
      setState(() {
        _history.add({
          'role': 'assistant',
          'content': 'לא קיבלתי תשובה. נסה שוב.',
        });
        _sending = false;
      });
      _scrollToBottom();
      return;
    }

    final replyText = reply['reply'] as String? ?? '';
    final spec = reply['spec'] as Map<String, dynamic>?;

    setState(() {
      _history.add({'role': 'assistant', 'content': replyText});
      if (spec != null) _latestSpec = spec;
      _sending = false;
    });
    _scrollToBottom();
  }

  // ── Save spec ──────────────────────────────────────────────────────────────
  Future<void> _saveSpec() async {
    if (_proposalId == null || _latestSpec == null) return;

    final result = await widget.api
        .saveWorkshopSpec(proposalId: _proposalId!, spec: _latestSpec!);

    if (!mounted) return;

    if (result == null) {
      _showError('שגיאה בשמירה.');
      return;
    }

    final path = result['path'] as String? ?? 'Backlog';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('נשמר: $path', style: const TextStyle(fontFamily: 'Heebo')),
        backgroundColor: JC.green500,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
        backgroundColor: JC.cancelRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.92;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: JC.shadow.withOpacity(0.25),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          children: [
            _DragHandle(),
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'תחקיר שיפור',
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        color: JC.amber400,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: JC.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Intent strip (goal input)
            if (!_sessionActive) _intentStrip(),

            // Chat body
            if (_sessionActive) _chatBody(),

            // Spec preview card
            if (_latestSpec != null) _specCard(),

            // Fallback note
            _fallbackNote(),

            // Input row (only when session is active)
            if (_sessionActive) _chatInputRow(),
          ],
        ),
      ),
    );
  }

  // ── Intent strip ───────────────────────────────────────────────────────────
  Widget _intentStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border.all(color: JC.amber400.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'המטרה הראשית',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: JC.textPrimary,
                  ),
                ),
              ),
              _pill('בסיס לתחקיר', JC.green500),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _goalCtrl,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(
                fontFamily: 'Heebo', fontSize: 13, color: JC.textPrimary),
            decoration: InputDecoration(
              hintText: 'מה אתה רוצה לשפר?',
              hintStyle: TextStyle(
                  fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted),
              filled: true,
              fillColor: JC.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.border.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.border.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.amber400),
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _starting
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: JC.amber400),
                  )
                : _actionButton(
                    label: 'התחל תחקיר',
                    color: JC.amber400,
                    onPressed: _goalCtrl.text.trim().isNotEmpty
                        ? _startSession
                        : null,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Chat body ──────────────────────────────────────────────────────────────
  Widget _chatBody() {
    return Expanded(
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        itemCount: _history.length,
        itemBuilder: (_, i) {
          final msg = _history[i];
          final isUser = msg['role'] == 'user';
          final text = msg['content'] as String? ?? '';
          return _ChatBubble(text: text, isUser: isUser);
        },
      ),
    );
  }

  // ── Spec preview card ─────────────────────────────────────────────────────
  Widget _specCard() {
    final spec = _latestSpec!;
    final name = spec['name'] as String? ?? '';
    final desc = spec['description'] as String? ?? '';
    final criteria = List<String>.from(
        (spec['acceptanceCriteria'] as List? ?? []));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border.all(color: JC.green500.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'פרומפט מדויק מוכן',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: JC.textPrimary,
                  ),
                ),
              ),
              _pill('מוכן', JC.green500),
            ],
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: JC.amber400,
              ),
            ),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              desc,
              style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 12,
                  color: JC.textSecondary,
                  height: 1.45),
            ),
          ],
          if (criteria.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...criteria.take(3).map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '• $c',
                    style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 11,
                        color: JC.textMuted),
                  ),
                )),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                label: 'שמור ל-Backlog / שלח לקודקס',
                color: JC.green500,
                onPressed: _saveSpec,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Fallback note ─────────────────────────────────────────────────────────
  Widget _fallbackNote() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.amber400.withOpacity(0.06),
        border: Border.all(
          color: JC.amber400.withOpacity(0.35),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: JC.amber400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'אם ג\'רוויס אינו זמין, ניתן למלא שאלון בסיס קבוע במקום תחקיר דינמי.',
              style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 11,
                  color: JC.amber400,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Chat input row ─────────────────────────────────────────────────────────
  Widget _chatInputRow() {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    color: JC.textPrimary),
                decoration: InputDecoration(
                  hintText: 'כתוב הודעה…',
                  hintStyle: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 12,
                      color: JC.textMuted),
                  filled: true,
                  fillColor: JC.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: JC.border.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        BorderSide(color: JC.border.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: JC.amber400),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? SizedBox(
                    width: 38,
                    height: 38,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: JC.amber400),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: JC.amber400.withOpacity(0.15),
                        border: Border.all(
                            color: JC.amber400.withOpacity(0.5)),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.send,
                          size: 18, color: JC.amber400),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // ── Shared pill ────────────────────────────────────────────────────────────
  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.38)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat bubble (mirrors tab_agents dialog bubble styling)
// ─────────────────────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;

  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
        isUser ? JC.amber400.withOpacity(0.18) : JC.surfaceAlt;
    final borderColor =
        isUser ? JC.amber400.withOpacity(0.4) : JC.border.withOpacity(0.25);
    final textColor = isUser ? JC.textPrimary : JC.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        // In RTL: user is "inline-start" (right side), assistant is "inline-end" (left)
        alignment:
            isUser ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 13,
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared action button (mirrors tab_overview / tab_agents pattern)
// ─────────────────────────────────────────────────────────────────────────────

Widget _actionButton({
  required String label,
  required Color color,
  VoidCallback? onPressed,
}) {
  return OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withOpacity(onPressed != null ? 0.42 : 0.2)),
      backgroundColor: color.withOpacity(onPressed != null ? 0.08 : 0.03),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(
          fontFamily: 'Heebo', fontWeight: FontWeight.w900, fontSize: 12),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag handle
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: JC.border.withOpacity(0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
