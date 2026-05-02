import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_settings.dart';
import '../main.dart' show JC;
import '../services/mission_service.dart';

/// Full-screen "active mission" UI. The state machine on the server drives
/// what's visible: clarifying/planning → chat-only; awaiting_approval →
/// approval banner + plan preview; executing → plan checklist + Claude Code
/// prompt + chat; done/cancelled → read-only view.
class ActiveMissionScreen extends StatefulWidget {
  final AppSettings settings;
  final int missionId;
  const ActiveMissionScreen({
    super.key,
    required this.settings,
    required this.missionId,
  });

  @override
  State<ActiveMissionScreen> createState() => _ActiveMissionScreenState();
}

class _ActiveMissionScreenState extends State<ActiveMissionScreen> {
  late final MissionService _api = MissionService(widget.settings);
  Map<String, dynamic>? _mission;
  bool _loading = true;
  bool _sending = false;
  bool _approving = false;
  String? _error;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final m = await _api.get(widget.missionId);
      if (!mounted) return;
      setState(() {
        _mission = m;
        _loading = false;
        _error = m == null ? 'המשימה לא נמצאה' : null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'שגיאת רשת: $e'; });
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final txt = _input.text.trim();
    if (txt.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      final res = await _api.sendMessage(widget.missionId, txt);
      if (!mounted) return;
      setState(() => _mission = res['mission'] as Map<String, dynamic>?);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) _snack('שגיאת שליחה: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _approve() async {
    if (_approving) return;
    setState(() => _approving = true);
    try {
      final m = await _api.approve(widget.missionId);
      if (!mounted) return;
      setState(() => _mission = m);
      _snack('יוצא לדרך', short: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (mounted) _snack('שגיאת אישור: $e');
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _regenerate() async {
    final feedback = await _askText(
      title: 'מה לעדכן בתוכנית?',
      hint: 'תיאור קצר במשפט-שניים',
    );
    if (feedback == null || !mounted) return;
    setState(() => _approving = true);
    try {
      final res = await _api.regeneratePlan(widget.missionId, feedback: feedback);
      if (!mounted) return;
      setState(() => _mission = res['mission'] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) _snack('שגיאת עדכון תוכנית: $e');
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await _confirm(title: 'לבטל את המשימה?', confirmLabel: 'בטל משימה');
    if (ok != true || !mounted) return;
    try {
      final m = await _api.cancel(widget.missionId);
      if (!mounted) return;
      setState(() => _mission = m);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack('שגיאת ביטול: $e');
    }
  }

  Future<void> _toggleStep(Map<String, dynamic> step) async {
    final cur = step['status']?.toString() ?? 'pending';
    final next = cur == 'done' ? 'pending' : 'done';
    try {
      final m = await _api.setStepStatus(
          widget.missionId, step['id']?.toString() ?? '', next);
      if (!mounted) return;
      setState(() => _mission = m);
    } catch (e) {
      if (mounted) _snack('שגיאה בעדכון שלב: $e');
    }
  }

  Future<void> _copyPrompt(String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) _snack('הפרומפט הועתק ל-Claude Code', short: true);
  }

  void _snack(String msg, {bool short = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
      duration: Duration(seconds: short ? 2 : 4),
      backgroundColor: JC.surfaceAlt,
    ));
  }

  Future<String?> _askText({required String title, String hint = ''}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: Text(title,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
              filled: true, fillColor: JC.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: JC.border),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('שלח',
                  style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    return (result == null || result.isEmpty) ? null : result;
  }

  Future<bool?> _confirm({required String title, required String confirmLabel}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: Text(title,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('לא',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel,
                  style: const TextStyle(color: JC.cancelRed, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('משימה פעילה',
            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 17)),
        actions: [
          if (_mission != null && !_isTerminal(_mission!))
            IconButton(
              tooltip: 'בטל משימה',
              onPressed: _cancel,
              icon: const Icon(Icons.close_rounded, color: JC.cancelRed, size: 20),
            ),
          IconButton(
            tooltip: 'רענן',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: JC.textMuted, size: 20),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2))
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  bool _isTerminal(Map<String, dynamic> m) =>
      ['done', 'cancelled'].contains(m['status']);

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error ?? 'שגיאה',
              textAlign: TextAlign.center,
              style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14)),
        ),
      );

  Widget _buildBody() {
    final m = _mission!;
    final status = m['status']?.toString() ?? 'clarifying';
    final plan = (m['plan'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final exec = (m['executorState'] as Map?)?.cast<String, dynamic>() ?? const {};
    final convo = (m['conversation'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          _buildHeader(m, status, plan),
          if (status == 'awaiting_approval') _buildApprovalBanner(),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              children: [
                if (m['goal'] != null && (m['goal'] as String).isNotEmpty)
                  _buildGoal(m['goal'] as String),
                if (plan.isNotEmpty) _buildPlan(plan, status),
                if (exec['prompt'] != null) _buildPromptCard(exec['prompt'] as String),
                if (exec['notice'] != null) _buildNoticeCard(exec['notice'] as String),
                if ((exec['errors'] as List?)?.isNotEmpty == true)
                  _buildErrorsCard((exec['errors'] as List).cast<String>()),
                const SizedBox(height: 14),
                _buildConversation(convo),
              ],
            ),
          ),
          if (!_isTerminal(m)) _buildInput(status),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> m, String status, List<Map<String, dynamic>> plan) {
    final title = m['title']?.toString() ?? '';
    final source = m['source']?.toString() ?? '';
    final done = plan.where((s) => s['status'] == 'done').length;
    final total = plan.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      decoration: const BoxDecoration(
        color: JC.surface,
        border: Border(bottom: BorderSide(color: JC.border, width: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _statusPill(status),
            const SizedBox(width: 8),
            _sourcePill(source),
            if (total > 0) ...[
              const Spacer(),
              Text('$done / $total שלבים',
                  style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
            ],
          ]),
          const SizedBox(height: 8),
          Text(title.isNotEmpty ? title : '(ללא כותרת)',
              style: const TextStyle(color: JC.textPrimary,
                  fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    String label; Color color;
    switch (status) {
      case 'clarifying':         label = '❓ בירור'; color = JC.blue400; break;
      case 'planning':           label = '🧠 מתכנן'; color = JC.blue400; break;
      case 'awaiting_approval':  label = '✋ ממתין לאישור'; color = const Color(0xFFF59E0B); break;
      case 'executing':          label = '⚡ מבצע'; color = const Color(0xFF22C55E); break;
      case 'paused':             label = '⏸ מושהית'; color = JC.textMuted; break;
      case 'done':               label = '✅ הושלמה'; color = const Color(0xFF22C55E); break;
      case 'cancelled':          label = '✖ בוטלה'; color = JC.cancelRed; break;
      default:                   label = status; color = JC.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35), width: 0.7),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sourcePill(String source) {
    final label = {
      'proposal': '🤖 הצעת AI',
      'manual':   '✍️ ידני',
      'factory':  '🏭 יצירת אייג\'נט',
    }[source] ?? source;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: JC.border, width: 0.5),
      ),
      child: Text(label,
          style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
    );
  }

  Widget _buildApprovalBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFFF59E0B).withOpacity(0.08),
      child: Row(children: [
        const Icon(Icons.help_outline_rounded, color: Color(0xFFF59E0B), size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('התוכנית מוכנה. לאשר ולהתחיל לעבוד?',
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13)),
        ),
        TextButton(
          onPressed: _approving ? null : _regenerate,
          child: const Text('עדכן',
              style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: _approving ? null : _approve,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13),
          ),
          child: _approving
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('אשר ✓'),
        ),
      ]),
    );
  }

