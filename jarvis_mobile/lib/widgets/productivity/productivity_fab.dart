import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../main.dart' show JC;

/// Expandable contextual FAB for the Productivity screen.
///
/// Direct tap behaviour:
///   - Tasks tab (index 1)   → open add-task sheet immediately
///   - Reminders tab (index 2) → open add-reminder sheet immediately
///   - Any other tab          → toggle speed-dial expansion
///
/// Long-press always toggles expansion regardless of current tab.
class ProductivityFAB extends StatefulWidget {
  final int currentTab;
  final VoidCallback onAddTask;
  final VoidCallback onAddReminder;
  final VoidCallback onAddEvent;
  final ValueChanged<bool>? onExpansionChanged;

  const ProductivityFAB({
    super.key,
    required this.currentTab,
    required this.onAddTask,
    required this.onAddReminder,
    required this.onAddEvent,
    this.onExpansionChanged,
  });

  @override
  State<ProductivityFAB> createState() => _ProductivityFABState();
}

class _ProductivityFABState extends State<ProductivityFAB>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  void _toggle() {
    HapticFeedback.lightImpact();
    final next = !_expanded;
    setState(() => _expanded = next);
    widget.onExpansionChanged?.call(next);
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    widget.onExpansionChanged?.call(false);
  }

  void _onTap() {
    if (widget.currentTab == 1) {
      widget.onAddTask();
    } else if (widget.currentTab == 2) {
      widget.onAddReminder();
    } else {
      _toggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Speed-dial options slide in from below
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _MiniFABRow(
                        label: '+ אירוע',
                        icon: Icons.event_rounded,
                        color: JC.indigo500,
                        delay: 120,
                        onTap: () {
                          _collapse();
                          widget.onAddEvent();
                        },
                      ),
                      const SizedBox(height: 10),
                      _MiniFABRow(
                        label: '+ תזכורת',
                        icon: Icons.notifications_rounded,
                        color: JC.amber400,
                        delay: 60,
                        onTap: () {
                          _collapse();
                          widget.onAddReminder();
                        },
                      ),
                      const SizedBox(height: 10),
                      _MiniFABRow(
                        label: '+ משימה',
                        icon: Icons.check_circle_outline_rounded,
                        color: JC.blue400,
                        delay: 0,
                        onTap: () {
                          _collapse();
                          widget.onAddTask();
                        },
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        // Main FAB
        GestureDetector(
          onLongPress: _toggle,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: JC.blue500.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FloatingActionButton(
              onPressed: _onTap,
              backgroundColor: JC.blue500,
              elevation: 0,
              child: AnimatedRotation(
                turns: _expanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 220),
                child:
                    const Icon(Icons.add_rounded, color: Colors.white, size: 26),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Mini FAB row ─────────────────────────────────────────────────────────────

class _MiniFABRow extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int delay;
  final VoidCallback onTap;

  const _MiniFABRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.delay,
    required this.onTap,
  });

  @override
  State<_MiniFABRow> createState() => _MiniFABRowState();
}

class _MiniFABRowState extends State<_MiniFABRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: widget.color.withOpacity(0.4), width: 1),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: widget.color),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 13,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
