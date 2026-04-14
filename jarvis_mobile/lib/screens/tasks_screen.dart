import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';

class TasksScreen extends StatefulWidget {
  final AppSettings settings;

  const TasksScreen({super.key, required this.settings});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
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
      final items = await ApiService(widget.settings).getTasks();
      if (mounted) setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _timeAgo(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'עכשיו';
      if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
      if (diff.inHours < 24) return 'לפני ${diff.inHours} שע׳';
      return 'לפני ${diff.inDays} ימים';
    } catch (_) {
      return '';
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));

    bool undone = false;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: const Text(
              'המשימה הוסרה',
              style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary),
            ),
            backgroundColor: JC.surfaceAlt,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'בטל',
              textColor: JC.blue400,
              onPressed: () {
                undone = true;
                setState(() {
                  final at = savedIndex.clamp(0, _items.length);
                  _items.insert(at, item);
                });
              },
            ),
          ),
        )
        .closed
        .then((_) {
          if (!undone) {
            ApiService(widget.settings).deleteTask(id).catchError((_) {});
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'משימות',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
          ),
          textDirection: TextDirection.rtl,
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JC.blue400))
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'שגיאת טעינה',
                  subtitle: _error!,
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'אין משימות',
                      subtitle: 'כשתוסיף משימות, הן יופיעו כאן',
                    )
                  : RefreshIndicator(
                      color: JC.blue400,
                      backgroundColor: JC.surfaceAlt,
                      onRefresh: _fetch,
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final item = _items[i];
                          return AnimatedListItem(
                            index: i,
                            child: Dismissible(
                              key: ValueKey(item['id']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: JC.cancelRed.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: JC.cancelRed,
                                ),
                              ),
                              onDismissed: (_) => _onDismissed(item),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: JC.surfaceAlt,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: JC.border, width: 0.8),
                                ),
                                child: Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    const Icon(
                                      Icons.radio_button_unchecked_rounded,
                                      color: JC.blue500,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item['content']?.toString() ?? '',
                                        textDirection: TextDirection.rtl,
                                        style: const TextStyle(
                                          color: JC.textPrimary,
                                          fontSize: 15,
                                          fontFamily: 'Heebo',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _timeAgo(item['created_at']),
                                      style: const TextStyle(
                                        color: JC.textMuted,
                                        fontSize: 11,
                                        fontFamily: 'Heebo',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
