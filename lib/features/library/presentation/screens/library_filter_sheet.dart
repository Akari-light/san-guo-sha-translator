import 'package:flutter/material.dart';
import '../../data/models/library_dto.dart';
import '../../../../core/theme/app_theme.dart';

// ── Sort Order 
enum LibrarySortOrder {
  none,    
  nameAZ,  
  nameZA;  

  String get label {
    switch (this) {
      case LibrarySortOrder.none:   return 'None (Default)';
      case LibrarySortOrder.nameAZ: return 'Name A → Z';
      case LibrarySortOrder.nameZA: return 'Name Z → A';
    }
  }
}

// ── Filter State 
class LibraryFilterState {
  final Set<String> categories;
  final bool hasRangeOnly;
  final LibrarySortOrder sortOrder;

  const LibraryFilterState({
    this.categories = const {},
    this.hasRangeOnly = false,
    this.sortOrder = LibrarySortOrder.none,
  });

  bool get isActive =>
      categories.isNotEmpty ||
      hasRangeOnly ||
      sortOrder != LibrarySortOrder.none;

  LibraryFilterState copyWith({
    Set<String>? categories,
    bool? hasRangeOnly,
    LibrarySortOrder? sortOrder,
  }) {
    return LibraryFilterState(
      categories: categories ?? this.categories,
      hasRangeOnly: hasRangeOnly ?? this.hasRangeOnly,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  List<LibraryDTO> apply(List<LibraryDTO> all) {
    List<LibraryDTO> result = all;

    if (categories.isNotEmpty) {
      result = result.where((c) => categories.contains(c.categoryEn)).toList();
    }
    if (hasRangeOnly) {
      result = result.where((c) => c.range != null).toList();
    }

    switch (sortOrder) {
      case LibrarySortOrder.none:
        break;
      case LibrarySortOrder.nameAZ:
        result.sort((a, b) => a.nameEn.compareTo(b.nameEn));
      case LibrarySortOrder.nameZA:
        result.sort((a, b) => b.nameEn.compareTo(a.nameEn));
    }

    return result;
  }
}

// ── Bottom Sheet 
class LibraryFilterSheet extends StatefulWidget {
  final LibraryFilterState initialState;
  final void Function(LibraryFilterState) onChanged;

  const LibraryFilterSheet({
    super.key,
    required this.initialState,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required LibraryFilterState initialState,
    required void Function(LibraryFilterState) onChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LibraryFilterSheet(
        initialState: initialState,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<LibraryFilterSheet> createState() => _LibraryFilterSheetState();
}

class _LibraryFilterSheetState extends State<LibraryFilterSheet>
    with SingleTickerProviderStateMixin {
  late LibraryFilterState _state;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _update(LibraryFilterState newState) {
    setState(() => _state = newState);
    widget.onChanged(newState);
  }

  void _toggleCategory(String category) {
    final updated = Set<String>.from(_state.categories);
    updated.contains(category)
        ? updated.remove(category)
        : updated.add(category);
    _update(_state.copyWith(categories: updated));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
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
                        onPressed: () => _update(const LibraryFilterState()),
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
                  Tab(text: 'Cards'),
                  Tab(text: 'Sort'),
                ],
              ),

              // ── Tab content
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.45,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCardsTab(theme, isDark),
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

  // ── Cards tab 
  Widget _buildCardsTab(ThemeData theme, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader('CATEGORY'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: LibraryDTO.categoryOrder
              .map((cat) => _CategoryFilterChip(
                    category: cat,
                    isSelected: _state.categories.contains(cat),
                    isDark: isDark,
                    onTap: () => _toggleCategory(cat),
                  ))
              .toList(),
        ),

        const SizedBox(height: 24),

        _buildSectionHeader('CARD PROPERTIES'),
        const SizedBox(height: 8),
        _buildToggleTile(
          label: 'Has Range Only',
          sublabel: 'Show only cards with an attack range value',
          value: _state.hasRangeOnly,
          onChanged: (v) => _update(_state.copyWith(hasRangeOnly: v)),
        ),
      ],
    );
  }

  // ── Sort tab 
  Widget _buildSortTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSectionHeader('SORT BY'),
        const SizedBox(height: 8),
        for (final order in LibrarySortOrder.values)
          _buildRadioTile(order),
      ],
    );
  }

  Widget _buildRadioTile(LibrarySortOrder order) {
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
}

// ── Category chip widget 
class _CategoryFilterChip extends StatelessWidget {
  final String category;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.category,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(category, isDark);
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
          category,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}