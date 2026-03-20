// lib/features/codex/presentation/codex_chapter_config.dart
//
// Chapter structural config: keys, labels, ordered list.
// Zero Color literals — all colors live in AppTheme.codex*() helpers.

const List<({String key, String labelEn, String labelCn})> kCodexChapters = [
  (key: 'setup',    labelEn: 'Setup',    labelCn: '准备'),
  (key: 'glossary', labelEn: 'Glossary', labelCn: '用语'),
  (key: 'flow',     labelEn: 'Flow',     labelCn: '流程'),
  (key: 'rules',    labelEn: 'Rules',    labelCn: '规则'),
];