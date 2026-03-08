import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/constants/app_assets.dart';

class LibraryDetailScreen extends StatefulWidget {
  final LibraryDTO card;
  const LibraryDetailScreen({super.key, required this.card});

  @override
  State<LibraryDetailScreen> createState() => _LibraryDetailScreenState();
}

class _LibraryDetailScreenState extends State<LibraryDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _isEnglish = true;
  bool _isPinned  = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPinState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPinState() async {
    final pinned = await PinService.instance.isPinned(widget.card.id, PinType.library);
    if (!mounted) return;
    setState(() => _isPinned = pinned);
  }

  Future<void> _togglePin() async {
    final nowPinned =
        await PinService.instance.toggle(widget.card.id, PinType.library);
    if (!mounted) return;
    setState(() => _isPinned = nowPinned);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(nowPinned
          ? '${widget.card.nameEn} pinned to Home'
          : '${widget.card.nameEn} unpinned'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final card   = widget.card;
    final cc     = AppTheme.categoryColor(card.categoryEn, isDark);

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
              color: _isPinned ? cc : null,
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

            // ── Card image (portrait or landscape for time-delay tools)
            _CardImage(card: card, categoryColor: cc),

            const SizedBox(height: 22),

            // ── Identity row: [name / badges / range] + [lang toggle]
            // The lang toggle is top-aligned next to the left column,
            // so it always sits beside the name regardless of how many
            // badge rows or range rows appear below.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _IdentityColumn(
                      card: card,
                      isEnglish: _isEnglish,
                      categoryColor: cc,
                    ),
                  ),
                  const SizedBox(width: 14),
                  _LangToggle(
                    isEnglish: _isEnglish,
                    categoryColor: cc,
                    onToggle: () => setState(() => _isEnglish = !_isEnglish),
                  ),
                ],
              ),
            ),

            const _Divider(),

            // ── Effect / FAQ tab bar
            _LibTabBar(
              controller: _tabController,
              faqCount:   card.faq.length,
              categoryColor: cc,
              isEnglish:  _isEnglish,
              theme:      theme,
            ),

            const SizedBox(height: 16),

            // ── Tab body
            ListenableBuilder(
              listenable: _tabController,
              builder: (context, _) {
                if (_tabController.index == 0) {
                  return _EffectBody(
                    card:      card,
                    isEnglish: _isEnglish,
                    isDark:    isDark,
                    theme:     theme,
                  );
                } else {
                  return _FaqList(
                    faq:       card.faq,
                    isEnglish: _isEnglish,
                    theme:     theme,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card image ────────────────────────────────────────────────────────────────
class _CardImage extends StatelessWidget {
  final LibraryDTO card;
  final Color categoryColor;

  const _CardImage({required this.card, required this.categoryColor});

  @override
  Widget build(BuildContext context) {
    final isHoriz = card.isHorizontal;
    final double w = isHoriz ? 240 : 160;
    final double h = isHoriz ? 160 : 240;

    return Center(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: categoryColor, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: categoryColor.withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: categoryColor.withValues(alpha: 0.18),
              blurRadius: 36,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.5),
          child: Image.asset(
            card.imagePath,
            width: w,
            height: h,
            fit: BoxFit.cover,
            errorBuilder: (context, error, _) => Image.asset(
              AppAssets.libraryPlaceholder,
              width: w,
              height: h,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Identity column (name, category badge, optional sub-category, range) ──────
class _IdentityColumn extends StatelessWidget {
  final LibraryDTO card;
  final bool isEnglish;
  final Color categoryColor;

  const _IdentityColumn({
    required this.card,
    required this.isEnglish,
    required this.categoryColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name   = isEnglish ? card.nameEn    : card.nameCn;
    final cat    = isEnglish ? card.categoryEn : card.categoryCn;
    final subCat = isEnglish ? card.subCategoryEn : card.subCategoryCn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Name
        Text(
          name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize:      isEnglish ? 24 : 22,
            letterSpacing: isEnglish ? -0.3 : 1.5,
            height: 1.15,
          ),
        ),

        const SizedBox(height: 10),

        // Badge row: category  [|  sub-category]  [range badge]
        Wrap(
          spacing: 7,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [

            // Category badge (coloured)
            _Badge(label: cat, color: categoryColor),

            // Sub-category badge (neutral)
            if (subCat != null) ...[
              Text(
                '|',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.hintColor.withValues(alpha: 0.3),
                ),
              ),
              _NeutralBadge(label: subCat, theme: theme),
            ],

            // Range badge — lives in the tag row, Option C style
            if (card.range != null)
              _RangeBadge(
                range:     card.range!,
                color:     AppTheme.statBadgeColor,
                isDark:    isDark,
                isEnglish: isEnglish,
              ),
          ],
        ),
      ],
    );
  }
}

// ── Lang toggle — identical structure to GeneralDetailScreen ──────────────────
// Uses categoryColor instead of factionColor. The active label glows in
// category color; inactive label uses theme.hintColor so it stays visible
// in both light and dark mode (no hardcoded white).
class _LangToggle extends StatelessWidget {
  final bool isEnglish;
  final Color categoryColor;
  final VoidCallback onToggle;

  const _LangToggle({
    required this.isEnglish,
    required this.categoryColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlowLabel(
              text: 'EN',
              active: isEnglish,
              accentColor: categoryColor,
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
                color: categoryColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            _GlowLabel(
              text: '中',
              active: !isEnglish,
              accentColor: categoryColor,
              fontSize: 13,
              letterSpacing: 0,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Glow label — theme-aware: inactive uses hintColor, not hardcoded white ────
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
        // Radial glow — only shown when active
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
        // Label text — theme-aware inactive colour
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          style: TextStyle(
            fontSize:      fontSize,
            fontWeight:    FontWeight.w700,
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

// ── Tab bar ───────────────────────────────────────────────────────────────────
class _LibTabBar extends StatelessWidget {
  final TabController controller;
  final int faqCount;
  final Color categoryColor;
  final bool isEnglish;
  final ThemeData theme;

  const _LibTabBar({
    required this.controller,
    required this.faqCount,
    required this.categoryColor,
    required this.isEnglish,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme.copyWith(
        highlightColor: Colors.transparent,
        splashColor:    Colors.transparent,
        splashFactory:  NoSplash.splashFactory,
      ),
      child: TabBar(
        controller:           controller,
        indicatorColor:       categoryColor,
        indicatorSize:        TabBarIndicatorSize.label,
        labelColor:           categoryColor,
        unselectedLabelColor: theme.hintColor,
        overlayColor:         WidgetStateProperty.all(Colors.transparent),
        splashFactory:        NoSplash.splashFactory,
        dividerColor:
            theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        labelStyle: const TextStyle(
          fontWeight:    FontWeight.w700,
          fontSize:      13,
          letterSpacing: 2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight:    FontWeight.w400,
          fontSize:      13,
          letterSpacing: 2,
        ),
        tabs: [
          Tab(text: isEnglish ? 'EFFECT' : '效果'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEnglish ? 'FAQ' : '问答',
                  style: const TextStyle(
                    fontWeight:    FontWeight.w700,
                    fontSize:      13,
                    letterSpacing: 2,
                  ),
                ),
                if (faqCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color:  categoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: categoryColor.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '$faqCount',
                      style: TextStyle(
                        fontSize:   9,
                        fontWeight: FontWeight.w700,
                        color:      categoryColor,
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

// ── Effect tab body ───────────────────────────────────────────────────────────
class _EffectBody extends StatelessWidget {
  final LibraryDTO card;
  final bool isEnglish;
  final bool isDark;
  final ThemeData theme;

  const _EffectBody({
    required this.card,
    required this.isEnglish,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final text = isEnglish
        ? card.effectEn.join('\n\n')
        : card.effectCn.join('\n\n');

    final textColor = isDark
        ? (isEnglish ? AppTheme.descriptionEnDark : AppTheme.descriptionCnDark)
        : theme.textTheme.bodyLarge?.color;

    return Text(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(
        height: 1.7,
        color: textColor,
        fontStyle: isEnglish ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}

// ── FAQ list (collapsible rows) ───────────────────────────────────────────────
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
          isEnglish ? 'No FAQ entries.' : '暂无问答。',
          style: TextStyle(
            fontSize:  13,
            fontStyle: FontStyle.italic,
            color:     theme.hintColor,
          ),
        ),
      );
    }
    return Column(
      children: faq
          .map((f) => _FaqRow(item: f, isEnglish: isEnglish, theme: theme))
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
                // Q badge
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
                      height:   1.6,
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
                  size:  16,
                  color: widget.theme.hintColor.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild:  const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 12),
            child: Text(
              a,
              style: TextStyle(
                fontSize:  14,
                height:    1.6,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF86EFAC).withValues(alpha: 0.85),
              ),
            ),
          ),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration:  const Duration(milliseconds: 240),
          sizeCurve: Curves.easeInOut,
        ),
        Divider(
          height: 1,
          color:  widget.theme.colorScheme.outlineVariant
              .withValues(alpha: 0.25),
        ),
      ],
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

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

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color:      color,
          fontSize:   13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NeutralBadge extends StatelessWidget {
  final String label;
  final ThemeData theme;
  const _NeutralBadge({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:   13,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// Range badge — sword icon + label + number, same row as category badge.
class _RangeBadge extends StatelessWidget {
  final int range;
  final Color color;
  final bool isDark;
  final bool isEnglish;

  const _RangeBadge({
    required this.range,
    required this.color,
    required this.isDark,
    required this.isEnglish,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.straighten_rounded, size: 17.5, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            isEnglish ? 'Range' : '距离',
            style: TextStyle(
              fontSize:      12.5,
              letterSpacing: 1.5,
              fontWeight:    FontWeight.w600,
              color: color.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$range',
            style: TextStyle(
              fontSize:   14,
              fontWeight: FontWeight.w900,
              color:      color,
              height:     1,
            ),
          ),
        ],
      ),
    );
  }
}