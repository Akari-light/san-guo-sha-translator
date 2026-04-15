// lib/features/codex/data/models/codex_entry_dto.dart

// ── Segment kind ──────────────────────────────────────────────────────────────

/// The semantic role of a single inline text segment inside a [CodexRuleBlock].
///
/// The renderer maps each kind to a fixed visual style — the JSON only records
/// what something *is*, never how it looks.
///
/// | Kind    | Marks                                     | Visual treatment        |
/// |---------|-------------------------------------------|-------------------------|
/// | label   | Timing name, step prefix, principle label | Bold, chapter accent    |
/// | body    | Regular prose                             | Normal definition color |
/// | card    | [Kill], [Dodge], [Iron Shackles] etc.     | w600, VS Code blue      |
/// | skill   | SkillName (e.g. Benevolence, Roar)        | w500, amber             |
/// | token   | TokenName (e.g. Rage, Forbearance)        | w500, muted purple      |
/// | number  | Step counters, ordered markers            | Bold, chapter accent    |
enum CodexSegmentKind { label, body, card, skill, token, number }

// ── Segment ───────────────────────────────────────────────────────────────────

/// A single inline text run inside a [CodexRuleBlock].
class CodexSegment {
  final CodexSegmentKind kind;
  final String cn;
  final String en;

  const CodexSegment({
    required this.kind,
    required this.cn,
    required this.en,
  });

  factory CodexSegment.fromJson(Map<String, dynamic> j) {
    final kind = switch (j['kind'] as String? ?? 'body') {
      'label'  => CodexSegmentKind.label,
      'card'   => CodexSegmentKind.card,
      'skill'  => CodexSegmentKind.skill,
      'token'  => CodexSegmentKind.token,
      'number' => CodexSegmentKind.number,
      _        => CodexSegmentKind.body,
    };
    return CodexSegment(
      kind: kind,
      cn: j['cn'] as String? ?? '',
      en: j['en'] as String? ?? '',
    );
  }
}

// ── Block type ────────────────────────────────────────────────────────────────

enum CodexRuleBlockType { rule, note, caution }

// ── Example ───────────────────────────────────────────────────────────────────

class CodexExample {
  final String cn;
  final String en;
  final List<CodexExample> subExamples;

  const CodexExample({
    required this.cn,
    required this.en,
    this.subExamples = const [],
  });

