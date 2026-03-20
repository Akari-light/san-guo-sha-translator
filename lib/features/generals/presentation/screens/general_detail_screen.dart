import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../data/models/skin_dto.dart';
import '../../data/repository/general_loader.dart';
import '../../data/repository/skin_loader.dart';
import '../../../../core/models/skill_dto.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/services/resolver_service.dart';
import '../../../../core/constants/app_assets.dart';

class GeneralDetailScreen extends StatefulWidget {
  final GeneralCard card;
  final void Function(String libraryCardId)? onLibraryCardTap;

  const GeneralDetailScreen({
    super.key,
    required this.card,
    this.onLibraryCardTap,
  });

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

  // ── Skins (alt-art for active variant)
  List<SkinDTO> _skins = [];
  int _skinIndex = 0; // 0 = base card image; 1..n = skins[0..n-1]

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
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Initial load — all sources run in parallel, one setState at the end.
  Future<void> _loadAll() async {
    final results = await Future.wait([
      GeneralLoader().getVariants(_activeCard.standardId),
      PinService.instance.isPinned(_activeCard.id, PinType.general),
      ResolverService().resolveGeneralSkills(_activeCard.skills, isChinese: true),
      ResolverService().resolveGeneralSkills(_activeCard.skills, isChinese: false),
      SkinLoader().getSkinsForBase(_activeCard.id),
    ]);
    if (!mounted) return;
    final variants = results[0] as List<GeneralCard>;
    setState(() {
      _variants = variants
        ..sort((a, b) => a.expansion.index.compareTo(b.expansion.index));
      _variantsLoading = false;
      _isPinned        = results[1] as bool;
      _refsCn          = results[2] as List<ResolvedReference>;
      _refsEn          = results[3] as List<ResolvedReference>;
      _refsLoading     = false;
      _skins           = results[4] as List<SkinDTO>;
      _skinIndex       = 0;
    });
  }

  // ── Version switch — reload refs, pin state, and skins for the new variant.
  Future<void> _loadPinState() async {
    final pinned = await PinService.instance.isPinned(_activeCard.id, PinType.general);
    if (!mounted) return;
    setState(() => _isPinned = pinned);
  }

  Future<void> _resolveRefs() async {
    final results = await Future.wait([
      ResolverService().resolveGeneralSkills(_activeCard.skills, isChinese: true),
      ResolverService().resolveGeneralSkills(_activeCard.skills, isChinese: false),
    ]);
    if (!mounted) return;
    setState(() {
      _refsCn      = results[0];
      _refsEn      = results[1];
      _refsLoading = false;
    });
  }

  Future<void> _loadSkins() async {
    final skins = await SkinLoader().getSkinsForBase(_activeCard.id);
    if (!mounted) return;
    setState(() {
      _skins     = skins;
      _skinIndex = 0;
    });
  }

  // ── Actions
  void _switchVersion(GeneralCard next) {
    if (next.id == _activeCard.id) return;
    setState(() {
      _activeCard  = next;
      _refsEn      = [];
      _refsCn      = [];
      _refsLoading = true;
      _skins       = [];
      _skinIndex   = 0;
      _tabController.index = 0;
    });
    _loadPinState();
    _resolveRefs();
    _loadSkins();
  }

  String get _activeImagePath {
    if (_skinIndex == 0 || _skins.isEmpty) return _activeCard.imagePath;
    return _skins[_skinIndex - 1].imagePath;
  }

