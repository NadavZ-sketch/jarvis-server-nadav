import 'package:flutter/material.dart';

class TabDevWorkshop extends StatefulWidget {
  const TabDevWorkshop({super.key});

  @override
  State<TabDevWorkshop> createState() => _TabDevWorkshopState();
}

class _TabDevWorkshopState extends State<TabDevWorkshop>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Center(child: Text('סדנת פיתוח — בקרוב'));
  }
}
