import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/inline_suit_text.dart';
import '../../../reference/services/resolver_service.dart';

typedef CodexReferenceTap = void Function(String bracketText, bool isChinese);

final RegExp _referenceTokenPattern = RegExp(
  '(\\[[^\\]]+\\]|\u3010[^\u3011]+\u3011|\u3016[^\u3017]+\u3017)',
);

class CodexReferenceText extends StatelessWidget {
  final String text;
  final bool isDark;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final CodexReferenceTap? onReferenceTap;

  const CodexReferenceText({
    super.key,
    required this.text,
    required this.isDark,
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
        children: _buildReferenceAwareSpans(
          text: text,
          style: effectiveStyle,
          isDark: isDark,
          onReferenceTap: onReferenceTap,
        ),
      ),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

List<InlineSpan> _buildReferenceAwareSpans({
  required String text,
  required TextStyle style,
  required bool isDark,
  CodexReferenceTap? onReferenceTap,
}) {
  final matches = _referenceTokenPattern.allMatches(text).toList(growable: false);
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
    final isChinese = token.startsWith('\u3010') || token.startsWith('\u3016');
    final referenceTap = onReferenceTap;
    final resolvable = referenceTap != null &&
        (ResolverService().canResolve(token, isChinese: isChinese) != false);

    final linkColor = AppTheme.codexCardRef(isDark);
    final linkStyle = style.copyWith(
      fontWeight: FontWeight.w600,
      color: resolvable ? linkColor : style.color,
      decoration: resolvable ? TextDecoration.underline : TextDecoration.none,
      decorationColor: resolvable ? linkColor.withAlpha(120) : null,
    );

    GestureRecognizer? recognizer;
    if (resolvable) {
      recognizer = TapGestureRecognizer()
        ..onTap = () => referenceTap(token, isChinese);
    }

    spans.add(
      TextSpan(
        style: linkStyle,
        recognizer: recognizer,
        children: buildInlineSuitSpans(
          text: token,
          style: linkStyle,
          isDark: isDark,
        ),
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
