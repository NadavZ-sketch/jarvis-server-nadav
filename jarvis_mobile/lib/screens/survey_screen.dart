import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../app_settings.dart';

class SurveyModal extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  final AppSettings settings;
  final VoidCallback onDismiss;

  const SurveyModal({
    super.key,
    required this.questions,
    required this.settings,
    required this.onDismiss,
  });

  @override
  State<SurveyModal> createState() => _SurveyModalState();
}

class _SurveyModalState extends State<SurveyModal> {
  late Map<String, String> responses;
  int currentPage = 0;
  bool isSubmitting = false;
  String? summary;

  @override
  void initState() {
    super.initState();
    responses = {for (var q in widget.questions) q['id']: ''};
  }

  Future<void> _submitSurvey() async {
    if (responses.values.any((v) => v.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אנא ענה על כל השאלות')),
      );
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final url = Uri.parse('${widget.settings.serverUrl}/survey-submit');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'responses': responses,
          'userName': widget.settings.userName,
        }),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          summary = data['summary'];
          isSubmitting = false;
        });
      } else {
        setState(() => isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('שגיאה בשמירת הסקר')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (summary != null) {
      return _buildSummaryView();
    }

    final question = widget.questions[currentPage];
    final progress = (currentPage + 1) / widget.questions.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'סקר חוויית משתמש',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: JC.textPrimary,
                  fontFamily: 'Heebo',
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: JC.border.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(JC.blue400),
                minHeight: 4,
              ),
              const SizedBox(height: 8),
              Text(
                'שאלה ${currentPage + 1} מתוך ${widget.questions.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: JC.textMuted,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ),
        ),

        // Question
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question['question'],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: JC.textPrimary,
                  fontFamily: 'Heebo',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),

              // Options
              Column(
                children: (question['options'] as List<dynamic>?)
                        ?.asMap()
                        .entries
                        .map<Widget>((entry) {
                      final idx = entry.key;
                      final option = entry.value;
                      final isSelected = responses[question['id']] == option;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                responses[question['id']] = option;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? JC.blue500.withValues(alpha: 0.15)
                                    : JC.border.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? JC.blue400 : JC.border,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? JC.blue400
                                            : JC.textMuted,
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? Padding(
                                            padding: EdgeInsets.all(4),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: JC.blue400,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      option,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: isSelected
                                            ? JC.blue400
                                            : JC.textPrimary,
                                        fontFamily: 'Heebo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList() ??
                    [],
              ),
            ],
          ),
        ),

        // Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (currentPage > 0)
                TextButton(
                  onPressed: () => setState(() => currentPage--),
                  child: Text(
                    'חזור',
                    style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo'),
                  ),
                ),
              Expanded(child: Container()),
              if (currentPage < widget.questions.length - 1)
                ElevatedButton(
                  onPressed: responses[question['id']]!.isNotEmpty
                      ? () => setState(() => currentPage++)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.blue500,
                    disabledBackgroundColor: JC.blue500.withValues(alpha: 0.3),
                  ),
                  child: const Text(
                    'הבא',
                    style: TextStyle(fontFamily: 'Heebo', color: Colors.white),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: isSubmitting ? null : _submitSurvey,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.blue500,
                    disabledBackgroundColor: JC.blue500.withValues(alpha: 0.3),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'שלח',
                          style: TextStyle(
                              fontFamily: 'Heebo', color: Colors.white),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✅ תודה! המשוב נקלט',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: JC.blue400,
                  fontFamily: 'Heebo',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'אקח את זה בחשבון כדי להשתפר עבורך.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: JC.textMuted,
                  fontFamily: 'Heebo',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                summary ?? '',
                style: TextStyle(
                  fontSize: 15,
                  color: JC.textPrimary,
                  fontFamily: 'Heebo',
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDismiss();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.blue500,
                  ),
                  child: const Text(
                    'סיום',
                    style: TextStyle(fontFamily: 'Heebo', color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
