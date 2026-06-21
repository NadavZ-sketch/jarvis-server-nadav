import 'package:flutter/material.dart';
import '../../app_settings.dart';

class TabTests extends StatefulWidget {
  final AppSettings settings;
  const TabTests({super.key, required this.settings});

  @override
  State<TabTests> createState() => _TabTestsState();
}

class _TabTestsState extends State<TabTests>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(child: Text('בדיקות — בקרוב'));
  }
}
