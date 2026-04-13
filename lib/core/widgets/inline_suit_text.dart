import 'package:flutter/material.dart';

enum SuitKind { hearts, diamonds, spades, clubs }

final RegExp _inlineSuitTokenRegex = RegExp(
  r'Hearts\s*[♥]?|Diamonds\s*[♦]?|Spades\s*[♠]?|Clubs\s*[♣]?|红桃\s*[♥]?|方块\s*[♦]?|黑桃\s*[♠]?|梅花\s*[♣]?|[♥♦♠♣]',
  caseSensitive: false,
);

List<InlineSpan> buildInlineSuitSpans({
  required String text,
  required TextStyle style,
  required bool isDark,
}) {
  final matches = _inlineSuitTokenRegex.allMatches(text).toList(growable: false);
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(
        text: text.substring(cursor, match.start),
        style: style,
      ));
    }

    final token = match.group(0)!;
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _SuitInlineMark(
          kind: _kindForToken(token),
          textStyle: style,
          isDark: isDark,
        ),
      ),
    );

    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(
      text: text.substring(cursor),
      style: style,
    ));
  }

  return spans;
}

class InlineSuitText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final bool isDark;
  final int? maxLines;
  final TextOverflow? overflow;

  const InlineSuitText({
    super.key,
    required this.text,
    required this.isDark,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: buildInlineSuitSpans(
          text: text,
          style: effectiveStyle,
          isDark: isDark,
        ),
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

SuitKind _kindForToken(String token) {
  final lower = token.toLowerCase();
  if (lower.contains('heart') || token.contains('红桃') || token.contains('♥')) {
    return SuitKind.hearts;
  }
  if (lower.contains('diamond') || token.contains('方块') || token.contains('♦')) {
    return SuitKind.diamonds;
  }
  if (lower.contains('spade') || token.contains('黑桃') || token.contains('♠')) {
    return SuitKind.spades;
  }
  return SuitKind.clubs;
}

class _SuitInlineMark extends StatelessWidget {
  final SuitKind kind;
  final TextStyle textStyle;
  final bool isDark;

  const _SuitInlineMark({
    required this.kind,
    required this.textStyle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = textStyle.fontSize ?? 14;
    final symbol = switch (kind) {
      SuitKind.hearts => '♥',
      SuitKind.diamonds => '♦',
      SuitKind.spades => '♠',
      SuitKind.clubs => '♣',
    };
    final color = switch (kind) {
      SuitKind.hearts || SuitKind.diamonds => const Color(0xFFE11D48),
      SuitKind.spades || SuitKind.clubs => isDark
          ? Colors.white.withAlpha(235)
          : Colors.black.withAlpha(220),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        symbol,
        style: textStyle.copyWith(
          fontSize: fontSize + 1,
          height: 1.0,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
