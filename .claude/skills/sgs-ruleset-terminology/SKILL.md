---
name: sgs-ruleset-terminology
description: Enforce project-specific English terminology for SGS / 三国杀 rules, skill text, timing words, card operations, and death-related procedures by checking the official Chinese ruleset first and applying the project's fixed glossary consistently during translation, review, and copy editing.
---

# SGS Ruleset Terminology

Use the Chinese official rules text as the authority. Do not treat fan translations as authoritative.

## Workflow

1. Read the relevant official rules section first.
2. Read [canonical-terms.md](references/canonical-terms.md) for the fixed English term map and mandatory distinctions.
3. Read [official-rules-review.md](references/official-rules-review.md) when the task touches disputed or easily-mistranslated terms.
4. Translate or review using the canonical English terms exactly.
5. If the Chinese source does not clearly support an English nuance, say so and keep the wording conservative.

## Enforcement Rules

- Preserve keyword distinctions exactly. Do not merge near-synonyms for style.
- Treat the Chinese term as the source of truth and the English term as a fixed project label.
- If two Chinese terms are distinct in the rules, keep them distinct in English even if the English feels repetitive.
- Prefer consistency over elegance. Repeated exact wording is acceptable.
- When a project-chosen English label is not explicitly supplied by the official site, keep using the project label once chosen; do not improvise variants later.
- Flag any wording that weakens modality or rules force, especially `须`, `可`, `视为`, `无效`, `无视`, `抵消`, and `取消`.

## Review Mode

When reviewing an existing translation:

1. Quote the Chinese term.
2. State the required canonical English term.
3. Explain whether the draft is faithful to the official rule text, unsupported by the source, or internally inconsistent.
4. Prefer corrections that minimize downstream glossary churn.

## Scope Notes

- This skill is project-local and should be used for this repository's SGS translator work.
- Card names may still follow the app's established card-name glossary when that glossary is separate from rules terminology.
- If a term is not covered in the references, derive from the official Chinese rules text and extend the glossary conservatively.
