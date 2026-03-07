import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../data/repository/general_loader.dart';
import '../../../../core/models/skill_dto.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/services/resolver_service.dart';
import '../../../library/presentation/screens/library_detail_screen.dart';



class GeneralDetailScreen extends StatefulWidget {
  final GeneralCard card;
  const GeneralDetailScreen({super.key, required this.card});

  @override
  State<GeneralDetailScreen> createState() => _GeneralDetailScreenState();
}

class _GeneralDetailScreenState extends State<GeneralDetailScreen>
    with SingleTickerProviderStateMixin {
  // ── Language
  bool _isEnglish = true;

  // ── Pin
  bool _isPinned = false;

  // ── Active card / variants
  late GeneralCard _activeCard;
  List<GeneralCard> _variants = [];
  bool _variantsLoading = true;

  // ── Resolved related-card references
  List<ResolvedReference> _refsEn = [];
  List<ResolvedReference> _refsCn = [];
  bool _refsLoading = true;

  // ── Skills/FAQ tab controller
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _activeCard = widget.card;
    _tabController = TabController(length: 2, vsync: this);
    _loadVariants();
    _loadPinState();
    _resolveRefs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data loaders 
  Future<void> _loadVariants() async {
    final variants = await GeneralLoader().getVariants(_activeCard.standardId);
    if (!mounted) return;
    setState(() {
      _variants = variants
        ..sort((a, b) => a.expansion.index.compareTo(b.expansion.index));
      _variantsLoading = false;
    });
  }

  Future<void> _loadPinState() async {
    final pinned = await PinService.instance.isPinned(_activeCard.id);
    if (!mounted) return;
    setState(() => _isPinned = pinned);
  }

  Future<void> _resolveRefs() async {
    setState(() => _refsLoading = true);
    final results = await Future.wait([
      ResolverService().resolveGeneralSkills(_activeCard.skills, isChinese: true),
      ResolverService().resolveGeneralSkills(_activeCard.skills, isChinese: false),
    ]);
    if (!mounted) return;
    setState(() {
      _refsCn = results[0];
      _refsEn = results[1];
      _refsLoading = false;
    });
  }

  // ── Actions 
  void _switchVersion(GeneralCard next) {
    if (next.id == _activeCard.id) return;
    setState(() {
      _activeCard = next;
      _refsEn = [];
      _refsCn = [];
      _refsLoading = true;
      _tabController.index = 0; // reset to Skills tab on version switch
    });
    _loadPinState();
    _resolveRefs();
  }

  Future<void> _togglePin() async {
    final nowPinned = await PinService.instance.toggle(_activeCard.id);
    if (!mounted) return;
    setState(() => _isPinned = nowPinned);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(nowPinned
          ? '${_activeCard.nameEn} pinned to Home'
          : '${_activeCard.nameEn} unpinned'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build 
  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final card     = _activeCard;
    final fc       = AppTheme.factionColor(card.faction);
    final refs     = _isEnglish ? _refsEn : _refsCn;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          card.nameCn,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: _isPinned ? fc : null,
            ),
            tooltip: _isPinned ? 'Unpin' : 'Pin to Home',
            onPressed: _togglePin,
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Hero row: image | identity | lang toggle 
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [

                  // ── Card image 160×240 — BoxFit.cover never upscales the
                  //    630×836 source; it scales down and centre-crops only.
                  _CardImage(card: card, factionColor: fc),

                  const SizedBox(width: 18),

                  // ── Identity column
                  Expanded(
                    child: _IdentityColumn(
                      card: card,
                      isEnglish: _isEnglish,
                      factionColor: fc,
                      isDark: isDark,
                    ),
                  ),

                  const SizedBox(width: 6),

                  // ── Lang toggle — bottom-aligned with card image
                  _LangToggle(
                    isEnglish: _isEnglish,
                    factionColor: fc,
                    onToggle: () => setState(() => _isEnglish = !_isEnglish),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Traits 
            if (card.traitsEn.isNotEmpty) ...[
              _SectionLabel(label: _isEnglish ? 'Traits' : '特征'),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: (_isEnglish ? card.traitsEn : card.traitsCn)
                    .map((t) => _TraitChip(label: t, theme: theme))
                    .toList(),
              ),
            ],

            _Divider(),

            // ── Version segment 
            if (!_variantsLoading && _variants.length > 1) ...[
              _SectionLabel(label: _isEnglish ? 'Version' : '版本'),
              const SizedBox(height: 10),
              _VersionSegment(
                variants: _variants,
                activeId: _activeCard.id,
                isEnglish: _isEnglish,
                onSelect: _switchVersion,
              ),
              _Divider(),
            ],

            // ── Skills / FAQ tabs 
            _TabBar(
              controller: _tabController,
              faqCount: card.faq.length,
              factionColor: fc,
              isEnglish: _isEnglish,
              theme: theme,
            ),
            const SizedBox(height: 16),

            // Skills tab body
            ListenableBuilder(
              listenable: _tabController,
              builder: (context, _) {
                if (_tabController.index == 0) {
                  return Column(
                    children: card.skills
                        .map((s) => _SkillCard(
                              skill: s,
                              isEnglish: _isEnglish,
                              isDark: isDark,
                              theme: theme,
                            ))
                        .toList(),
                  );
                } else {
                  return _FaqList(
                    faq: card.faq,
                    isEnglish: _isEnglish,
                    theme: theme,
                  );
                }
              },
            ),

            _Divider(),

            // ── Related Cards 
            _SectionLabel(label: _isEnglish ? 'Related Cards' : '相关牌'),
            const SizedBox(height: 10),
            if (_refsLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Loading…', style: TextStyle(fontSize: 12)),
                ]),
              )
            else if (refs.isEmpty)
              Text(
                _isEnglish
                    ? 'No card references in skill descriptions.'
                    : '技能描述中未找到相关牌。',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.hintColor,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: refs.map((ref) {
                  if (ref.type == ReferenceType.libraryCard &&
                      ref.libraryCard != null) {
                    return _RelatedCardChip(
                      label: _isEnglish
                          ? ref.libraryCard!.nameEn
                          : ref.libraryCard!.nameCn,
                      category: ref.libraryCard!.categoryEn,
                      isDark: isDark,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LibraryDetailScreen(card: ref.libraryCard!),
                        ),
                      ),
                    );
                  } else {
                    return _RelatedSkillChip(
                      label: _isEnglish ? ref.nameEn : ref.nameCn,
                    );
                  }
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Card image 
class _CardImage extends StatelessWidget {
  final GeneralCard card;
  final Color factionColor;

  const _CardImage({required this.card, required this.factionColor});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: card.id,
      child: Container(
        width: 160,
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: factionColor, width: 2.5),
          boxShadow: [
            // tight inner glow
            BoxShadow(
              color: factionColor.withValues(alpha: 0.55),
              blurRadius: 12,
              spreadRadius: 1,
            ),
            // wide ambient bloom
            BoxShadow(
              color: factionColor.withValues(alpha: 0.2),
              blurRadius: 32,
              spreadRadius: 4,
            ),
            // depth shadow
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.5),
          child: Image.asset(
            card.imagePath,
            width: 160,
            height: 240,
            fit: BoxFit.cover,
            errorBuilder: (context, error, _) => Image.asset(
              GeneralCard.placeholderImagePath,
              width: 160,
              height: 240,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Identity column (name, faction, health, power, gender) 
class _IdentityColumn extends StatelessWidget {
  final GeneralCard card;
  final bool isEnglish;
  final Color factionColor;
  final bool isDark;

  const _IdentityColumn({
    required this.card,
    required this.isEnglish,
    required this.factionColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // Name
        Text(
          isEnglish ? card.nameEn : card.nameCn,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: isEnglish ? 24 : 22,
            letterSpacing: isEnglish ? -0.3 : 1.5,
            height: 1.15,
          ),
        ),

        const SizedBox(height: 10),

        // Faction badge
        _Badge(
          label: isEnglish ? card.faction : card.factionCn,
          color: factionColor,
        ),

        const SizedBox(height: 14),

        // Health label
        _MicroLabel(label: isEnglish ? 'Health' : '体力'),
        const SizedBox(height: 6),
        _HealthPips(health: card.health),

        const SizedBox(height: 12),

        // Power label
        _MicroLabel(label: isEnglish ? 'Power' : '战力'),
        const SizedBox(height: 6),
        _PowerStars(value: card.powerIndex),

        const SizedBox(height: 12),

        // Gender
        Text(
          card.gender == 'Female'
              ? (isEnglish ? '♀  Female' : '♀  女')
              : (isEnglish ? '♂  Male'   : '♂  男'),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            color: card.gender == 'Female'
                ? const Color(0xFFF9A8D4) // pink — same for dark/light
                : const Color(0xFF93C5FD), // sky blue
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Lang toggle (vertical EN/中 with animated arrow + radial glow )
class _LangToggle extends StatelessWidget {
  final bool isEnglish;
  final Color factionColor;
  final VoidCallback onToggle;

  const _LangToggle({
    required this.isEnglish,
    required this.factionColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // EN label
            _GlowLabel(
              text: 'EN',
              active: isEnglish,
              factionColor: factionColor,
              fontSize: 11,
              letterSpacing: 1.0,
            ),

            const SizedBox(height: 6),

            // Arrow — rotates to point at active language
            AnimatedRotation(
              turns: isEnglish ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              child: Icon(
                Icons.arrow_downward_rounded,
                size: 14,
                color: factionColor.withValues(alpha: 0.5),
              ),
            ),

            const SizedBox(height: 6),

            // 中 label
            _GlowLabel(
              text: '中',
              active: !isEnglish,
              factionColor: factionColor,
              fontSize: 13,
              letterSpacing: 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowLabel extends StatelessWidget {
  final String text;
  final bool active;
  final Color factionColor;
  final double fontSize;
  final double letterSpacing;

  const _GlowLabel({
    required this.text,
    required this.active,
    required this.factionColor,
    required this.fontSize,
    required this.letterSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: active ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          child: Container(
            width: 36,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  factionColor.withValues(alpha: 0.32),
                  factionColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // Label text
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: letterSpacing,
            color: active
                ? factionColor
                : Colors.white.withValues(alpha: 0.22),
          ),
          child: Text(text),
        ),
      ],
    );
  }
}

// ── Health pips 
class _HealthPips extends StatelessWidget {
  final int health;
  const _HealthPips({required this.health});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(health, (i) {
        return Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.only(right: 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF7F7F), Color(0xFFE53935)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE53935).withValues(alpha: 0.65),
                blurRadius: 6,
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Power stars (split-half per star, 0.5 increments clearly distinct )
class _PowerStars extends StatelessWidget {
  final double value;
  const _PowerStars({required this.value});

  static const Color _goldColor = AppTheme.skillLord; // reuse gold from theme
  static const Color _dimColor  = Color(0x1AFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final leftLit  = value >= i + 0.5;
        final rightLit = value >= i + 1.0;
        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(
            children: [
              // dim base star
              const Center(
                child: Text(
                  '★',
                  style: TextStyle(fontSize: 18, color: _dimColor, height: 1),
                ),
              ),
              // left half
              ClipRect(
                clipper: _HalfClipper(left: true),
                child: Center(
                  child: Text(
                    '★',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1,
                      color: leftLit ? _goldColor : Colors.transparent,
                    ),
                  ),
                ),
              ),
              // right half
              ClipRect(
                clipper: _HalfClipper(left: false),
                child: Center(
                  child: Text(
                    '★',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1,
                      color: rightLit ? _goldColor : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _HalfClipper extends CustomClipper<Rect> {
  final bool left;
  const _HalfClipper({required this.left});

  @override
  Rect getClip(Size size) => left
      ? Rect.fromLTWH(0, 0, size.width / 2, size.height)
      : Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(_HalfClipper old) => old.left != left;
}

// ── Version segment control 
class _VersionSegment extends StatelessWidget {
  final List<GeneralCard> variants;
  final String activeId;
  final bool isEnglish;
  final ValueChanged<GeneralCard> onSelect;

  const _VersionSegment({
    required this.variants,
    required this.activeId,
    required this.isEnglish,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = variants.firstWhere((v) => v.id == activeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segment bar
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: variants.map((v) {
              final isActive = v.id == activeId;
              final ec       = AppTheme.expansionColor(v.expansion);
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isActive
                          ? ec.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? ec.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Badge glyph
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: isActive
                                ? ec
                                : theme.hintColor.withValues(alpha: 0.35),
                          ),
                          child: Text(
                            v.expansionBadge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Health pips (mini)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(v.health, (i) {
                            return Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFFE53935)
                                        .withValues(alpha: 0.3),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 8),

        // Active version label row
        Row(
          children: [
            Text(
              isEnglish
                  ? active.expansion.labelEn
                  : active.expansion.labelCn,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.expansionColor(active.expansion),
              ),
            ),
            Text(
              '  ·  ',
              style: TextStyle(
                fontSize: 11,
                color: theme.hintColor.withValues(alpha: 0.3),
              ),
            ),
            Text(
              '${active.skills.length} ${isEnglish ? "skill" : "技能"}'
              '${isEnglish && active.skills.length != 1 ? "s" : ""}',
              style: TextStyle(
                fontSize: 11,
                color: theme.hintColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Skills/FAQ tab bar 
class _TabBar extends StatelessWidget {
  final TabController controller;
  final int faqCount;
  final Color factionColor;
  final bool isEnglish;
  final ThemeData theme;

  const _TabBar({
    required this.controller,
    required this.faqCount,
    required this.factionColor,
    required this.isEnglish,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme.copyWith(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      child: TabBar(
        controller: controller,
        indicatorColor: factionColor,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: factionColor,
        unselectedLabelColor: theme.hintColor,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        dividerColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 10,
        letterSpacing: 2,
      ),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w400,
        fontSize: 10,
        letterSpacing: 2,
      ),
      tabs: [
        Tab(text: isEnglish ? 'SKILLS' : '技能'),
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEnglish ? 'FAQ' : '问答',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
              if (faqCount > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: factionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: factionColor.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '$faqCount',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: factionColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      )
    );
  }
}

// ── Skill card (collapsible, gradient border fading left→right )
class _SkillCard extends StatefulWidget {
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
  State<_SkillCard> createState() => _SkillCardState();
}

class _SkillCardState extends State<_SkillCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppTheme.skillTypeColor(widget.skill.skillType);
    final dimColor    = widget.theme.colorScheme.outlineVariant
        .withValues(alpha: 0.35);
    final bgColor     = widget.theme.colorScheme.surface.withValues(alpha: 0.5);
    final descColor   = widget.isDark
        ? (widget.isEnglish
            ? AppTheme.descriptionEnDark
            : AppTheme.descriptionCnDark)
        : widget.theme.textTheme.bodyMedium?.color;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: CustomPaint(
          painter: _SkillCardBorderPainter(
            accentColor: accentColor,
            dimColor: dimColor,
            bgColor: bgColor,
            radius: 12,
          ),
          child: Padding(
            // Inset content so it sits inside the painted border (1.5px stroke)
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Text(
                      widget.isEnglish
                          ? widget.skill.nameEn
                          : widget.skill.nameCn,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (widget.skill.skillType.hasBadge) ...[
                      const SizedBox(width: 8),
                      _SkillTypeBadge(
                        label: widget.isEnglish
                            ? widget.skill.skillType.labelEn
                            : widget.skill.skillType.labelCn,
                        color: accentColor,
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: widget.theme.hintColor.withValues(alpha: 0.4),
                    ),
                  ],
                ),

                // Description — collapses
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.isEnglish
                          ? widget.skill.descriptionEn
                          : widget.skill.descriptionCn,
                      style: widget.theme.textTheme.bodyMedium?.copyWith(
                        color: descColor,
                        height: 1.72,
                        fontStyle: widget.isEnglish
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 260),
                  sizeCurve: Curves.easeInOut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCardBorderPainter extends CustomPainter {
  final Color accentColor;
  final Color dimColor;
  final Color bgColor;
  final double radius;

  const _SkillCardBorderPainter({
    required this.accentColor,
    required this.dimColor,
    required this.bgColor,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    canvas.drawRRect(rRect, Paint()..color = bgColor);

    final gradientShader = LinearGradient(
      stops: const [0.0, 0.35, 0.65, 1.0],
      colors: [
        accentColor,
        accentColor,
        dimColor,
        dimColor,
      ],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRRect(
      rRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = gradientShader,
    );
  }

  @override
  bool shouldRepaint(_SkillCardBorderPainter old) =>
      old.accentColor != accentColor ||
      old.dimColor != dimColor ||
      old.bgColor != bgColor;
}

// ── FAQ list 
class _FaqList extends StatelessWidget {
  final List<Map<String, String>> faq;
  final bool isEnglish;
  final ThemeData theme;

  const _FaqList({
    required this.faq,
    required this.isEnglish,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (faq.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          isEnglish ? 'No FAQ entries yet.' : '暂无问答。',
          style: TextStyle(
            fontSize: 13,
            color: theme.hintColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return Column(
      children: faq.map((item) => _FaqRow(
            item: item,
            isEnglish: isEnglish,
            theme: theme,
          )).toList(),
    );
  }
}

class _FaqRow extends StatefulWidget {
  final Map<String, String> item;
  final bool isEnglish;
  final ThemeData theme;

  const _FaqRow({
    required this.item,
    required this.isEnglish,
    required this.theme,
  });

  @override
  State<_FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<_FaqRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.isEnglish
        ? (widget.item['q_en'] ?? '')
        : (widget.item['q_cn'] ?? widget.item['q_en'] ?? '');
    final a = widget.isEnglish
        ? (widget.item['a_en'] ?? '')
        : (widget.item['a_cn'] ?? widget.item['a_en'] ?? '');

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFFFC847).withValues(alpha: 0.75),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    q,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: widget.theme.colorScheme.onSurface
                          .withValues(alpha: 0.65),
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: widget.theme.hintColor.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 12),
            child: Text(
              a,
              style: TextStyle(
                fontSize: 13,
                height: 1.65,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF86EFAC).withValues(alpha: 0.85),
              ),
            ),
          ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 240),
          sizeCurve: Curves.easeInOut,
        ),
        Divider(
          height: 1,
          color: widget.theme.colorScheme.outlineVariant
              .withValues(alpha: 0.25),
        ),
      ],
    );
  }
}


// ── Small shared widgets
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 2.8,
            color: Theme.of(context).hintColor.withValues(alpha: 0.55),
          ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Divider(
        height: 1,
        color: Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.35),
      ),
    );
  }
}

class _MicroLabel extends StatelessWidget {
  final String label;
  const _MicroLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 9,
            letterSpacing: 2.8,
            color: Theme.of(context).hintColor.withValues(alpha: 0.4),
          ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SkillTypeBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SkillTypeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _TraitChip extends StatelessWidget {
  final String label;
  final ThemeData theme;
  const _TraitChip({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.52),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _RelatedCardChip extends StatelessWidget {
  final String label;
  final String category;
  final bool isDark;
  final VoidCallback onTap;

  const _RelatedCardChip({
    required this.label,
    required this.category,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(category, isDark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.0),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios_rounded, size: 10, color: color),
          ],
        ),
      ),
    );
  }
}

class _RelatedSkillChip extends StatelessWidget {
  final String label;
  const _RelatedSkillChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ), // TabBar
    ); // Theme
  }
}