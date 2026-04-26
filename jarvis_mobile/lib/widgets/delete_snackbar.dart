import 'package:flutter/material.dart';
import '../main.dart' show JC;

/// Shows a "deleted ✓ — Undo" snackbar styled with the app design tokens.
///
/// Returns the snackbar's `closed` future so callers can run the actual
/// delete only after the undo grace period (when the user did NOT press
/// undo). The boolean argument to [onClosed] is true when the user tapped
/// "בטל" (undo).
void showDeleteSnackbar(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  required void Function(bool wasUndone) onClosed,
  Duration duration = const Duration(seconds: 3),
}) {
  bool undone = false;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger
      .showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
                fontFamily: 'Heebo', color: JC.textPrimary),
            textDirection: TextDirection.rtl,
          ),
          backgroundColor: JC.surfaceAlt,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          duration: duration,
          action: SnackBarAction(
            label: 'בטל',
            textColor: JC.blue400,
            onPressed: () {
              undone = true;
              onUndo();
            },
          ),
        ),
      )
      .closed
      .then((_) => onClosed(undone));
}
