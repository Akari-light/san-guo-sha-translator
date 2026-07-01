import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/inline_suit_text.dart';

typedef ReferenceTap = void Function(String bracketText, bool isChinese);

final RegExp _referenceTokenPattern = RegExp(
  r'(\[[^\]]+\]|【[^】]+】|〖[^〗]+〗|「[^」]+」)',
);

class ReferenceText extends StatelessWidget {
  final String text;
  final bool isDark;
  final bool isChineseText;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final ReferenceTap? onReferenceTap;

  const ReferenceText({
    super.key,
    required this.text,
    required this.isDark,
    this.isChineseText = false,
    this.style,
    this.maxLines,
    this.overflow,
    this.onReferenceTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;

    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: _buildReferenceSpans(
          text: text,
          style: effectiveStyle,
          isDark: isDark,
          isChineseText: isChineseText,
          onReferenceTap: onReferenceTap,
        ),
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

List<InlineSpan> _buildReferenceSpans({
  required String text,
  required TextStyle style,
  required bool isDark,
  required bool isChineseText,
  ReferenceTap? onReferenceTap,
}) {
  final matches = _referenceTokenPattern
      .allMatches(text)
      .toList(growable: false);
  if (matches.isEmpty) {
    return buildInlineSuitSpans(text: text, style: style, isDark: isDark);
  }

  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in matches) {
    if (match.start > cursor) {
      spans.addAll(
        buildInlineSuitSpans(
          text: text.substring(cursor, match.start),
          style: style,
          isDark: isDark,
        ),
      );
    }

    final token = match.group(0)!;
    final linkColor = _referenceColor(token, isDark);
    final referenceTap = onReferenceTap;
    final canTap = referenceTap != null;

    GestureRecognizer? recognizer;
    if (canTap) {
      recognizer = TapGestureRecognizer()
        ..onTap = () =>
            referenceTap(token, _isChineseReference(token, isChineseText));
    }

    spans.add(
      TextSpan(
        text: token,
        style: style.copyWith(
          color: canTap ? linkColor : style.color,
          fontWeight: FontWeight.w600,
          decoration: canTap ? TextDecoration.underline : TextDecoration.none,
          decorationColor: canTap ? linkColor.withValues(alpha: 0.65) : null,
        ),
        recognizer: recognizer,
      ),
    );

    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.addAll(
      buildInlineSuitSpans(
        text: text.substring(cursor),
        style: style,
        isDark: isDark,
      ),
    );
  }

  return spans;
}

Color _referenceColor(String token, bool isDark) {
  if (token.startsWith('〖')) return AppTheme.codexSkillRef(isDark);
  if (token.startsWith('「')) return AppTheme.codexTokenRef(isDark);
  return AppTheme.codexCardRef(isDark);
}

bool _isChineseReference(String token, bool isChineseText) {
  if (token.startsWith('【')) return true;
  if (token.startsWith('[')) return false;
  if (token.startsWith('〖')) {
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(token);
  }
  return isChineseText;
}
