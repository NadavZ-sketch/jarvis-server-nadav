import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';

class ContactsScreen extends StatefulWidget {
  final AppSettings settings;

  const ContactsScreen({super.key, required this.settings});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
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
      final items = await ApiService(widget.settings).getContacts();
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

  void _onDismissed(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));

    bool undone = false;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text(
              '${item['name'] ?? 'איש הקשר'} הוסר',
              style:
                  const TextStyle(fontFamily: 'Heebo', color: JC.textPrimary),
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
            ApiService(widget.settings)
                .deleteContact(id)
                .catchError((_) {});
          }
        });
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'אנשי קשר',
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
                      icon: Icons.contacts_outlined,
                      title: 'אין אנשי קשר',
                      subtitle: 'כשתוסיף אנשי קשר, הם יופיעו כאן',
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
                          final name =
                              item['name']?.toString() ?? 'ללא שם';
                          final phone = item['phone']?.toString() ??
                              item['phone_number']?.toString() ??
                              '';
                          final email =
                              item['email']?.toString() ?? '';
                          final subtitle = phone.isNotEmpty
                              ? phone
                              : email.isNotEmpty
                                  ? email
                                  : '';

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
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: JC.surfaceAlt,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: JC.border, width: 0.8),
                                ),
                                child: Row(
                                  textDirection: TextDirection.rtl,
                                  children: [
                                    // Avatar
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            JC.blue400,
                                            JC.blue500,
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _initials(name),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Heebo',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            name,
                                            textDirection:
                                                TextDirection.rtl,
                                            style: const TextStyle(
                                              color: JC.textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              fontFamily: 'Heebo',
                                            ),
                                          ),
                                          if (subtitle.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              subtitle,
                                              textDirection:
                                                  TextDirection.rtl,
                                              style: const TextStyle(
                                                color: JC.textMuted,
                                                fontSize: 12,
                                                fontFamily: 'Heebo',
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
                        },
                      ),
                    ),
    );
  }
}
