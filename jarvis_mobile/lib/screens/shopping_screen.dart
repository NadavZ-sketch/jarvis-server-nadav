import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';

class ShoppingScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const ShoppingScreen({super.key, required this.settings, this.onCountUpdate});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _showDone = false;
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

  void _updateCount() {
    final active = _items.where((i) => i['done'] != true).length;
    widget.onCountUpdate?.call(active);
  }

  /// Active items first (by created_at), then done items.
  List<Map<String, dynamic>> get _sorted {
    final active = _items.where((i) => i['done'] != true).toList();
    final done   = _items.where((i) => i['done'] == true).toList();
    return _showDone ? [...active, ...done] : active;
  }

  List<Map<String, dynamic>> get _filtered {
    final src = _sorted;
    if (_searchQuery.isEmpty) return src;
    return src
        .where((i) =>
            (i['item']?.toString() ?? '').toLowerCase().contains(_searchQuery))
        .toList();
  }

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('shopping');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
      _updateCount();
    }
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService(widget.settings).getShopping();
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        _updateCount();
        CacheService.saveList('shopping', items);
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

  Future<void> _toggleDone(Map<String, dynamic> item) async {
    HapticFeedback.selectionClick();
    final id      = item['id'].toString();
    final newDone = item['done'] != true;
    setState(() => item['done'] = newDone);
    _updateCount();
    try {
      await ApiService(widget.settings)
          .updateShoppingItem(id, done: newDone);
      CacheService.saveList('shopping', _items);
    } catch (_) {
      // revert on error
      setState(() => item['done'] = !newDone);
      _updateCount();
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));
    _updateCount();

    showDeleteSnackbar(
      context,
      message: '"${item['item']}" הוסר',
      onUndo: () {
        setState(() =>
            _items.insert(savedIndex.clamp(0, _items.length), item));
        _updateCount();
      },
      onClosed: (wasUndone) {
        if (!wasUndone) {
          ApiService(widget.settings)
              .deleteShoppingItem(id)
              .catchError((_) {});
        }
      },
    );
  }

  Future<void> _showAddSheet() async {
    final ctrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('הוסף לרשימת הקניות',
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Heebo'),
                textDirection: TextDirection.rtl),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              textDirection: TextDirection.rtl,
              autofocus: true,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: 'חלב, לחם, ביצים...',
                hintStyle:
                    const TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                filled: true,
                fillColor: JC.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JC.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JC.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JC.blue500)),
              ),
              onSubmitted: (_) => _submitAdd(ctrl.text, ctx),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: JC.blue500,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () => _submitAdd(ctrl.text, ctx),
                child: const Text('הוסף',
                    style: TextStyle(fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAdd(String text, BuildContext sheetCtx) async {
    final val = text.trim();
    if (val.isEmpty) return;
    Navigator.pop(sheetCtx);
    try {
      final res = await ApiService(widget.settings).addShoppingItem(val);
      final newItem = res['item'] as Map<String, dynamic>? ??
          {'id': DateTime.now().toString(), 'item': val, 'done': false};
      setState(() => _items.insert(0, newItem));
      _updateCount();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('שגיאה בהוספה',
                style: TextStyle(fontFamily: 'Heebo'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _items.where((i) => i['done'] == true).length;

    return Scaffold(
      backgroundColor: JC.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
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
                            hint: 'חיפוש ברשימת הקניות...'),
                      ),
                    if (doneCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _showDone = !_showDone),
                            child: Text(
                              _showDone
                                  ? 'הסתר נקנו'
                                  : 'הצג נקנו ($doneCount)',
                              style: const TextStyle(
                                  color: JC.blue400,
                                  fontFamily: 'Heebo',
                                  fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.shopping_cart_outlined,
                              title: _searchQuery.isEmpty
                                  ? 'רשימת הקניות ריקה'
                                  : 'לא נמצאו פריטים',
                              subtitle: _searchQuery.isEmpty
                                  ? 'לחץ + להוספת פריט'
                                  : '',
                            )
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surfaceAlt,
                              onRefresh: _fetch,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final item = _filtered[i];
                                  final isDone = item['done'] == true;
                                  return AnimatedListItem(
                                    index: i,
                                    child: Dismissible(
                                      key: ValueKey(item['id']),
                                      direction: DismissDirection.endToStart,
                                      background: _deleteBg(),
                                      onDismissed: (_) => _onDismissed(item),
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: isDone
                                              ? JC.surface.withOpacity(0.6)
                                              : JC.surfaceAlt,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                              color: JC.border, width: 0.8),
                                        ),
                                        child: Row(
                                          textDirection: TextDirection.rtl,
                                          children: [
                                            GestureDetector(
                                              onTap: () => _toggleDone(item),
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                    milliseconds: 200),
                                                child: Icon(
                                                  isDone
                                                      ? Icons
                                                          .check_circle_rounded
                                                      : Icons
                                                          .radio_button_unchecked_rounded,
                                                  key: ValueKey(isDone),
                                                  color: isDone
                                                      ? JC.blue400
                                                          .withOpacity(0.6)
                                                      : JC.blue500,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                item['item']?.toString() ?? '',
                                                textDirection:
                                                    TextDirection.rtl,
                                                style: TextStyle(
                                                  color: isDone
                                                      ? JC.textMuted
                                                      : JC.textPrimary,
                                                  fontSize: 15,
                                                  fontFamily: 'Heebo',
                                                  decoration: isDone
                                                      ? TextDecoration
                                                          .lineThrough
                                                      : null,
                                                ),
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
                    ),
                  ],
                ),
    );
  }
}

Widget _deleteBg() => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );
