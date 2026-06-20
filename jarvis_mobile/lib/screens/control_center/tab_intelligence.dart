import 'package:flutter/material.dart';

class TabIntelligence extends StatefulWidget {
  const TabIntelligence({super.key});

  @override
  State<TabIntelligence> createState() => _TabIntelligenceState();
}

class _TabIntelligenceState extends State<TabIntelligence>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(child: Text('אינטליגנציה — בקרוב'));
  }
}
