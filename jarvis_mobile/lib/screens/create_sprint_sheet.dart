import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';

class CreateSprintSheet extends StatefulWidget {
  final String projectId;
  final AppSettings settings;
  final VoidCallback? onCreated;
  final ScrollController? scrollController;
  const CreateSprintSheet({
    super.key,
    required this.projectId,
    required this.settings,
    this.onCreated,
    this.scrollController,
  });
  @override
  State<CreateSprintSheet> createState() => _CreateSprintSheetState();
}

class _CreateSprintSheetState extends State<CreateSprintSheet> {
  final _nameCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _capacity = 40;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      locale: const Locale('he'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: JC.blue500,
            onPrimary: Colors.white,
            surface: JC.surface,
            onSurface: JC.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontFamily: 'Heebo'),
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: JC.cancelRed,
      ),
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _startDate == null ||
        _endDate == null) {
      _showError('נא למלא שם, תאריך התחלה ותאריך סיום');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      _showError('תאריך הסיום חייב להיות אחרי תאריך ההתחלה');
      return;
    }
    setState(() => _saving = true);
    try {
      await ApiService(widget.settings).createSprint(widget.projectId, {
        'name': _nameCtrl.text.trim(),
        'goal': _goalCtrl.text.trim(),
        'start_date': _startDate!.toIso8601String().substring(0, 10),
        'end_date': _endDate!.toIso8601String().substring(0, 10),
        'capacity_points': _capacity,
      });
      if (!mounted) return;
      widget.onCreated?.call();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('יצירת הספרינט נכשלה');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JC.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: JC.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'ספרינט חדש',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: JC.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary),
              decoration: InputDecoration(
                hintText: 'שם הספרינט',
                hintStyle: TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
                filled: true,
                fillColor: JC.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.blue500, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _goalCtrl,
              textDirection: TextDirection.rtl,
              maxLines: 2,
              style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary),
              decoration: InputDecoration(
                hintText: 'מטרת הספרינט (אופציונלי)',
                hintStyle: TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
                filled: true,
                fillColor: JC.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: JC.blue500, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'תאריך התחלה',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JC.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _pickDate(isStart: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: JC.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: JC.border),
                          ),
                          child: Text(
                            _startDate == null
                                ? 'בחר תאריך'
                                : _formatDate(_startDate!),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFamily: 'Heebo',
                              fontSize: 13,
                              color: _startDate == null
                                  ? JC.textMuted
                                  : JC.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'תאריך סיום',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JC.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _pickDate(isStart: false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: JC.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: JC.border),
                          ),
                          child: Text(
                            _endDate == null
                                ? 'בחר תאריך'
                                : _formatDate(_endDate!),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFamily: 'Heebo',
                              fontSize: 13,
                              color: _endDate == null
                                  ? JC.textMuted
                                  : JC.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'קיבולת: $_capacity נ"ס',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: JC.textPrimary,
              ),
            ),
            Slider(
              value: _capacity.toDouble(),
              min: 0,
              max: 200,
              divisions: 20,
              activeColor: JC.blue500,
              inactiveColor: JC.border,
              onChanged: (v) => setState(() => _capacity = v.round()),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'צור ספרינט',
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: Text(
                'ביטול',
                style: TextStyle(
                    fontFamily: 'Heebo', color: JC.textMuted, fontSize: 14),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
