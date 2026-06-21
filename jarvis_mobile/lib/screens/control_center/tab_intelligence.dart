import 'package:flutter/material.dart';
import '../../app_settings.dart';

class TabIntelligence extends StatefulWidget {
  final AppSettings settings;
  const TabIntelligence({super.key, required this.settings});

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
