import 'package:flutter/material.dart';

class AnimatedListItem extends StatelessWidget {
  final int index;
  final Widget child;

  const AnimatedListItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final delay = (260 + (index * 50).clamp(0, 300)).toInt();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: delay),
      curve: Curves.easeOut,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
