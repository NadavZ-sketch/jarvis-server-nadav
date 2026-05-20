import 'package:flutter/material.dart';
import '../main.dart' show JC;

/// Minimal markdown renderer for chat messages: supports **bold**, *italic*,
/// `inline code`, fenced ```code blocks```, and `- ` / `1. ` lists. Deliberately
/// dependency-free — handles the subset the assistant actually produces.
class MarkdownLite extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final TextDirection textDirection;

  const MarkdownLite({
    super.key,
    required this.text,
    required this.baseStyle,
    this.textDirection = TextDirection.rtl,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final lines = text.split('\n');
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      // Fenced code block
      if (line.trimLeft().startsWith('```')) {
        final buf = <String>[];
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          buf.add(lines[i]);
          i++;
        }
        i++; // skip closing fence
        blocks.add(_codeBlock(buf.join('\n')));
        continue;
      }
      // List item (bullet or numbered)
      final bullet = RegExp(r'^\s*([-*•])\s+(.*)$').firstMatch(line);
      final numbered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        blocks.add(_listItem('•', bullet.group(2) ?? ''));
      } else if (numbered != null) {
        blocks.add(_listItem('${numbered.group(1)}.', numbered.group(2) ?? ''));
      } else if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 6));
      } else {
        blocks.add(Text.rich(
          _inlineSpans(line),
          textDirection: textDirection,
        ));
      }
      i++;
    }
    return Column(
      crossAxisAlignment: textDirection == TextDirection.rtl
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _listItem(String marker, String content) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          textDirection: textDirection,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(marker,
                style: baseStyle.copyWith(
                    color: JC.blue400, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(_inlineSpans(content),
                  textDirection: textDirection),
            ),
          ],
        ),
      );

  Widget _codeBlock(String code) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: JC.bg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: SelectableText(
          code,
          textDirection: TextDirection.ltr,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            fontSize: (baseStyle.fontSize ?? 15) - 1,
            color: JC.blue300,
          ),
        ),
      );

  TextSpan _inlineSpans(String input) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'(\*\*.+?\*\*|`.+?`|\*.+?\*)');
    int last = 0;
    for (final m in pattern.allMatches(input)) {
      if (m.start > last) {
        spans.add(TextSpan(text: input.substring(last, m.start), style: baseStyle));
      }
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (tok.startsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            color: JC.blue300,
            background: Paint()..color = JC.bg.withValues(alpha: 0.5),
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      last = m.end;
    }
    if (last < input.length) {
      spans.add(TextSpan(text: input.substring(last), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }
}