  Future<void> _togglePin() async {
    final nowPinned = await PinService.instance.toggle(_activeCard.id, PinType.general);
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
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card   = _activeCard;
    final fc     = AppTheme.factionColor(card.faction);
    final refs   = _isEnglish ? _refsEn : _refsCn;

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

                  // Card image — receives the resolved path so it displays either the base art or a skin without knowing about SkinDTO.
                  _CardImage(
                    imagePath: _activeImagePath,
                    factionColor: fc,
                  ),

                  const SizedBox(width: 18),

                  // Identity column — skin button lives inside here, below gender
                  Expanded(
                    child: _IdentityColumn(
                      card: card,
                      isEnglish: _isEnglish,
                      factionColor: fc,
                      isDark: isDark,
                      hasSkins: _skins.isNotEmpty,
                      skinIndex: _skinIndex,
                      skins: _skins,
                      baseImagePath: card.imagePath,
                      onSelectSkin: _skins.isNotEmpty
                          ? (i) => setState(() => _skinIndex = i)
                          : null,
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Lang toggle — bottom-aligned with card image
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

            const _Divider(),

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
              const _Divider(),
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

            // Tab body
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

            const _Divider(),

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
                      ref.id != null) {
                    return _RelatedCardChip(
                      label: _isEnglish
                          ? ref.nameEn
                          : ref.nameCn,
                      category: ref.categoryEn ?? '',
                      isDark: isDark,
                      onTap: () =>
                          widget.onLibraryCardTap?.call(ref.id!),
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

// Card image (Receives a pre-resolved [imagePath] — stateless, no knowledge of SkinDTO.)
class _CardImage extends StatelessWidget {
  final String imagePath;
  final Color factionColor;

  const _CardImage({required this.imagePath, required this.factionColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: factionColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: factionColor.withValues(alpha: 0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: factionColor.withValues(alpha: 0.2),
            blurRadius: 32,
            spreadRadius: 4,
          ),
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
          imagePath,
          width: 160,
          height: 240,
          fit: BoxFit.cover,
          errorBuilder: (context, _, _) => Image.asset(
            AppAssets.generalPlaceholder,
            width: 160,
            height: 240,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

// Identity column — name, faction, health, power, gender, skin button
class _IdentityColumn extends StatelessWidget {
  final GeneralCard card;
  final bool isEnglish;
  final Color factionColor;
  final bool isDark;

  // Skin strip props — only rendered when [hasSkins] is true
  final bool hasSkins;
  final int skinIndex;
  final List<SkinDTO> skins;
  final String baseImagePath;
  final void Function(int)? onSelectSkin;

  const _IdentityColumn({
    required this.card,
    required this.isEnglish,
    required this.factionColor,
    required this.isDark,
    required this.hasSkins,
    required this.skinIndex,
    required this.skins,
    required this.baseImagePath,
    required this.onSelectSkin,
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

        // Health
        _MicroLabel(label: isEnglish ? 'Health' : '体力'),
        const SizedBox(height: 6),
        _HealthPips(health: card.health),

        const SizedBox(height: 12),

        // Power
        _MicroLabel(label: isEnglish ? 'Power' : '战力'),
        const SizedBox(height: 6),
        _PowerStars(value: card.powerIndex),

        const SizedBox(height: 12),

        // Gender
        Text(
          card.gender == 'Female'
              ? (isEnglish ? '♀  Female' : '♀  女')
              : (isEnglish ? '♂  Male' : '♂  男'),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            color: card.gender == 'Female'
                ? const Color(0xFFF9A8D4)
                : const Color(0xFF93C5FD),
            fontWeight: FontWeight.w600,
          ),
        ),

        // Skin thumbnail strip — hidden when no skins exist
        if (hasSkins) ...[
          const SizedBox(height: 10),
          _SkinThumbnailStrip(
            skinIndex: skinIndex,
            skins: skins,
            baseImagePath: baseImagePath,
            factionColor: factionColor,
            isEnglish: isEnglish,
            onSelect: onSelectSkin,
          ),
        ],
      ],
    );
  }
}

// Skin thumbnail strip.
// Shows every slot EXCEPT the one currently displayed on the main card.
// Slot 0 = base art (_activeCard.imagePath), slots 1..n = skins[0..n-1].
// Tapping a thumbnail swaps it onto the main card and the previously active
// slot takes the vacated thumbnail position.
class _SkinThumbnailStrip extends StatelessWidget {
  final int skinIndex;
  final List<SkinDTO> skins;
  final String baseImagePath;
  final Color factionColor;
  final bool isEnglish;
  final void Function(int)? onSelect;

  const _SkinThumbnailStrip({
    required this.skinIndex,
    required this.skins,
    required this.baseImagePath,
    required this.factionColor,
    required this.isEnglish,
    required this.onSelect,
  });

  // Resolve the image path for any slot index.
  // Slot 0 → base card art; slot k → skins[k-1].imagePath.
  String _pathForSlot(int i) =>
      i == 0 ? baseImagePath : skins[i - 1].imagePath;

  // Human-readable label for any slot index.
  String _labelForSlot(int i) => i == 0
      ? (isEnglish ? 'Original' : '原版')
      : (isEnglish ? skins[i - 1].nameEn : skins[i - 1].nameCn);

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final totalSlots = 1 + skins.length;

    // Build the list of slot indices that are NOT currently active.
    final others = [
      for (int i = 0; i < totalSlots; i++)
        if (i != skinIndex) i,
    ];

    // Label shown below the strip — name of the currently active slot.
    final activeLabel = _labelForSlot(skinIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Thumbnail row — one tile per non-active slot ───────────────────
        Row(
          mainAxisSize: MainAxisSize.min,
          children: others.asMap().entries.map((entry) {
            final pos      = entry.key;   // position in the rendered row
            final slotIdx  = entry.value; // actual slot index (0 = base, 1..n = skins)
            final isLast   = pos == others.length - 1;

            return GestureDetector(
              onTap: onSelect != null ? () => onSelect!(slotIdx) : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 50,
                margin: EdgeInsets.only(right: isLast ? 0 : 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: factionColor.withValues(alpha: 0.30),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.asset(
                    _pathForSlot(slotIdx),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: factionColor.withValues(alpha: 0.08),
                      child: Icon(
                        slotIdx == 0
                            ? Icons.star_rounded
                            : Icons.auto_awesome_rounded,
                        size: 14,
                        color: factionColor.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        // ── Active slot label ──────────────────────────────────────────────
        const SizedBox(height: 7),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                activeLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: factionColor.withValues(alpha: 0.8),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${skinIndex + 1}/$totalSlots',
              style: TextStyle(
                fontSize: 10,
                color: theme.hintColor.withValues(alpha: 0.4),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Lang toggle (vertical EN/中 with animated arrow + radial glow)
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
            _GlowLabel(
              text: 'EN',
              active: isEnglish,
              accentColor: factionColor,
              fontSize: 11,
              letterSpacing: 1.0,
            ),
            const SizedBox(height: 6),
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
            _GlowLabel(
              text: '中',
              active: !isEnglish,
              accentColor: factionColor,
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
  final Color accentColor;
  final double fontSize;
  final double letterSpacing;

  const _GlowLabel({
    required this.text,
    required this.active,
    required this.accentColor,
    required this.fontSize,
    required this.letterSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  accentColor.withValues(alpha: 0.32),
                  accentColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: letterSpacing,
            color: active
                ? accentColor
                : theme.hintColor.withValues(alpha: 0.4),
          ),
          child: Text(text),
        ),
      ],
    );
  }
}

// Health pips
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

// Power stars (split-half per star, 0.5 increments clearly distinct)
class _PowerStars extends StatelessWidget {
  final double value;
  const _PowerStars({required this.value});

  static const Color _goldColor = AppTheme.skillLord;
  static const Color _dimColor  = Color(0x22888888);

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
              const Center(
                child: Text(
                  '★',
                  style: TextStyle(fontSize: 18, color: _dimColor, height: 1),
                ),
              ),
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

// Version segment control
//
// Layout:
//   1. Expansion tab row — one tab per unique expansion, dots = within-expansion
//      variant count (1 dot = single variant, 3 dots = 3 variants).
//   2. Sub-variant rail — only rendered when the active expansion tab has
//      more than one variant. Shows a step rail with numbered nodes and
//      labels (ID + short name) so the user can pick between within-expansion
//      variants without leaving the screen.
//   3. Meta line — "Expansion name · N skills" always visible below.
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
    final theme  = Theme.of(context);
    final active = variants.firstWhere((v) => v.id == activeId);
    final ec     = AppTheme.expansionColor(active.expansion);

    // ── Group variants by expansion, preserving sort order.
    // Each group is a list of GeneralCards sharing the same expansion.
    final Map<String, List<GeneralCard>> groups = {};
    for (final v in variants) {
      groups.putIfAbsent(v.expansion.labelEn, () => []).add(v);
    }
    // The tab list: one entry per unique expansion (in original sort order).
    final expansionKeys = groups.keys.toList();

    // Within-expansion siblings of the active card.
    final siblings = groups[active.expansion.labelEn] ?? [active];
    final hasSubVariants = siblings.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Expansion tab row ──────────────────────────────────────────────
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
            children: expansionKeys.map((key) {
              final group    = groups[key]!;
              final first    = group.first;
              final tabEc    = AppTheme.expansionColor(first.expansion);
              final isActive = group.any((v) => v.id == activeId);
              final dotCount = group.length; // dots = within-expansion variant count

              return Expanded(
                child: GestureDetector(
                  // Tapping the tab selects the first card in that group
                  // (or keeps current if already active).
                  onTap: () => onSelect(
                    isActive ? active : group.first,
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isActive
                          ? tabEc.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? tabEc.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 220),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: isActive
                                ? tabEc
                                : theme.hintColor.withValues(alpha: 0.35),
                          ),
                          child: Text(
                            first.expansionBadge,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // Dots = within-expansion variant count.
                        // Only shown when there are multiple variants; capped at 5.
                        if (dotCount > 1)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              dotCount.clamp(1, 5),
                              (i) => Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(right: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive
                                      ? tabEc
                                      : tabEc.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                          )
                        else
                          // Single variant — render invisible dot to keep
                          // tab height consistent across all tabs.
                          const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Sub-variant step rail ──────────────────────────────────────────
        // Only rendered when the active expansion has >1 variant.
        // Siblings reversed so base card is rightmost.
        // Uses a LayoutBuilder so nodes spread across the full container width
        // (matching the version tab row above). Only scrolls if > 5 variants.
        if (hasSubVariants) ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final containerWidth = constraints.maxWidth;
              final n = siblings.length;
              // Minimum gap between node edges before we switch to scrolling.
              const minGap = 16.0;
              const nodeSize = _SubVariantRail.nodeSize;
              final naturalSpacing = (containerWidth - nodeSize) / (n - 1);
              final needsScroll = naturalSpacing < nodeSize + minGap;

              final rail = _SubVariantRail(
                siblings: siblings.reversed.toList(),
                activeId: activeId,
                expansionColor: ec,
                onSelect: onSelect,
                fixedWidth: needsScroll ? null : containerWidth,
              );

              if (needsScroll) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: rail,
                );
              }
              return rail;
            },
          ),
        ],

        const SizedBox(height: 8),

        // ── Meta line: expansion label · skill count ───────────────────────
        Row(
          children: [
            Text(
              isEnglish ? active.expansion.labelEn : active.expansion.labelCn,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: ec,
              ),
            ),
            Text(
              '  ·  ',
              style: TextStyle(
                fontSize: 13,
                color: theme.hintColor.withValues(alpha: 0.3),
              ),
            ),
            Text(
              '${active.skills.length} ${isEnglish ? "skill" : "技能"}'
              '${isEnglish && active.skills.length != 1 ? "s" : ""}',
              style: TextStyle(
                fontSize: 13,
                color: theme.hintColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Step-rail sub-selector for within-expansion variants.
//
// Renders a horizontal rail of numbered nodes connected by lines.
// The active node is filled with the expansion colour; inactive nodes
// are outlined. Each node sits above a label showing the card ID and
// a shortened display name.
//
// Short-name rule: if name_cn/name_en contains '·', use the text AFTER
// the last '·' as the label (e.g. "虎牢关神吕布·最强神话" → "最强神话").
// Otherwise use the full name.
// Animated step-rail sub-selector for within-expansion variants.
//
/// Sub-variant step rail.
///
/// Visual design:
/// • One static full-span background rail (dim colour) drawn first (lowest z).
/// • Per-gap overlay segments drawn on top of the background:
///     - Gap touching the active node → gradient fade (expansion colour at
///       the active end, transparent at the far end).
///     - All other gaps → transparent (background rail shows through).
/// • Nodes drawn last (highest z) so they always sit solidly on the rail.
///     - Active node: full-opacity image, expansion-colour border ring,
///       solid expansion-colour circle background behind the image.
///     - Inactive nodes: dimmed image, dim border.
class _SubVariantRail extends StatelessWidget {
  final List<GeneralCard> siblings;
  final String activeId;
  final Color expansionColor;
  final ValueChanged<GeneralCard> onSelect;
  /// When non-null, nodes are spread to fill this exact width (matches the
  /// version tab row). When null, fixed scroll-mode gap is used.
  final double? fixedWidth;

  static const double nodeSize      = 54.0;   // was 46 — larger for readability
  static const double _railHeight   = 2.5;
  static const double _scrollGap    = 28.0;

  const _SubVariantRail({
    required this.siblings,
    required this.activeId,
    required this.expansionColor,
    required this.onSelect,
    this.fixedWidth,
  });

  // Left edge of node i.
  double _nodeLeft(int i, int n) {
    if (fixedWidth != null) {
      return (i + 0.5) / n * fixedWidth! - nodeSize / 2;
    }
    return i * (nodeSize + _scrollGap);
  }

  // Horizontal centre of node i.
  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final isDark     = theme.brightness == Brightness.dark;
    final ec         = expansionColor;
    final dimColor   = theme.colorScheme.outlineVariant
        .withValues(alpha: isDark ? 0.25 : 0.30);

    final n          = siblings.length;
    final activeIdx  = siblings.indexWhere((s) => s.id == activeId);
    final stackWidth = fixedWidth
        ?? (n * nodeSize + (n - 1) * _scrollGap);
    final railTop    = (nodeSize - _railHeight) / 2;

    // Rail runs from the RIGHT edge of node 0 to the LEFT edge of node n-1.
    // This means the line is only ever visible in the gaps between nodes —
    // it never overlaps any circle.
    final railLeft  = _nodeLeft(0, n) + nodeSize;          // right edge of first node
    final railRight = _nodeLeft(n - 1, n);                 // left edge of last node
    final railWidth = (railRight - railLeft).clamp(0.0, double.infinity);

    // Helper: right edge of node i
    double rightEdge(int i) => _nodeLeft(i, n) + nodeSize;
    // Helper: left edge of node i
    double leftEdge(int i)  => _nodeLeft(i, n);

    return SizedBox(
      width:  stackWidth,
      height: nodeSize + 6 + 30,   // +30 for larger label
      child: Stack(
        clipBehavior: Clip.none,
        children: [

          // ── 1. Background rail — edge-to-edge, dim, lowest z
          //       Starts at right edge of node 0, ends at left edge of node n-1.
          //       Never overlaps any node circle.
          Positioned(
            left:   railLeft,
            width:  railWidth,
            top:    railTop,
            height: _railHeight,
            child: Container(
              decoration: BoxDecoration(
                color: dimColor,
                borderRadius: BorderRadius.circular(_railHeight / 2),
              ),
            ),
          ),

          // ── 2. Gradient overlay segments adjacent to the active node
          //       Each gradient also runs edge-to-edge between the two nodes.
          //       Left gap: right edge of (activeIdx-1) → left edge of activeIdx
          //       Right gap: right edge of activeIdx → left edge of (activeIdx+1)
          if (activeIdx > 0)
            _gradientSegment(
              left:      rightEdge(activeIdx - 1),
              right:     leftEdge(activeIdx),
              top:       railTop,
              fromColor: dimColor,
              toColor:   ec,
            ),
          if (activeIdx < n - 1)
            _gradientSegment(
              left:      rightEdge(activeIdx),
              right:     leftEdge(activeIdx + 1),
              top:       railTop,
              fromColor: ec,
              toColor:   dimColor,
            ),

          // ── 3. Nodes — highest z, fully opaque background so rail never shows through
          ...siblings.asMap().entries.map((entry) {
            final idx      = entry.key;
            final sibling  = entry.value;
            final isActive = sibling.id == activeId;

            return Positioned(
              left: _nodeLeft(idx, n),
              top:  0,
              child: GestureDetector(
                onTap: () => onSelect(sibling),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: nodeSize,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        width:  nodeSize,
                        height: nodeSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // Solid scaffold colour behind the image prevents
                          // the rail from ever bleeding through the circle.
                          color: theme.scaffoldBackgroundColor,
                          border: Border.all(
                            color: isActive ? ec : dimColor,
                            width: isActive ? 2.5 : 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: AnimatedOpacity(
                            opacity: isActive ? 1.0 : 0.45,
                            duration: const Duration(milliseconds: 220),
                            child: Image.asset(
                              sibling.imagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: isActive
                                    ? ec.withValues(alpha: 0.25)
                                    : dimColor.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.person_outline_rounded,
                                  size: 24,
                                  color: (isActive ? ec : dimColor)
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        sibling.id,
                        style: TextStyle(
                          fontSize: 10,         // was 9
                          letterSpacing: 0.3,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isActive
                              ? ec
                              : theme.hintColor.withValues(alpha: 0.4),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// A horizontal gradient segment running from [left] centre to [right] centre.
  Widget _gradientSegment({
    required double left,
    required double right,
    required double top,
    required Color fromColor,
    required Color toColor,
  }) {
    return Positioned(
      left:   left,
      width:  right - left,
      top:    top,
      height: _railHeight,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_railHeight / 2),
          gradient: LinearGradient(
            colors: [fromColor, toColor],
          ),
        ),
      ),
    );
  }
}

// Skills/FAQ tab bar
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
          fontSize: 13,
          letterSpacing: 2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13,
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
                    fontSize: 13,
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
      ),
    );
  }
}

// Skill card (collapsible, gradient border fading left→right)
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
      behavior: HitTestBehavior.opaque,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.isEnglish
                          ? widget.skill.nameEn
                          : widget.skill.nameCn,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
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
                        height: 1.7,
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
      colors: [accentColor, accentColor, dimColor, dimColor],
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

// FAQ list
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
      children: faq
          .map((item) => _FaqRow(item: item, isEnglish: isEnglish, theme: theme))
          .toList(),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppTheme.skillLord.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    q,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: widget.theme.colorScheme.onSurface
                          .withValues(alpha: 0.65),
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
                fontSize: 14,
                height: 1.6,
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
          color: widget.theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.0,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

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
        color: color.withValues(alpha: 0.14),
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
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.3,
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
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.transparent,
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
      ),
    );
  }
}