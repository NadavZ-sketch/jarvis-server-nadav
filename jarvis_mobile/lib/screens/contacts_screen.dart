import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';

class ContactsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const ContactsScreen(
      {super.key, required this.settings, this.onCountUpdate});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    _loadCache();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered => _searchQuery.isEmpty
      ? _items
      : _items.where((i) {
          final name = (i['name']?.toString() ?? '').toLowerCase();
          final phone = (i['phone']?.toString() ?? '').toLowerCase();
          final email = (i['email']?.toString() ?? '').toLowerCase();
          return name.contains(_searchQuery) ||
              phone.contains(_searchQuery) ||
              email.contains(_searchQuery);
        }).toList();

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('contacts');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
      widget.onCountUpdate?.call(cached.length);
    }
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService(widget.settings).getContacts();
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        widget.onCountUpdate?.call(items.length);
        CacheService.saveList('contacts', items);
      }
    } catch (e) {
      if (mounted && _items.isEmpty) {
        setState(() {
          _error = ApiService.friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));
    widget.onCountUpdate?.call(_items.length);

    showDeleteSnackbar(
      context,
      message: '${item['name'] ?? 'איש הקשר'} הוסר',
      onUndo: () {
        setState(() =>
            _items.insert(savedIndex.clamp(0, _items.length), item));
        widget.onCountUpdate?.call(_items.length);
      },
      onClosed: (wasUndone) {
        if (!wasUndone) {
          ApiService(widget.settings).deleteContact(id).catchError((_) {});
        }
      },
    );
  }

  void _showActions(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final phone = item['phone']?.toString() ??
        item['phone_number']?.toString() ??
        '';
    final email = item['email']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  name,
                  style: const TextStyle(
                      color: JC.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo'),
                  textDirection: TextDirection.rtl,
                ),
              ),
              const Divider(color: JC.border, height: 1),
              if (phone.isNotEmpty) ...[
                _ActionTile(
                  icon: Icons.call_rounded,
                  label: 'התקשר: $phone',
                  color: const Color(0xFF34D399),
                  onTap: () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse('tel:$phone'));
                  },
                ),
                _ActionTile(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF4ADE80),
                  onTap: () {
                    Navigator.pop(context);
                    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
                    launchUrl(
                        Uri.parse('https://wa.me/$clean'),
                        mode: LaunchMode.externalApplication);
                  },
                ),
              ],
              if (email.isNotEmpty)
                _ActionTile(
                  icon: Icons.email_outlined,
                  label: 'מייל: $email',
                  color: JC.blue400,
                  onTap: () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse('mailto:$email'));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('אנשי קשר',
            style: TextStyle(
                color: JC.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Heebo'),
            textDirection: TextDirection.rtl),
        centerTitle: true,
      ),
      body: _loading
          ? const LoadingSkeleton(itemCount: 6)
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'שגיאת טעינה',
                  subtitle: _error!)
              : Column(
                  children: [
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: JarvisSearchBar(
                            controller: _searchCtrl,
                            hint: 'חיפוש באנשי הקשר...'),
                      ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.contacts_outlined,
                              title: _searchQuery.isEmpty
                                  ? 'אין אנשי קשר'
                                  : 'לא נמצאו תוצאות',
                              subtitle: _searchQuery.isEmpty
                                  ? 'כשתוסיף אנשי קשר, הם יופיעו כאן'
                                  : '')
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surfaceAlt,
                              onRefresh: _fetch,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 32),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final item = _filtered[i];
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
                                      background: _conDismissBg(),
                                      onDismissed: (_) => _onDismissed(item),
                                      child: GestureDetector(
                                        onTap: () => _showActions(item),
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 10),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 12),
                                          decoration: BoxDecoration(
                                            color: JC.surfaceAlt,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                                color: JC.border, width: 0.8),
                                          ),
                                          child: Row(
                                            textDirection: TextDirection.rtl,
                                            children: [
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
                                                      JC.blue500
                                                    ],
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    _initials(name),
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFamily: 'Heebo'),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  children: [
                                                    Text(name,
                                                        textDirection:
                                                            TextDirection.rtl,
                                                        style: const TextStyle(
                                                            color:
                                                                JC.textPrimary,
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontFamily:
                                                                'Heebo')),
                                                    if (subtitle.isNotEmpty)
                                                      Text(subtitle,
                                                          textDirection:
                                                              TextDirection.rtl,
                                                          style: const TextStyle(
                                                              color: JC.textMuted,
                                                              fontSize: 12,
                                                              fontFamily:
                                                                  'Heebo')),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                  Icons
                                                      .chevron_left_rounded,
                                                  color: JC.textMuted,
                                                  size: 18),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

Widget _conDismissBg() => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        textDirection: TextDirection.rtl,
        style: const TextStyle(
            color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 14),
      ),
      onTap: onTap,
    );
  }
}

