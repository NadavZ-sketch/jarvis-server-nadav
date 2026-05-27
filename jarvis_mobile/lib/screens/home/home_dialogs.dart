import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../app_settings.dart';
import '../../services/api_service.dart';
import 'home_controller.dart';

void showAddTaskDialog(BuildContext context, HomeController c) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF0B1422),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('משימה חדשה',
            style: TextStyle(
                color: JC.textPrimary,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
          decoration: _inputDecoration('תאר את המשימה...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ביטול',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
          ),
          ElevatedButton(
            style: _primaryBtn(JC.blue500),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              c.addTask(text);
            },
            child: const Text('הוסף',
                style:
                    TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

void showAddReminderDialog(BuildContext context, HomeController c) {
  final textController = TextEditingController();
  DateTime reminderTime = DateTime.now()
      .add(const Duration(hours: 1))
      .copyWith(second: 0, microsecond: 0);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDState) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0B1422),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('תזכורת חדשה',
              style: TextStyle(
                  color: JC.textPrimary,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: _inputDecoration('תאר את התזכורת...'),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: reminderTime,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null || !ctx.mounted) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(reminderTime),
                  );
                  if (time == null) return;
                  setDState(() {
                    reminderTime = DateTime(date.year, date.month, date.day,
                        time.hour, time.minute);
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1929),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: JC.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.schedule_rounded, color: JC.blue400, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${reminderTime.day}/${reminderTime.month}  '
                      '${reminderTime.hour.toString().padLeft(2, '0')}:'
                      '${reminderTime.minute.toString().padLeft(2, '0')}',
                      style:
                          TextStyle(color: JC.textSecondary, fontFamily: 'Heebo'),
                    ),
                    const Spacer(),
                    Text('שנה',
                        style: TextStyle(
                            color: JC.blue400,
                            fontSize: 12,
                            fontFamily: 'Heebo')),
                  ]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('ביטול',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
            ),
            ElevatedButton(
              style: _primaryBtn(const Color(0xFF22C55E)),
              onPressed: () {
                final text = textController.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                c.addReminder(text, reminderTime);
              },
              child: const Text('הוסף',
                  style: TextStyle(
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}

void showBuildDaySheet(BuildContext context, HomeController c) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0B1422),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BuildDaySheet(api: c.api, settings: c.settings),
  );
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: JC.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: JC.blue500),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

ButtonStyle _primaryBtn(Color bg) => ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

class _BuildDaySheet extends StatefulWidget {
  final ApiService api;
  final AppSettings settings;
  const _BuildDaySheet({required this.api, required this.settings});

  @override
  State<_BuildDaySheet> createState() => _BuildDaySheetState();
}

class _BuildDaySheetState extends State<_BuildDaySheet> {
  bool _loading = true;
  String _result = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.askJarvis(
        'בנה לי תוכנית יום מהמשימות הפתוחות שלי, בעברית, עם סדר עדיפויות ברור',
        widget.settings,
      );
      if (mounted) {
        setState(() {
          _result = r['answer'] as String? ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B1422),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2E4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(
                  children: [
                    const Text('🗓', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('תוכנית היום',
                          style: TextStyle(
                            color: JC.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Heebo',
                          )),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: JC.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(color: JC.border),
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                color: JC.blue400, strokeWidth: 2),
                            const SizedBox(height: 14),
                            Text('ג׳רוויס בונה את היום שלך...',
                                style: TextStyle(
                                    color: JC.textMuted,
                                    fontFamily: 'Heebo',
                                    fontSize: 14)),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!,
                                      style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontFamily: 'Heebo')),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _fetch,
                                    child: Text('נסה שוב',
                                        style: TextStyle(
                                            color: JC.blue400,
                                            fontFamily: 'Heebo')),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            child: Text(_result,
                                style: TextStyle(
                                  color: JC.textSecondary,
                                  fontSize: 14,
                                  height: 1.65,
                                  fontFamily: 'Heebo',
                                )),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