  Widget _buildGoal(String goal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JC.surface,
            border: Border(left: BorderSide(color: JC.blue400.withOpacity(0.5), width: 2.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('🎯 מטרה',
                style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 4),
            Text(goal,
                style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 14, height: 1.4)),
          ]),
        ),
      ),
    );
  }

  Widget _buildPlan(List<Map<String, dynamic>> plan, String status) {
    final canEdit = status == 'executing';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          decoration: BoxDecoration(
            color: JC.surface,
            border: Border.all(color: JC.border, width: 0.6),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('📋 תוכנית',
                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            ...plan.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value;
              final st = s['status']?.toString() ?? 'pending';
              final done = st == 'done';
              return InkWell(
                onTap: canEdit ? () => _toggleStep(s) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 22, height: 22,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: done ? const Color(0xFF22C55E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: done ? const Color(0xFF22C55E) : JC.border,
                          width: 1.4,
                        ),
                      ),
                      child: done
                          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                          : Center(
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['text']?.toString() ?? '',
                            style: TextStyle(
                              color: done ? JC.textMuted : JC.textPrimary,
                              fontFamily: 'Heebo', fontSize: 13, height: 1.35,
                              decoration: done ? TextDecoration.lineThrough : null,
                            )),
                        if (s['why'] != null && (s['why'] as String).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(s['why'].toString(),
                                style: const TextStyle(
                                    color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              );
            }),
          ]),
        ),
      ),
    );
  }

  Widget _buildPromptCard(String prompt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JC.blue500.withOpacity(0.07),
            border: Border.all(color: JC.blue400.withOpacity(0.3), width: 0.7),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('🤖 פרומפט ל-Claude Code',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              GestureDetector(
                onTap: () => _copyPrompt(prompt),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: JC.blue500.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('📋 העתק',
                      style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(prompt,
                maxLines: 6, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.45)),
          ]),
        ),
      ),
    );
  }

  Widget _buildNoticeCard(String notice) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withOpacity(0.08),
            border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3), width: 0.7),
          ),
          child: Text(notice,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 12, height: 1.4)),
        ),
      ),
    );
  }

  Widget _buildErrorsCard(List<String> errors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: JC.cancelRed.withOpacity(0.08),
            border: Border.all(color: JC.cancelRed.withOpacity(0.3), width: 0.7),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⚠️ שגיאות באקזקיוטר',
                style: TextStyle(color: JC.cancelRed, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 4),
            ...errors.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('• $e',
                      style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11)),
                )),
          ]),
        ),
      ),
    );
  }

  Widget _buildConversation(List<Map<String, dynamic>> convo) {
    if (convo.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Text('Jarvis יתחיל לדבר בעוד רגע...',
            textAlign: TextAlign.center,
            style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: convo.map(_buildMsg).toList(),
    );
  }

  Widget _buildMsg(Map<String, dynamic> m) {
    final isUser = m['role'] == 'user';
    final text = m['text']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isUser ? JC.userBubble : JC.jarvisBubble,
                  border: Border.all(color: JC.border, width: 0.5),
                ),
                child: Text(text,
                    style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13, height: 1.45)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(String status) {
    final hint = switch (status) {
      'clarifying'        => 'תכתוב לJarvis את התשובה...',
      'planning'          => 'מתכנן... חכה רגע',
      'awaiting_approval' => 'תכתוב פידבק או אשר את התוכנית',
      'executing'         => 'תכתוב להJarvis עדכון או שאלה',
      _                   => 'הקלד הודעה',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: const BoxDecoration(
        color: JC.surface,
        border: Border(top: BorderSide(color: JC.border, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1, maxLines: 4,
              textDirection: TextDirection.rtl,
              enabled: !_sending && status != 'planning',
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true, fillColor: JC.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: JC.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: JC.border, width: 0.7),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: JC.blue400, width: 0.9),
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JC.blue500,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _sending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    );
  }
}
