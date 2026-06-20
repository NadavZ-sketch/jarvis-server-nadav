import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import 'tab_overview.dart';
import 'tab_intelligence.dart';
import 'tab_dev_workshop.dart';
import 'tab_tests.dart';

enum CcTab { overview, intelligence, devWorkshop, tests }

class ControlCenterShell extends StatefulWidget {
  final bool isAdmin;
  const ControlCenterShell({super.key, this.isAdmin = false});

  @override
  State<ControlCenterShell> createState() => _ControlCenterShellState();
}

class _ControlCenterShellState extends State<ControlCenterShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<CcTab> get _visibleTabs => widget.isAdmin
      ? CcTab.values.toList()
      : [CcTab.overview, CcTab.tests];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _visibleTabs.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant ControlCenterShell old) {
    super.didUpdateWidget(old);
    if (_tabController.length != _visibleTabs.length) {
      final keepIdx = _tabController.index.clamp(0, _visibleTabs.length - 1);
      _tabController.dispose();
      _tabController = TabController(
        length: _visibleTabs.length,
        vsync: this,
        initialIndex: keepIdx,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _tabLabel(CcTab t) => switch (t) {
        CcTab.overview => 'סקירה',
        CcTab.intelligence => 'אינטליגנציה',
        CcTab.devWorkshop => 'סדנת פיתוח',
        CcTab.tests => 'בדיקות',
      };

  Widget _tabBody(CcTab t) => switch (t) {
        CcTab.overview => const TabOverview(),
        CcTab.intelligence => const TabIntelligence(),
        CcTab.devWorkshop => const TabDevWorkshop(),
        CcTab.tests => const TabTests(),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: JC.amber400,
          unselectedLabelColor: JC.textMuted,
          labelStyle: const TextStyle(
              fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle:
              const TextStyle(fontFamily: 'Heebo', fontSize: 11),
          tabs: _visibleTabs.map((t) => Tab(text: _tabLabel(t))).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _visibleTabs.map(_tabBody).toList(),
          ),
        ),
      ],
    );
  }
}
