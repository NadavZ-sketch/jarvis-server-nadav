import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import 'home/home_controller.dart';
import 'home/home_card_registry.dart';
import 'home/home_helpers.dart';

/// Smart Day Manager home screen. A thin shell: it owns a [HomeController] and
/// renders the cards declared in [kHomeCards] in the user's saved order. Cards
/// can be reordered/hidden in layout-edit mode (persisted to [AppSettings]).
class SmartProductivityPreviewScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function({String? command})? onNavigateToChat;

  const SmartProductivityPreviewScreen({
    super.key,
    required this.settings,
    this.onNavigateToChat,
  });

  @override
  State<SmartProductivityPreviewScreen> createState() =>
      _SmartProductivityPreviewScreenState();
}

class _SmartProductivityPreviewScreenState
    extends State<SmartProductivityPreviewScreen> {
  late final HomeController _c;
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _c = HomeController(
      settings: widget.settings,
      onNavigateToChat: widget.onNavigateToChat,
    )..start();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // ── Layout editing ──────────────────────────────────────────────────────────

  void _onReorder(int oldIndex, int newIndex) {
    // Operates on the non-pinned cards only.
    final movable =
        orderedCards(widget.settings).where((c) => c.id != kPinnedCardId).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = movable.removeAt(oldIndex);
    movable.insert(newIndex, moved);
    setState(() {
      widget.settings.homeCardOrder = [kPinnedCardId, ...movable.map((c) => c.id)];
    });
    widget.settings.save();
  }

  void _toggleHidden(String id, bool hidden) {
    setState(() {
      if (hidden) {
        widget.settings.homeCardsHidden.add(id);
      } else {
        widget.settings.homeCardsHidden.remove(id);
      }
    });
    widget.settings.save();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        body: SafeArea(
          top: true,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return Stack(children: [
                Column(children: [
                  _header(),
                  Expanded(
                    child: _c.loading
                        ? Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: JC.blue400))
                        : _c.error != null
                            ? ErrorView(message: _c.error!, onRetry: _c.refresh)
                            : RefreshIndicator(
                                color: JC.blue400,
                                backgroundColor: JC.surface,
                                onRefresh: _c.refresh,
                                child: _editMode
                                    ? _editList(bottomPad)
                                    : _cardList(bottomPad),
                              ),
                  ),
                ]),
                if (_c.snack != null)
                  Positioned(
                    bottom: 60,
                    left: 16,
                    right: 16,
                    child: SnackOverlay(_c.snack!),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        _circleButton(Icons.menu_rounded,
            () => Scaffold.of(context).openEndDrawer()),
        const SizedBox(width: 10),
        _circleButton(
          _editMode ? Icons.check_rounded : Icons.tune_rounded,
          () => setState(() => _editMode = !_editMode),
          active: _editMode,
        ),
        const SizedBox(width: 10),
        _circleButton(Icons.refresh_rounded, _c.refresh),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('שלום, ${widget.settings.userName}',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Heebo',
                )),
            Text(_editMode ? 'עריכת פריסה' : 'מנהל היום החכם',
                style: TextStyle(
                    color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
          ],
        ),
      ]),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? JC.blue500.withOpacity(0.22)
              : JC.surface.withOpacity(0.85),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? JC.blue400.withOpacity(0.5)
                : JC.border.withOpacity(0.5),
            width: 0.8,
          ),
          boxShadow: [
            if (active)
              BoxShadow(
                  color: JC.blue500.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 2)),
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon,
            color: active ? JC.blue400 : JC.textSecondary, size: 18),
      ),
    );
  }

  Widget _cardList(double bottomPad) {
    final cards = visibleCards(widget.settings);
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 16),
      itemCount: cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) => cards[i].build(context, _c),
    );
  }

  Widget _editList(double bottomPad) {
    final movable =
        orderedCards(widget.settings).where((c) => c.id != kPinnedCardId).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JC.border.withOpacity(0.7), width: 0.8),
          ),
          child: Row(children: [
            Icon(Icons.push_pin_rounded, color: JC.textMuted, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text('ברכה (קבוע)',
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: _onReorder,
          children: [
            for (int i = 0; i < movable.length; i++)
              _editRow(movable[i], i),
          ],
        ),
      ],
    );
  }

  Widget _editRow(HomeCardSpec spec, int index) {
    final hidden = widget.settings.homeCardsHidden.contains(spec.id);
    return Container(
      key: ValueKey('edit-${spec.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border.withOpacity(0.7), width: 0.8),
      ),
      child: Row(children: [
        ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_indicator_rounded, color: JC.textMuted, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(spec.titleHe,
              style: TextStyle(
                color: hidden ? JC.textMuted : JC.textPrimary,
                fontSize: 13,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600,
              )),
        ),
        Switch(
          value: !hidden,
          activeColor: JC.blue400,
          onChanged: (visible) => _toggleHidden(spec.id, !visible),
        ),
      ]),
    );
  }
}
