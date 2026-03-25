// lib/features/ai/presentation/screens/discover_search_screen.dart
//
// Semantic search screen for the Discover tab (Feature 2 placeholder).
// Extracted from scanner_screen.dart — search mode now lives here exclusively.
//
// Rendered by ScannerScreen when the user switches to Search mode.
// Returns to scan mode via the onSwitchToScan callback (mode pill tap).

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DiscoverSearchScreen
// ─────────────────────────────────────────────────────────────────────────────

class DiscoverSearchScreen extends StatefulWidget {
  /// Called when the user taps "Scan Card" in the mode pill.
  final VoidCallback onSwitchToScan;

  const DiscoverSearchScreen({
    super.key,
    required this.onSwitchToScan,
  });

  @override
  State<DiscoverSearchScreen> createState() => _DiscoverSearchScreenState();
}

class _DiscoverSearchScreenState extends State<DiscoverSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Do NOT use Scaffold — this screen sits inside main.dart's Scaffold.
    return SizedBox.expand(
      child: SafeArea(
        child: Column(
          children: [
            // ── Search bar ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search rules, generals, card effects…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(height: 8),

            // ── Results area ───────────────────────────────────────────────
            // Feature 2 placeholder — will be replaced with semantic search.
            Expanded(
              child: _searchController.text.isEmpty
                  ? const _SearchEmptyState()
                  : const Center(
                      child: Text(
                        'Semantic search\ncoming in Feature 2',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
            ),

            // ── Mode pill at bottom ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: _SearchModePill(onSwitchToScan: widget.onSwitchToScan),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchEmptyState
// ─────────────────────────────────────────────────────────────────────────────

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 52,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Search for rules, generals,\nor card effects',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'e.g. "skill that draws cards when losing HP"\nor "what is chain damage"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchModePill
// Search is always selected here; Scan Card tap calls onSwitchToScan.
// ─────────────────────────────────────────────────────────────────────────────

class _SearchModePill extends StatelessWidget {
  final VoidCallback onSwitchToScan;
  const _SearchModePill({required this.onSwitchToScan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillItem(
            icon: Icons.document_scanner_outlined,
            label: 'Scan Card',
            selected: false,
            onTap: onSwitchToScan,
          ),
          _PillItem(
            icon: Icons.search,
            label: 'Search',
            selected: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PillItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.black87 : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.black87 : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}