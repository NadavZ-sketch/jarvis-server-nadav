import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;
import 'tab_overview.dart';
import 'tab_brain.dart';
import 'tab_agents.dart';
import 'tab_improve.dart';

enum CcTab { overview, brain, agents, improve }

class ControlCenterShell extends StatefulWidget {
  final bool isAdmin;
  final AppSettings settings;
  const ControlCenterShell({super.key, this.isAdmin = false, required this.settings});

  @override
  State<ControlCenterShell> createState() => _ControlCenterShellState();
}

class _ControlCenterShellState extends State<ControlCenterShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<CcTab> get _visibleTabs => widget.isAdmin
      ? CcTab.values.toList()
      : [CcTab.overview, CcTab.improve];

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
        CcTab.brain    => 'מוח',
        CcTab.agents   => 'סוכנים',
        CcTab.improve  => 'שיפור',
      };

  Widget _tabBody(CcTab t) => switch (t) {
        CcTab.overview => TabOverview(settings: widget.settings),
        CcTab.brain    => TabBrain(settings: widget.settings),
        CcTab.agents   => TabAgents(settings: widget.settings),
        CcTab.improve  => TabImprove(settings: widget.settings),
      };

  Future<void> _openVisualControlCenter() async {
    final url = Uri.parse('${widget.settings.serverUrl}/progress-map/brain');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TabBar(
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
            ),
            IconButton(
              icon: Icon(Icons.open_in_new, size: 18, color: JC.blue400),
              tooltip: 'פתח מרכז שליטה ויזואלי בווב',
              onPressed: _openVisualControlCenter,
            ),
          ],
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
