import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// The proactive Jarvis card — a merge of the old "what now" (load gauge + top
/// item) and "Jarvis insight" (time-of-day AI thread) cards. The load gauge is
/// computed locally from the task/reminder state (no `/day-plan` LLM call); the
/// insight thread is the only LLM-backed piece.
class JarvisCard extends StatefulWidget {
  final HomeController c;
  const JarvisCard(this.c, {super.key});

  @override
  State<JarvisCard> createState() => _JarvisCardState();
}

class _JarvisCardState extends State<JarvisCard>
    with SingleTickerProviderStateMixin {
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();
  late final AnimationController _dotController;

  HomeController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    _dotController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(JarvisCard old) {
    super.didUpdateWidget(old);
    if (old.c.insightThread.length != c.insightThread.length ||
        old.c.insightReplyLoading != c.insightReplyLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendReply() {
    final msg = _replyController.text.trim();
    if (msg.isEmpty || c.insightReplyLoading) return;
    _replyController.clear();
    c.replyToInsight(msg);
  }

  @override
  Widget build(BuildContext context) {
    final hasThread =
        !c.insightLoading && c.insightError == null && c.insightThread.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLoadGauge(),
                _buildNowLine(),
                const SizedBox(height: 12),
                _buildModeChips(),
                const SizedBox(height: 12),
                _buildBody(),
                if (hasThread) ...[
                  const SizedBox(height: 12),
                  _buildReplyInput(),
                  const SizedBox(height: 10),
                  _buildActions(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final mode = c.insightMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
                child: Text(mode.emoji, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mode.label,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    )),
                Text(mode.subtitle,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo')),
              ],
            ),
          ),
          _iconBtn(Icons.refresh_rounded, () => c.loadJarvisInsight(fresh: true)),
        ],
      ),
    );
  }

  // ── Load gauge (local, from task/reminder state) ───────────────────────────

  Widget _buildLoadGauge() {
    final status = c.dayLoadStatus();
    final ratio = c.dayLoadRatio();
    final color = _statusColor(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('עומס היום: ${_statusLabel(status)}',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo')),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 6, color: const Color(0xFF1A2E4A)),
            FractionallySizedBox(
              widthFactor: ratio.clamp(0.0, 1.0),
              child: Container(height: 6, color: color),
            ),
          ]),
        ),
      ],
    );
  }

  /// A thin "now" line for the most pressing task. Kept subtle so it doesn't
  /// compete with the dedicated tasks card.
  Widget _buildNowLine() {
    final task = c.topOpenTask;
    if (task == null) return const SizedBox.shrink();
    final title = task['content'] as String? ?? '';
    if (title.isEmpty) return const SizedBox.shrink();
    final isHigh =
        (task['priority'] ?? '').toString().toLowerCase() == 'high';
    final accent =
        isHigh ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Icon(Icons.play_arrow_rounded, color: accent, size: 14),
        const SizedBox(width: 6),
        Text('עכשיו: ',
            style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'Heebo')),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: JC.textSecondary, fontSize: 12, fontFamily: 'Heebo')),
        ),
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'overloaded':
      case 'heavy':
        return const Color(0xFFEF4444);
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'empty':
        return JC.textMuted;
      default:
        return const Color(0xFF22C55E);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'overloaded':
        return 'עמוס מאוד';
      case 'heavy':
        return 'כבד';
      case 'moderate':
        return 'בינוני';
      case 'light':
        return 'קל';
      case 'empty':
        return 'פנוי';
      default:
        return status;
    }
  }

  // ── Insight thread ──────────────────────────────────────────────────────────

  Widget _buildModeChips() {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: kInsightModes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final mode = kInsightModes[i];
          final selected = c.insightMode.key == mode.key;
          return _chip(
            '${mode.emoji} ${mode.label}',
            selected,
            () => c.setInsightMode(mode),
          );
        },
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF6366F1).withOpacity(0.2)
              : const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF6366F1)
                : JC.border.withOpacity(0.7),
            width: 0.8,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF818CF8)
                  : JC.textSecondary,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }

  Widget _buildBody() {
    if (c.insightLoading && c.insightThread.isEmpty) {
      return const CardSkeleton(lines: 3);
    }
    if (c.insightError != null && c.insightThread.isEmpty) {
      return InlineError(
          message: c.insightError!,
          onRetry: () => c.loadJarvisInsight(fresh: true));
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...c.insightThread.map((msg) => _buildBubble(msg)),
            if (c.insightReplyLoading) _buildTypingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg) {
    final isAssistant = msg['role'] == 'assistant';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isAssistant ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isAssistant
                ? const Color(0xFF6366F1).withOpacity(0.1)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isAssistant ? 14 : 4),
              bottomRight: Radius.circular(isAssistant ? 4 : 14),
            ),
            border: Border.all(
              color: isAssistant
                  ? const Color(0xFF6366F1).withOpacity(0.25)
                  : JC.border.withOpacity(0.5),
              width: 0.7,
            ),
          ),
          child: Text(
            msg['text'] ?? '',
            style: TextStyle(
              color: isAssistant ? const Color(0xFF818CF8) : JC.textPrimary,
              fontSize: 13.5,
              height: 1.55,
              fontFamily: 'Heebo',
              fontStyle: isAssistant ? FontStyle.italic : FontStyle.normal,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.2), width: 0.7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              return AnimatedBuilder(
                animation: _dotController,
                builder: (_, __) {
                  final delay = i * 0.3;
                  final phase = (_dotController.value - delay).clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF6366F1).withOpacity(0.3),
                        const Color(0xFF818CF8),
                        phase,
                      ),
                      shape: BoxShape.circle,
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1929),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border.withOpacity(0.6), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replyController,
              textDirection: TextDirection.rtl,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
              enabled: !c.insightReplyLoading,
              style: TextStyle(
                color: JC.textPrimary,
                fontSize: 13,
                fontFamily: 'Heebo',
              ),
              decoration: InputDecoration(
                hintText: 'ענה לג׳רוויס...',
                hintStyle: TextStyle(
                  color: JC.textMuted,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          GestureDetector(
            onTap: c.insightReplyLoading ? null : _sendReply,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.insightReplyLoading
                    ? const Color(0xFF6366F1).withOpacity(0.3)
                    : const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.send_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final threadSummary = c.insightThread
        .map((m) =>
            '${m['role'] == 'assistant' ? 'ג׳רוויס' : 'אני'}: ${m['text']}')
        .join('\n\n');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _action(Icons.add_task_rounded, 'הפוך למשימה', c.insightToTask),
        _action(Icons.chat_bubble_outline_rounded, 'המשך בצ׳אט', () {
          c.onNavigateToChat?.call(command: threadSummary);
        }),
        _action(Icons.thumb_up_alt_outlined, '', () {
          c.recordInsightFeedback('up');
          c.showSnack('תודה על המשוב 🙏');
        }),
        _action(Icons.thumb_down_alt_outlined, '', () {
          c.recordInsightFeedback('down');
          c.showSnack('תודה, אנסה משהו אחר');
          c.loadJarvisInsight(fresh: true);
        }),
      ],
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            EdgeInsets.symmetric(horizontal: label.isEmpty ? 8 : 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: JC.border.withOpacity(0.7), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: JC.textSecondary),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  color: JC.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600,
                )),
          ],
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF6366F1), size: 14),
      ),
    );
  }
}
