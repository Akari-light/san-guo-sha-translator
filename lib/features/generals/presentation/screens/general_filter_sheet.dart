import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../../../core/theme/app_theme.dart';

// ── Filter State ─────────────────────────────────────────────────────────────

enum GeneralSortOrder {
  defaultOrder, // JSON order as entered
  nameAZ,
  nameZA,
  powerHighest,
  powerLowest,
  healthHighest,
  healthLowest;

  String get label {
    switch (this) {
      case GeneralSortOrder.defaultOrder:  return 'Default';
      case GeneralSortOrder.nameAZ:        return 'Name A→Z';
      case GeneralSortOrder.nameZA:        return 'Name Z→A';
      case GeneralSortOrder.powerHighest:  return 'Power ↓';
      case GeneralSortOrder.powerLowest:   return 'Power ↑';
      case GeneralSortOrder.healthHighest: return 'Health ↓';
      case GeneralSortOrder.healthLowest:  return 'Health ↑';
    }
  }
}

class GeneralFilterState {
  final Set<String> factions;
  final Set<Expansion> expansions;
  final bool lordOnly;
  final GeneralSortOrder sortOrder;

  const GeneralFilterState({
    this.factions = const {},
    this.expansions = const {},
    this.lordOnly = false,
    this.sortOrder = GeneralSortOrder.defaultOrder,
  });

  bool get isActive =>
      factions.isNotEmpty ||
      expansions.isNotEmpty ||
      lordOnly ||
      sortOrder != GeneralSortOrder.defaultOrder;

  GeneralFilterState copyWith({
    Set<String>? factions,
    Set<Expansion>? expansions,
    bool? lordOnly,
    GeneralSortOrder? sortOrder,
  }) {
    return GeneralFilterState(
      factions: factions ?? this.factions,
      expansions: expansions ?? this.expansions,
      lordOnly: lordOnly ?? this.lordOnly,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Applies this filter state to a list of generals.
  List<GeneralCard> apply(List<GeneralCard> all) {
    List<GeneralCard> result = all;

    if (factions.isNotEmpty) {
      result = result.where((g) => factions.contains(g.faction)).toList();
    }
    if (expansions.isNotEmpty) {
      result = result.where((g) => expansions.contains(g.expansion)).toList();
    }
    if (lordOnly) {
      result = result
          .where((g) => g.skills.any((s) => s.skillType.name == 'lord'))
          .toList();
    }

    switch (sortOrder) {
      case GeneralSortOrder.defaultOrder:
        break; // preserve JSON order
      case GeneralSortOrder.nameAZ:
        result.sort((a, b) => a.nameEn.compareTo(b.nameEn));
      case GeneralSortOrder.nameZA:
        result.sort((a, b) => b.nameEn.compareTo(a.nameEn));
      case GeneralSortOrder.powerHighest:
        result.sort((a, b) => b.powerIndex.compareTo(a.powerIndex));
      case GeneralSortOrder.powerLowest:
        result.sort((a, b) => a.powerIndex.compareTo(b.powerIndex));
      case GeneralSortOrder.healthHighest:
        result.sort((a, b) => b.health.compareTo(a.health));
      case GeneralSortOrder.healthLowest:
        result.sort((a, b) => a.health.compareTo(b.health));
    }

    return result;
  }
}

// ── Bottom Sheet ─────────────────────────────────────────────────────────────

class GeneralFilterSheet extends StatefulWidget {
  final GeneralFilterState initialState;
  final void Function(GeneralFilterState) onApply;

  const GeneralFilterSheet({
    super.key,
    required this.initialState,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    required GeneralFilterState initialState,
    required void Function(GeneralFilterState) onApply,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GeneralFilterSheet(
        initialState: initialState,
        onApply: onApply,
      ),
    );
  }

  @override
  State<GeneralFilterSheet> createState() => _GeneralFilterSheetState();
}

class _GeneralFilterSheetState extends State<GeneralFilterSheet>
    with SingleTickerProviderStateMixin {
  late GeneralFilterState _state;
  late TabController _tabController;

  static const List<String> _factions = ['Shu', 'Wei', 'Wu', 'Qun', 'God'];

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleFaction(String faction) {
    final updated = Set<String>.from(_state.factions);
    updated.contains(faction) ? updated.remove(faction) : updated.add(faction);
    setState(() => _state = _state.copyWith(factions: updated));
  }

  void _toggleExpansion(Expansion expansion) {
    final updated = Set<Expansion>.from(_state.expansions);
    updated.contains(expansion)
        ? updated.remove(expansion)
        : updated.add(expansion);
    setState(() => _state = _state.copyWith(expansions: updated));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Handle ───────────────────────────────────────────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.hintColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      'Filter & Sort',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    // Reset button
                    if (_state.isActive)
                      TextButton(
                        onPressed: () => setState(
                          () => _state = const GeneralFilterState(),
                        ),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                              color: theme.colorScheme.error),
                        ),
                      ),
                    // Apply button
                    FilledButton(
                      onPressed: () {
                        widget.onApply(_state);
                        Navigator.pop(context);
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),

              // ── Tab bar ──────────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Faction'),
                  Tab(text: 'Expansion'),
                  Tab(text: 'Sort'),
                ],
              ),

