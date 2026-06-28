import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;

class TabImprove extends StatefulWidget {
  final AppSettings settings;
  const TabImprove({super.key, required this.settings});

  @override
  State<TabImprove> createState() => _TabImproveState();
}

class _TabImproveState extends State<TabImprove>
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
