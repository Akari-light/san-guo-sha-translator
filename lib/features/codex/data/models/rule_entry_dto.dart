import '../../../../core/services/search_service.dart';

// ── Block type ────────────────────────────────────────────────────────────────

/// The semantic role of a prose block inside a [RuleEntryDTO].
enum RuleBlockType {
  /// A core rule statement.
  rule,

  /// An explanatory note or clarification.
  note,

  /// A caution or common-mistake warning.
  caution,

  /// A worked example or case study.
  definition,
}

// ── Example ───────────────────────────────────────────────────────────────────

/// A single example (or sub-example) inside a [RuleBlock].
class RuleExample {
  final String cn;
  final String en;

  /// Optional nested examples (max one level of nesting under a top-level
  /// example, giving three total levels: block → example → sub-example).
  final List<RuleExample> subExamples;

  const RuleExample({
    required this.cn,
    required this.en,
    this.subExamples = const [],
  });

  factory RuleExample.fromJson(Map<String, dynamic> json) {
    return RuleExample(
      cn: json['cn'] as String,
      en: json['en'] as String,
      subExamples: (json['sub_examples'] as List? ?? [])
          .map((e) => RuleExample.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Rule block ────────────────────────────────────────────────────────────────

/// A single prose block (rule / note / caution / definition) with optional examples.
class RuleBlock {
  final RuleBlockType type;
  final String cn;
  final String en;
  final List<RuleExample> examples;

  const RuleBlock({
    required this.type,
    required this.cn,
    required this.en,
    this.examples = const [],
  });

  factory RuleBlock.fromJson(Map<String, dynamic> json) {
    return RuleBlock(
      type: RuleBlockType.values.firstWhere(
        (t) => t.name == (json['type'] as String),
        orElse: () => RuleBlockType.rule,
      ),
      cn: json['cn'] as String,
      en: json['en'] as String,
      examples: (json['examples'] as List? ?? [])
          .map((e) => RuleExample.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Rule entry ────────────────────────────────────────────────────────────────

/// A single entry in any of the info / glossary / rules chapters.
///
/// All three chapter types share this schema — the [chapter] field
/// distinguishes them: `"info"`, `"glossary"`, or `"rules"`.
class RuleEntryDTO {
  final String id;
  final String chapter;
  final String sectionNum;
  final String sectionTitleCn;
  final String sectionTitleEn;
  final String termCn;
  final String termEn;

  /// Optional badge key — maps to the app's skill-type or category badge
  /// system. `null` for entries that carry no badge.
  final String? badge;

  final String definitionCn;
  final String definitionEn;
  final List<RuleBlock> rules;

  /// Pre-built search corpus (CN). Populated in JSON so the loader does
  /// not need to reconstruct it at runtime.
  final String searchTextCn;

  /// Pre-built search corpus (EN).
  final String searchTextEn;

  const RuleEntryDTO({
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
    required this.rules,
    required this.searchTextCn,
    required this.searchTextEn,
  });

  factory RuleEntryDTO.fromJson(Map<String, dynamic> json) {
    return RuleEntryDTO(
      id:               json['id']                as String,
      chapter:          json['chapter']           as String,
      sectionNum:       json['section_num']       as String,
      sectionTitleCn:   json['section_title_cn']  as String,
      sectionTitleEn:   json['section_title_en']  as String,
      termCn:           json['term_cn']           as String,
      termEn:           json['term_en']           as String,
      badge:            json['badge']             as String?,
      definitionCn:     json['definition_cn']     as String,
      definitionEn:     json['definition_en']     as String,
      rules: (json['rules'] as List? ?? [])
          .map((e) => RuleBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
      searchTextCn:     json['search_text_cn']    as String,
      searchTextEn:     json['search_text_en']    as String,
    );
  }

  /// Fuzzy match against term names, section titles, and the pre-built
  /// search corpora.
  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    if (SearchService.fuzzyMatch(query, termEn))         return true;
    if (SearchService.fuzzyMatch(query, termCn))         return true;
    if (SearchService.fuzzyMatch(query, sectionTitleEn)) return true;
    if (SearchService.fuzzyMatch(query, sectionTitleCn)) return true;
    if (SearchService.fuzzyMatch(query, searchTextEn))   return true;
    if (SearchService.fuzzyMatch(query, searchTextCn))   return true;
    return false;
  }
}

// ── Flow chapter ──────────────────────────────────────────────────────────────

/// Phase classification for a timing slot inside a [RuleFlowEntryDTO].
enum TimingPhase {
  /// Before the main resolution begins.
  pre,

  /// During the main resolution.
  during,

  /// After the main resolution completes.
  post,
}

/// A single timing slot inside a flow event.
class RuleTiming {
  final int order;
  final String labelCn;
  final String labelEn;
  final TimingPhase phase;
  final String descriptionCn;
  final String descriptionEn;

  /// Optional skill IDs whose trigger points correspond to this timing.
  /// Used by [ResolverService] to surface cross-links to GeneralDetailScreen.
  final List<String> skillRefs;

  final List<RuleBlock> rules;

  const RuleTiming({
    required this.order,
    required this.labelCn,
    required this.labelEn,
    required this.phase,
    required this.descriptionCn,
    required this.descriptionEn,
    this.skillRefs = const [],
    this.rules = const [],
  });

  factory RuleTiming.fromJson(Map<String, dynamic> json) {
    return RuleTiming(
      order:          json['order']           as int,
      labelCn:        json['label_cn']        as String,
      labelEn:        json['label_en']        as String,
      phase: TimingPhase.values.firstWhere(
        (p) => p.name == (json['phase'] as String),
        orElse: () => TimingPhase.during,
      ),
      descriptionCn:  json['description_cn']  as String,
      descriptionEn:  json['description_en']  as String,
      skillRefs: List<String>.from(json['skill_refs'] ?? []),
      rules: (json['rules'] as List? ?? [])
          .map((e) => RuleBlock.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A single entry in the flow chapter (§3).
///
/// Each entry corresponds to one named event type (e.g. §3.8 Damage Event)
/// and contains an ordered list of timing slots.
class RuleFlowEntryDTO {
  final String id;
  final String chapter;
  final String sectionNum;

  /// Optional introductory prose before the timing list.
  final String preambleCn;
  final String preambleEn;

  final List<RuleTiming> timings;

  /// Optional closing prose after the timing list.
  final String postambleCn;
  final String postambleEn;

  const RuleFlowEntryDTO({
    required this.id,
    required this.chapter,
    required this.sectionNum,
    this.preambleCn   = '',
    this.preambleEn   = '',
    required this.timings,
    this.postambleCn  = '',
    this.postambleEn  = '',
  });

  factory RuleFlowEntryDTO.fromJson(Map<String, dynamic> json) {
    return RuleFlowEntryDTO(
      id:           json['id']            as String,
      chapter:      json['chapter']       as String,
      sectionNum:   json['section_num']   as String,
      preambleCn:   json['preamble_cn']   as String? ?? '',
      preambleEn:   json['preamble_en']   as String? ?? '',
      timings: (json['timings'] as List? ?? [])
          .map((e) => RuleTiming.fromJson(e as Map<String, dynamic>))
          .toList(),
      postambleCn:  json['postamble_cn']  as String? ?? '',
      postambleEn:  json['postamble_en']  as String? ?? '',
    );
  }

  /// Fuzzy match against section number and timing labels.
  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    if (sectionNum.contains(query)) return true;
    return timings.any((t) =>
        SearchService.fuzzyMatch(query, t.labelEn) ||
        SearchService.fuzzyMatch(query, t.labelCn));
  }
}