  factory CodexExample.fromJson(Map<String, dynamic> j) => CodexExample(
        cn: j['cn'] as String? ?? '',
        en: j['en'] as String? ?? '',
        subExamples: (j['sub_examples'] as List<dynamic>? ?? [])
            .map((e) => CodexExample.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CodexRoleDistributionRow {
  final int players;
  final List<CodexRoleDistributionOption> options;

  const CodexRoleDistributionRow({
    required this.players,
    this.options = const [],
  });

  factory CodexRoleDistributionRow.fromJson(Map<String, dynamic> j) =>
      CodexRoleDistributionRow(
        players: (j['players'] as num?)?.toInt() ?? 0,
        options: _parseDistributionOptions(j),
      );
}

class CodexRoleDistributionOption {
  final int lord;
  final int loyalist;
  final int rebel;
  final int spy;

  const CodexRoleDistributionOption({
    required this.lord,
    required this.loyalist,
    required this.rebel,
    required this.spy,
  });

  factory CodexRoleDistributionOption.fromJson(Map<String, dynamic> j) =>
      CodexRoleDistributionOption(
        lord: (j['lord'] as num?)?.toInt() ?? 0,
        loyalist: (j['loyalist'] as num?)?.toInt() ?? 0,
        rebel: (j['rebel'] as num?)?.toInt() ?? 0,
        spy: (j['spy'] as num?)?.toInt() ?? 0,
      );
}

List<CodexRoleDistributionOption> _parseDistributionOptions(
  Map<String, dynamic> j,
) {
  final rawOptions = j['options'] as List<dynamic>?;
  if (rawOptions != null && rawOptions.isNotEmpty) {
    return rawOptions
        .map(
          (option) => CodexRoleDistributionOption.fromJson(
            option as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  return [
    CodexRoleDistributionOption(
      lord: (j['lord'] as num?)?.toInt() ?? 0,
      loyalist: (j['loyalist'] as num?)?.toInt() ?? 0,
      rebel: (j['rebel'] as num?)?.toInt() ?? 0,
      spy: (j['spy'] as num?)?.toInt() ?? 0,
    ),
  ];
}

class CodexRoleData {
  final String roleCn;
  final String roleEn;
  final String goalCn;
  final String goalEn;
  final String tipsCn;
  final String tipsEn;

  const CodexRoleData({
    required this.roleCn,
    required this.roleEn,
    this.goalCn = '',
    this.goalEn = '',
    this.tipsCn = '',
    this.tipsEn = '',
  });

  bool get hasGoal => goalCn.isNotEmpty || goalEn.isNotEmpty;
  bool get hasTips => tipsCn.isNotEmpty || tipsEn.isNotEmpty;

  factory CodexRoleData.fromJson(Map<String, dynamic> j) => CodexRoleData(
        roleCn: j['role_cn'] as String? ?? '',
        roleEn: j['role_en'] as String? ?? '',
        goalCn: j['goal_cn'] as String? ?? '',
        goalEn: j['goal_en'] as String? ?? '',
        tipsCn: j['tips_cn'] as String? ?? '',
        tipsEn: j['tips_en'] as String? ?? '',
      );
}

// ── Rule block ────────────────────────────────────────────────────────────────

/// A single prose block (rule / note / caution) inside a [CodexEntryDTO].
///
/// **Approach B (rich text):** if [segments] is non-empty the renderer builds
/// a [TextSpan] tree from the segment list. The flat [cn]/[en] strings are
/// retained as the search corpus and as a backward-compatible fallback.
///
/// **Fallback (plain text):** if [segments] is empty the renderer displays
/// [cn] or [en] as a plain [Text] widget. All existing JSON files therefore
/// continue to load without modification during the migration.
class CodexRuleBlock {
  final CodexRuleBlockType type;

  /// Flat CN text — search corpus + plain-text fallback.
  final String cn;

  /// Flat EN text — search corpus + plain-text fallback.
  final String en;

  /// Inline segments for rich-text rendering (Approach B).
  /// Empty list → renderer uses flat [cn]/[en] fallback.
  final List<CodexSegment> segments;

  final List<CodexExample> examples;

  const CodexRuleBlock({
    required this.type,
    required this.cn,
    required this.en,
    this.segments = const [],
    this.examples = const [],
  });

  bool get hasSegments => segments.isNotEmpty;

  factory CodexRuleBlock.fromJson(Map<String, dynamic> j) {
    final type = switch (j['type'] as String? ?? 'rule') {
      'note'    => CodexRuleBlockType.note,
      'caution' => CodexRuleBlockType.caution,
      _         => CodexRuleBlockType.rule,
    };
    return CodexRuleBlock(
      type: type,
      cn: j['cn'] as String? ?? '',
      en: j['en'] as String? ?? '',
      segments: (j['segments'] as List<dynamic>? ?? [])
          .map((s) => CodexSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
      examples: (j['examples'] as List<dynamic>? ?? [])
          .map((e) => CodexExample.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Entry ─────────────────────────────────────────────────────────────────────

class CodexEntryDTO {
  final String id;
  final String chapter;
  final String sectionNum;
  final String sectionTitleCn;
  final String sectionTitleEn;
  final String termCn;
  final String termEn;
  final String? badge;
  final String definitionCn;
  final String definitionEn;
  final List<CodexRuleBlock> rules;
  final List<CodexRoleDistributionRow> roleDistribution;
  final List<CodexRoleData> roles;
  final String searchTextCn;
  final String searchTextEn;

  const CodexEntryDTO({
    required this.id,
    required this.chapter,
    required this.sectionNum,
    required this.sectionTitleCn,
    required this.sectionTitleEn,
    required this.termCn,
    required this.termEn,
    this.badge,
    required this.definitionCn,
    required this.definitionEn,
    this.rules = const [],
    this.roleDistribution = const [],
    this.roles = const [],
    required this.searchTextCn,
    required this.searchTextEn,
  });

  factory CodexEntryDTO.fromJson(Map<String, dynamic> j, String chapter) =>
      CodexEntryDTO(
        id:             j['id']              as String,
        chapter:        chapter,
        sectionNum:     j['section_num'] as String? ?? '',
        sectionTitleCn: j['section_title_cn'] as String? ?? '',
        sectionTitleEn: j['section_title_en'] as String? ?? '',
        termCn:         j['term_cn'] as String? ?? '',
        termEn:         j['term_en'] as String? ?? '',
        badge:          j['badge'] as String?,
        definitionCn:   j['definition_cn'] as String? ?? '',
        definitionEn:   j['definition_en'] as String? ?? '',
        rules: (j['rules'] as List<dynamic>? ?? [])
            .map((e) => CodexRuleBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        roleDistribution: (j['role_distribution'] as List<dynamic>? ?? [])
            .map((e) => CodexRoleDistributionRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        roles: (j['roles'] as List<dynamic>? ?? [])
            .map((e) => CodexRoleData.fromJson(e as Map<String, dynamic>))
            .toList(),
        searchTextCn: j['search_text_cn'] as String? ?? '',
        searchTextEn: j['search_text_en'] as String? ?? '',
      );

  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return searchTextCn.toLowerCase().contains(q) ||
        searchTextEn.toLowerCase().contains(q) ||
        termCn.toLowerCase().contains(q) ||
        termEn.toLowerCase().contains(q);
  }
}
