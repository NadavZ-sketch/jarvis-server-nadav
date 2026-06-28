import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;

class TabBrain extends StatefulWidget {
  final AppSettings settings;
  const TabBrain({super.key, required this.settings});

  @override
  State<TabBrain> createState() => _TabBrainState();
}

class _TabBrainState extends State<TabBrain>
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
