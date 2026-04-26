import 'package:flutter/material.dart';
import '../main.dart' show JC;

/// Animated placeholder rows that appear during the first network fetch.
/// Replaces a bare `CircularProgressIndicator` so the layout doesn't jump
/// once data arrives.
class LoadingSkeleton extends StatefulWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  const LoadingSkeleton({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 64,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: widget.padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.itemCount,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AnimatedBuilder(
          animation: _opacity,
          builder: (_, __) => Opacity(
            opacity: _opacity.value,
            child: Container(
              height: widget.itemHeight,
              decoration: BoxDecoration(
                color: JC.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: JC.border, width: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
