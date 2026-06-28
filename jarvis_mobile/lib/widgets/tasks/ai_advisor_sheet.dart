import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';

/// Phase 5 — AI Advisor planning sheet.
///
/// Opens at 90% screen height. Auto-loads task analysis on open.
/// Three sections: analysis bullets, quick-action cards, open question field.
class AiAdvisorSheet extends StatefulWidget {
  final TasksController controller;

  const AiAdvisorSheet({super.key, required this.controller});

  @override
  State<AiAdvisorSheet> createState() => _AiAdvisorSheetState();
}

class _AiAdvisorSheetState extends State<AiAdvisorSheet> {
  TasksController get _c => widget.controller;

  bool _analysisLoading = true;
  String? _analysisText;
  String? _actionResult;
  String? _actionLabel;
  bool _actionLoading = false;
  final _askCtrl = TextEditingController();
  bool _askLoading = false;
  String? _askResult;

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
  }

  @override
  void dispose() {
    _askCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAnalysis() async {
    setState(() => _analysisLoading = true);
    try {
      final openTasks = _c.tasks.where((t) => t['done'] != true).toList();
      _analysisText = await _c.api.getTaskInsights(openTasks);
    } catch (_) {
      _analysisText = 'לא ניתן לטעון ניתוח כרגע.';
    }
    if (mounted) setState(() => _analysisLoading = false);
  }

  String _buildTaskContext() {
    final openTasks = _c.tasks.where((t) => t['done'] != true).toList();
    return openTasks.take(20).map((t) {
      final title = (t['content'] as String? ?? '').split('\n<<<AI_PROMPT>>>\n').first;
      final cat = t['category']?.toString() ?? '';
      final pri = t['priority']?.toString() ?? 'medium';
      return '- $title ($pri${cat.isNotEmpty ? ', $cat' : ''})';
    }).join('\n');
  }

  Future<void> _runAction(String prompt, String label) async {
    setState(() { _actionLoading = true; _actionResult = null; _actionLabel = label; });
    try {
      final taskList = _buildTaskContext();
      final fullPrompt = '$prompt\n\nמשימות:\n$taskList';
      final res = await _c.api.askJarvis(fullPrompt, _c.settings, intent: 'chat');
      _actionResult = (res['answer'] as String? ?? '').trim();
    } catch (_) {
      _actionResult = 'שגיאה. נסה שוב.';
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  Future<void> _submitAsk() async {
    final q = _askCtrl.text.trim();
    if (q.isEmpty || _askLoading) return;
    FocusScope.of(context).unfocus();
    setState(() { _askLoading = true; _askResult = null; });
    try {
      final taskList = _buildTaskContext();
      final fullPrompt = '$q\n\nמשימות:\n$taskList';
      final res = await _c.api.askJarvis(fullPrompt, _c.settings, intent: 'chat');
      _askResult = (res['answer'] as String? ?? '').trim();
    } catch (_) {
      _askResult = 'שגיאה. נסה שוב.';
    }
    if (mounted) setState(() => _askLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: JC.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [JC.indigo500, JC.blue500],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Center(
                        child: Text('✨', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'עוזר תכנון',
                      style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Heebo'),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            color: JC.surface,
                            shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: JC.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: JC.border, height: 1),

              // Scrollable body
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    // ── Analysis ──────────────────────────────────────────
                    _sectionLabel('ניתוח נוכחי'),
                    const SizedBox(height: 8),
                    if (_analysisLoading)
                      _loadingSkeleton()
                    else
                      _AnalysisCard(text: _analysisText ?? ''),
                    const SizedBox(height: 20),

                    // ── Quick actions ─────────────────────────────────────
                    _sectionLabel('פעולות מהירות'),
                    const SizedBox(height: 8),
                    _ActionCard(
                      emoji: '🎯',
                      title: 'סדר עדיפויות מחדש',
                      subtitle: 'AI מסדר לפי דחיפות + חשיבות',
                      active: _actionLabel == 'priorities',
                      loading: _actionLoading && _actionLabel == 'priorities',
                      onTap: () => _runAction(
                          'בהינתן רשימת המשימות הבאה, מהן 5 המשימות שכדאי לטפל בהן קודם ולמה? '
                          'ענה בעברית, כל שורה — משימה אחת עם הנמקה קצרה.',
                          'priorities'),
                    ),
                    const SizedBox(height: 6),
                    _ActionCard(
                      emoji: '📆',
                      title: 'הצע חלוקה לשבוע',
                      subtitle: 'מחלק משימות פתוחות לימים',
                      active: _actionLabel == 'week',
                      loading: _actionLoading && _actionLabel == 'week',
                      onTap: () => _runAction(
                          'חלק את המשימות הפתוחות לימות השבוע הקרוב (ראשון עד שישי). '
                          'כל יום — 2-3 משימות מתאימות. ענה בעברית בפורמט ברור.',
                          'week'),
                    ),
                    const SizedBox(height: 6),
                    _ActionCard(
                      emoji: '🗑',
                      title: 'מצא משימות לדחייה',
                      subtitle: 'low priority + לא נגעת שבועיים',
                      active: _actionLabel == 'defer',
                      loading: _actionLoading && _actionLabel == 'defer',
                      onTap: () => _runAction(
                          'מהן המשימות שניתן לדחות או למחוק? '
                          'חפש עדיפות נמוכה, משימות ישנות, ומשימות לא ברורות. '
                          'ענה בעברית עם הנמקה קצרה לכל אחת.',
                          'defer'),
                    ),
                    if (_actionResult != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JC.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: JC.indigo500.withValues(alpha: 0.3), width: 0.8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_actionLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  switch (_actionLabel) {
                                    'priorities' => '🎯 סדר עדיפויות',
                                    'week'       => '📆 חלוקה לשבוע',
                                    'defer'      => '🗑 משימות לדחייה',
                                    _            => '',
                                  },
                                  style: TextStyle(
                                      color: JC.indigo300,
                                      fontSize: 11,
                                      fontFamily: 'Heebo',
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            Text(
                              _actionResult!,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                  color: JC.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'Heebo',
                                  height: 1.6),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ── Ask ───────────────────────────────────────────────
                    _sectionLabel('שאל את ה-AI'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: JC.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JC.border, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _askCtrl,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                  color: JC.textPrimary,
                                  fontFamily: 'Heebo',
                                  fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'שאל משהו... "איך לארגן את השבוע?"',
                                hintStyle: TextStyle(
                                    color: JC.textMuted,
                                    fontFamily: 'Heebo',
                                    fontSize: 12),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              onSubmitted: (_) => _submitAsk(),
                            ),
                          ),
                          if (_askLoading)
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5, color: JC.indigo300)),
                            )
                          else
                            GestureDetector(
                              onTap: _submitAsk,
                              child: Container(
                                margin: const EdgeInsets.all(6),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: JC.indigo500.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.arrow_upward_rounded,
                                    size: 15, color: JC.indigo300),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_askResult != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JC.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: JC.indigo300.withValues(alpha: 0.25), width: 0.8),
                        ),
                        child: Text(
                          _askResult!,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              color: JC.textPrimary,
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              height: 1.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
            color: JC.textMuted,
            fontSize: 10.5,
            fontFamily: 'Heebo',
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8),
      );

  Widget _loadingSkeleton() => Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: 14,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ],
      );
}

// ─── Analysis card ────────────────────────────────────────────────────────────

class _AnalysisCard extends StatelessWidget {
  final String text;
  const _AnalysisCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return Column(
      children: [
        for (final line in lines)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: JC.border, width: 0.7),
            ),
            child: Text(
              line,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                  height: 1.45),
            ),
          ),
      ],
    );
  }
}

// ─── Action card ──────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool loading;
  final bool active;
  final VoidCallback onTap;

  const _ActionCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? JC.indigo500.withValues(alpha: 0.08)
              : JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? JC.indigo300.withValues(alpha: 0.5) : JC.border,
            width: active ? 1.0 : 0.7,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: active ? JC.indigo300 : JC.textPrimary,
                          fontSize: 13,
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo')),
                ],
              ),
            ),
            if (loading)
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: JC.indigo300))
            else
              Icon(Icons.chevron_left_rounded,
                  color: active ? JC.indigo300 : JC.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
