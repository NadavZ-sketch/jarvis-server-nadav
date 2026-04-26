import 'package:flutter/material.dart';
import '../main.dart' show JC;

/// Reusable RTL search input matching the design tokens (`JC.*`).
///
/// Replaces the per-screen `_ListSearchBar` / `_RemSearchBar` /
/// `_NoteSearchBar` / `_ConSearchBar` / `_SearchBar` duplicates that lived
/// inside each screen. The visual styling is identical, so callers don't see
/// any UI shift after migration.
class JarvisSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const JarvisSearchBar({
    super.key,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textDirection: TextDirection.rtl,
      style: const TextStyle(
          color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: JC.textMuted, size: 18),
        filled: true,
        fillColor: JC.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JC.border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JC.border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JC.blue500, width: 1),
        ),
      ),
    );
  }
}
