import 'package:flutter/material.dart';
import '../../app_settings.dart';

class TabDevWorkshop extends StatefulWidget {
  final AppSettings settings;
  const TabDevWorkshop({super.key, required this.settings});

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
