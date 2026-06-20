import 'package:flutter/material.dart';

class TabTests extends StatefulWidget {
  const TabTests({super.key});

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
