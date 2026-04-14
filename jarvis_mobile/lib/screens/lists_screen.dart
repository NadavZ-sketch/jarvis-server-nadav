import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import 'shopping_screen.dart';
import 'notes_screen.dart';

class ListsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onShoppingCountUpdate;
  final ValueChanged<int>? onNotesCountUpdate;

  const ListsScreen({
    super.key,
    required this.settings,
    this.onShoppingCountUpdate,
    this.onNotesCountUpdate,
  });

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'רשימות',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
          ),
          textDirection: TextDirection.rtl,
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: JC.blue400,
          unselectedLabelColor: JC.textMuted,
          indicatorColor: JC.blue400,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: JC.border,
          labelStyle: const TextStyle(
              fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontFamily: 'Heebo', fontSize: 14),
          tabs: const [
            Tab(text: 'קניות 🛒'),
            Tab(text: 'הערות 📝'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ShoppingScreen(
            settings: widget.settings,
            onCountUpdate: widget.onShoppingCountUpdate,
          ),
          NotesScreen(
            settings: widget.settings,
            onCountUpdate: widget.onNotesCountUpdate,
          ),
        ],
      ),
    );
  }
}