              // ── Tab content ──────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFactionTab(),
                    _buildExpansionTab(theme),
                    _buildSortTab(theme),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Faction tab ────────────────────────────────────────────────────────────

  Widget _buildFactionTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Lord only toggle — lives here since it's character-related
        _buildToggleTile(
          label: 'Lord Cards Only',
          sublabel: 'Show generals with a Lord skill',
          value: _state.lordOnly,
          onChanged: (v) =>
              setState(() => _state = _state.copyWith(lordOnly: v)),
        ),
        const SizedBox(height: 20),
        const Text('FACTION',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _factions
              .map((f) => _FactionFilterChip(
                    faction: f,
                    isSelected: _state.factions.contains(f),
                    onTap: () => _toggleFaction(f),
                  ))
              .toList(),
        ),
      ],
    );
  }

  // ── Expansion tab ──────────────────────────────────────────────────────────

  Widget _buildExpansionTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('EXPANSION',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        // One tile per expansion — add more as expansions are added
        for (final expansion in Expansion.values)
          _buildCheckTile(
            label: expansion.badge,
            sublabel: _expansionLabel(expansion),
            isSelected: _state.expansions.contains(expansion),
            onTap: () => _toggleExpansion(expansion),
            theme: theme,
          ),
      ],
    );
  }

  String _expansionLabel(Expansion expansion) {
    switch (expansion) {
      case Expansion.limitBreak: return '界限突破 — Limit Break';
    }
  }

  // ── Sort tab ───────────────────────────────────────────────────────────────

  Widget _buildSortTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('SORT BY',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        for (final order in GeneralSortOrder.values)
          _buildRadioTile(
            label: order.label,
            isSelected: _state.sortOrder == order,
            onTap: () =>
                setState(() => _state = _state.copyWith(sortOrder: order)),
            theme: theme,
          ),
      ],
    );
  }

  // ── Shared tile builders ───────────────────────────────────────────────────

  Widget _buildToggleTile({
    required String label,
    required String sublabel,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sublabel,
          style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildCheckTile({
    required String label,
    required String sublabel,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary)),
      ),
      title: Text(sublabel),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.circle_outlined),
      onTap: onTap,
    );
  }

  Widget _buildRadioTile({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: TextStyle(
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected
          ? Icon(Icons.radio_button_checked,
              color: theme.colorScheme.primary)
          : const Icon(Icons.radio_button_unchecked),
      onTap: onTap,
    );
  }
}

// ── Faction chip widget ───────────────────────────────────────────────────────

class _FactionFilterChip extends StatelessWidget {
  final String faction;
  final bool isSelected;
  final VoidCallback onTap;

  const _FactionFilterChip({
    required this.faction,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.factionColor(faction);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(
          faction,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}