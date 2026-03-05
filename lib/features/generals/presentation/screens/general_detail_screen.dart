import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../../../core/models/skill_dto.dart';
import '../../../../core/theme/app_theme.dart';

class GeneralDetailScreen extends StatefulWidget {
  final GeneralCard card;

  const GeneralDetailScreen({super.key, required this.card});

  @override
  State<GeneralDetailScreen> createState() => _GeneralDetailScreenState();
}

class _GeneralDetailScreenState extends State<GeneralDetailScreen> {
  bool _isEnglish = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card = widget.card;
    final factionColor = AppTheme.factionColor(card.faction);

    return Scaffold(
      appBar: AppBar(
        title: Text(card.nameCn),
        centerTitle: true,
        actions: [
          // ── Language toggle ───────────────────────────────────────────────
          TextButton(
            onPressed: () => setState(() => _isEnglish = !_isEnglish),
            style: TextButton.styleFrom(
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              _isEnglish ? 'EN ➔ 中' : '中 ➔ EN',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card image ──────────────────────────────────────────────────
            Center(
              child: Hero(
                tag: card.id,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: factionColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: factionColor.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.asset(
                      card.imagePath,
                      height: 280,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Image.asset(
                        GeneralCard.placeholderImagePath,
                        height: 280,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Name + badges row ───────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEnglish ? card.nameEn : card.nameCn,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Faction badge
                          _Badge(
                            label: _isEnglish ? card.faction : card.factionCn,
                            color: factionColor,
                          ),
                          const SizedBox(width: 8),
                          // Expansion badge
                          _Badge(
                            label: card.expansionBadge,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Stat row: health, power, gender ────────────────────────────
            Row(
              children: [
                _StatChip(
                  icon: Icons.favorite,
                  iconColor: Colors.redAccent,
                  label: '${card.health}',
                  tooltip: 'Health',
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.bolt,
                  iconColor: Colors.amber,
                  label: card.powerStars.isEmpty ? '—' : card.powerStars,
                  tooltip: 'Power Index',
                ),
                const SizedBox(width: 10),
                _StatChip(
                  icon: card.gender == 'Female'
                      ? Icons.female
                      : Icons.male,
                  iconColor: card.gender == 'Female'
                      ? Colors.pinkAccent
                      : Colors.blueAccent,
                  label: _isEnglish
                      ? card.gender
                      : (card.gender == 'Female' ? '女' : '男'),
                  tooltip: 'Gender',
                ),
              ],
            ),

            // ── Traits ─────────────────────────────────────────────────────
            if (card.traits.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(
                  context, _isEnglish ? 'TRAITS' : '特征'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: card.traits
                    .map((t) => _TraitChip(label: t))
                    .toList(),
              ),
            ],

            const Divider(height: 32),

            // ── Skills ─────────────────────────────────────────────────────
            _buildSectionHeader(
                context, _isEnglish ? 'SKILLS' : '技能'),
            const SizedBox(height: 12),
            ...card.skills.map(
              (skill) => _SkillCard(
                skill: skill,
                isEnglish: _isEnglish,
                isDark: isDark,
                theme: theme,
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            letterSpacing: 1.2,
            color: Theme.of(context).hintColor,
          ),
    );
  }
}

// ── Skill card ────────────────────────────────────────────────────────────────

class _SkillCard extends StatelessWidget {
  final SkillDTO skill;
  final bool isEnglish;
  final bool isDark;
  final ThemeData theme;

  const _SkillCard({
    required this.skill,
    required this.isEnglish,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final descriptionColor = isDark
        ? (isEnglish
            ? AppTheme.descriptionEnDark
            : AppTheme.descriptionCnDark)
        : theme.textTheme.bodyMedium?.color;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skill name + type badge
          Row(
            children: [
              Text(
                isEnglish ? skill.nameEn : skill.nameCn,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (skill.skillType.hasBadge) ...[
                const SizedBox(width: 8),
                _SkillTypeBadge(
                  label: isEnglish
                      ? skill.skillType.labelEn
                      : skill.skillType.labelCn,
                  type: skill.skillType,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Description
          Text(
            isEnglish ? skill.descriptionEn : skill.descriptionCn,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: descriptionColor,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skill type badge ──────────────────────────────────────────────────────────

class _SkillTypeBadge extends StatelessWidget {
  final String label;
  final SkillType type;

  const _SkillTypeBadge({required this.label, required this.type});

  Color get _color {
    switch (type) {
      case SkillType.lord:      return Colors.amber;
      case SkillType.limited:   return Colors.redAccent;
      case SkillType.awakening: return Colors.purpleAccent;
      case SkillType.locked:    return Colors.blueAccent;
      case SkillType.active:    return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Faction / expansion badge ─────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String tooltip;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Trait chip ────────────────────────────────────────────────────────────────

class _TraitChip extends StatelessWidget {
  final String label;

  const _TraitChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}