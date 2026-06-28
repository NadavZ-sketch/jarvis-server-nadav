import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;

class TabAgents extends StatefulWidget {
  final AppSettings settings;
  const TabAgents({super.key, required this.settings});

  @override
  State<TabAgents> createState() => _TabAgentsState();
}

class _TabAgentsState extends State<TabAgents>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Center(
      child: Text(
        'בקרוב',
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 18,
          color: JC.textMuted,
        ),
      ),
    );
  }
}
