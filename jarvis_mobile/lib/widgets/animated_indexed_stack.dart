import 'package:flutter/material.dart';

/// Like [IndexedStack] but cross-fades + slides the active child when [index]
/// changes. Keeps all children alive (offstage) so screen state is preserved.
class AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;
  final bool enabled;

  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 240),
    this.enabled = true,
  });

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)..value = 1.0;
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void didUpdateWidget(covariant AnimatedIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && widget.enabled) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return IndexedStack(index: widget.index, children: widget.children);
    }
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(_fade),
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
