import 'package:flutter/material.dart';
import '../../data/models/general_card.dart';
import '../../../../core/models/skill_dto.dart';
import '../../../../core/theme/app_theme.dart';

// ── Sort Order 
enum GeneralSortOrder {
  none,         // JSON order — no sort applied
  serialNumber, // By card ID: SHU001, SHU002...
  nameAZ,       // Alphabetical A → Z
  nameZA,       // Alphabetical Z → A
  powerHighest, // Power Index high → low
  powerLowest;  // Power Index low → high

  String get label {
    switch (this) {
      case GeneralSortOrder.none:         return 'None (Default)';
      case GeneralSortOrder.serialNumber: return 'Serial Number';
      case GeneralSortOrder.nameAZ:       return 'Name A → Z';
      case GeneralSortOrder.nameZA:       return 'Name Z → A';
      case GeneralSortOrder.powerHighest: return 'Power ↓ High to Low';
      case GeneralSortOrder.powerLowest:  return 'Power ↑ Low to High';
    }
  }
}

// ── Filter State 
class GeneralFilterState {
  final Set<String> factions;
  final Set<Expansion> expansions;
  final bool lordOnly;
  final GeneralSortOrder sortOrder;

  const GeneralFilterState({
    this.factions = const {},
    this.expansions = const {},
    this.lordOnly = false,
    this.sortOrder = GeneralSortOrder.none,
  });

  bool get isActive =>
      factions.isNotEmpty ||
      expansions.isNotEmpty ||
      lordOnly ||
      sortOrder != GeneralSortOrder.none;

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

  /// Applies filters then sort to a list of generals.
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
          .where((g) => g.skills.any((s) => s.skillType == SkillType.lord))
          .toList();
    }

    switch (sortOrder) {
      case GeneralSortOrder.none:
        break; // preserve JSON order
      case GeneralSortOrder.serialNumber:
        result.sort((a, b) => a.id.compareTo(b.id));
      case GeneralSortOrder.nameAZ:
        result.sort((a, b) => a.nameEn.compareTo(b.nameEn));
      case GeneralSortOrder.nameZA:
        result.sort((a, b) => b.nameEn.compareTo(a.nameEn));
      case GeneralSortOrder.powerHighest:
        result.sort((a, b) => b.powerIndex.compareTo(a.powerIndex));
      case GeneralSortOrder.powerLowest:
        result.sort((a, b) => a.powerIndex.compareTo(b.powerIndex));
    }

    return result;
  }
}

// ── Bottom Sheet 
class GeneralFilterSheet extends StatefulWidget {
  final GeneralFilterState initialState;
  final void Function(GeneralFilterState) onChanged;

  const GeneralFilterSheet({
    super.key,
    required this.initialState,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required GeneralFilterState initialState,
    required void Function(GeneralFilterState) onChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GeneralFilterSheet(
        initialState: initialState,
        onChanged: onChanged,
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

  void _update(GeneralFilterState newState) {
    setState(() => _state = newState);
    widget.onChanged(newState);
  }

  void _toggleFaction(String faction) {
    final updated = Set<String>.from(_state.factions);
    updated.contains(faction) ? updated.remove(faction) : updated.add(faction);
    _update(_state.copyWith(factions: updated));
  }

  void _toggleExpansion(Expansion expansion) {
    final updated = Set<Expansion>.from(_state.expansions);
    updated.contains(expansion)
        ? updated.remove(expansion)
        : updated.add(expansion);
    _update(_state.copyWith(expansions: updated));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // ── Transparent tap zone
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),

        // ── Sheet content
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF252526) : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle
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

              // ── Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      'Filter',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_state.isActive)
                      TextButton(
                        onPressed: () => _update(const GeneralFilterState()),
                        child: Text(
                          'Reset All',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Tab bar
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Characters'),
                  Tab(text: 'Expansion'),
                  Tab(text: 'Sort'),
                ],
              ),

              // ── Tab content (fixed height)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCharactersTab(theme),
                    _buildExpansionTab(theme),
                    _buildSortTab(),
                  ],
                ),
              ),

              // ── Bottom safe area padding
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        ),
      ],
    );
  }

  // ── Characters tab 
  Widget _buildCharactersTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader('FACTION'),
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

        const SizedBox(height: 24),

        // Add more character-type toggles below as needed
        _buildSectionHeader('CHARACTER TYPE'),
        const SizedBox(height: 8),
        _buildToggleTile(
          label: 'Lord Cards Only',
          sublabel: 'Generals with a Lord skill',
          value: _state.lordOnly,
          onChanged: (v) => _update(_state.copyWith(lordOnly: v)),
        ),
      ],
    );
  }

  // ── Expansion tab 
  Widget _buildExpansionTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader('EXPANSION'),
        const SizedBox(height: 12),
        for (final expansion in Expansion.values)
          _buildCheckTile(
            badge: expansion.badge,
            label: _expansionLabel(expansion),
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
      case Expansion.standard: return '标准 — Standard';
      case Expansion.demon: return '魔 — Demon';
      case Expansion.god: return '神 — Demon';
    }
  }

  // ── Sort tab 
  Widget _buildSortTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader('SORT BY'),
        const SizedBox(height: 8),
        for (final order in GeneralSortOrder.values)
          _buildRadioTile(order),
      ],
    );
  }

  Widget _buildRadioTile(GeneralSortOrder order) {
    final isSelected = _state.sortOrder == order;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        order.label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.radio_button_checked, color: theme.colorScheme.primary)
          : const Icon(Icons.radio_button_unchecked),
      onTap: () => _update(_state.copyWith(sortOrder: order)),
    );
  }

  // ── Shared builders
  Widget _buildSectionHeader(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildToggleTile({
    required String label,
    required String sublabel,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sublabel, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildCheckTile({
    required String badge,
    required String label,
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
        child: Text(
          badge,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
      title: Text(label),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : const Icon(Icons.circle_outlined),
      onTap: onTap,
    );
  }
}

// ── Faction chip widget 
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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