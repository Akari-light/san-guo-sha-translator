// lib/features/ai/presentation/screens/scanner_results_sheet.dart
//
// Results DraggableScrollableSheet for the Discover tab scanner.
//
// Phase 3 addition: Pin button on each candidate row. Wired to PinService
// with the correct PinType (general/library) derived from RecordType.
//
// Architecture note: this file imports PinService from core/services — this
// is a permitted dependency direction (features/presentation → core/*).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/services/recently_viewed_service.dart';
import '../../../../core/services/scanner_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ScannerResultsSheet
// ─────────────────────────────────────────────────────────────────────────────

class ScannerResultsSheet extends StatelessWidget {
  final List<MatchCandidate> candidates;
  final void Function(MatchCandidate) onSelect;
  final VoidCallback onDismiss;

  const ScannerResultsSheet({
    super.key,
    required this.candidates,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Stack(
      children: [
        // No backdrop tap-to-dismiss — taps above the sheet pass through
        // to the rect-handle overlay so users can re-crop live.
        DraggableScrollableSheet(
          expand: true,
          initialChildSize: 0.38,
          minChildSize: 0.18,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [0.38, 0.60, 0.85],
          builder: (context, scrollController) {
            return _SheetBody(
              candidates: candidates,
              onSelect: onSelect,
              onDismiss: onDismiss,
              scrollController: scrollController,
              bg: bg,
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet body
// ─────────────────────────────────────────────────────────────────────────────

class _SheetBody extends StatelessWidget {
  final List<MatchCandidate> candidates;
  final void Function(MatchCandidate) onSelect;
  final VoidCallback onDismiss;
  final ScrollController scrollController;
  final Color bg;

  const _SheetBody({
    required this.candidates,
    required this.onSelect,
    required this.onDismiss,
    required this.scrollController,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          // ── Handle + header
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.hintColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    children: [
                      Text(
                        candidates.length == 1
                            ? 'Match Found'
                            : '${candidates.length} Possible Matches',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      _ConfidenceBadge(confidence: candidates.first.confidence),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),

          // ── Top candidate
          SliverToBoxAdapter(
            child: _TopCandidateCard(
              candidate: candidates.first,
              onTap: () => onSelect(candidates.first),
            ),
          ),

          // ── Other candidates
          if (candidates.length > 1) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Other possibilities',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: candidates.length - 1,
              itemBuilder: (_, i) => _CandidateTile(
                candidate: candidates[i + 1],
                onTap: () => onSelect(candidates[i + 1]),
              ),
            ),
          ],

          // ── Bottom padding
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.of(context).padding.bottom + 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TopCandidateCard — with pin button (Phase 3)
// ─────────────────────────────────────────────────────────────────────────────

class _TopCandidateCard extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;
  const _TopCandidateCard({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGeneral = candidate.recordType == RecordType.general;
    final placeholder =
        isGeneral ? AppAssets.generalPlaceholder : AppAssets.libraryPlaceholder;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                candidate.imagePath,
                width: 60, height: 82, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  placeholder, width: 60, height: 82, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.nameCn,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 3),
                  Text(candidate.nameEn,
                      style: TextStyle(fontSize: 13, color: theme.hintColor)),
                  const SizedBox(height: 6),
                  _TypeBadge(isGeneral: isGeneral),
                ],
              ),
            ),
            // ── Pin button (Phase 3) ──────────────────────────────────────
            _PinButton(candidate: candidate),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.arrow_forward_rounded,
                  size: 20, color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CandidateTile — with pin button (Phase 3)
// ─────────────────────────────────────────────────────────────────────────────

class _CandidateTile extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;
  const _CandidateTile({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (candidate.confidence * 100).toStringAsFixed(0);
    final confColor = candidate.confidence >= 0.80 ? Colors.green : Colors.orange;
    final isGeneral = candidate.recordType == RecordType.general;
    final placeholder =
        isGeneral ? AppAssets.generalPlaceholder : AppAssets.libraryPlaceholder;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.asset(
                candidate.imagePath,
                width: 40, height: 55, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  placeholder, width: 40, height: 55, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.nameCn,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(candidate.nameEn,
                      style: TextStyle(fontSize: 12, color: theme.hintColor)),
                  const SizedBox(height: 4),
                  _TypeBadge(isGeneral: isGeneral),
                ],
              ),
            ),
            // ── Pin button (Phase 3) ──────────────────────────────────────
            _PinButton(candidate: candidate, compact: true),
            const SizedBox(width: 6),
            Text('$pct%', style: TextStyle(
                color: confColor, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PinButton — stateful, queries PinService for current state
// ─────────────────────────────────────────────────────────────────────────────

class _PinButton extends StatefulWidget {
  final MatchCandidate candidate;
  final bool compact;
  const _PinButton({required this.candidate, this.compact = false});

  @override
  State<_PinButton> createState() => _PinButtonState();
}

class _PinButtonState extends State<_PinButton> {
  bool _pinned = false;
  bool _loading = true;
  StreamSubscription<PinType>? _sub;

  PinType get _pinType =>
      widget.candidate.recordType == RecordType.general
          ? PinType.general
          : PinType.library;

  @override
  void initState() {
    super.initState();
    _loadState();
    // Listen for external pin changes (e.g. from detail screen)
    _sub = PinService.instance.changes.listen((type) {
      if (type == _pinType) { _loadState(); }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PinButton old) {
    super.didUpdateWidget(old);
    if (old.candidate.cardId != widget.candidate.cardId) { _loadState(); }
  }

  Future<void> _loadState() async {
    final pinned = await PinService.instance.isPinned(
      widget.candidate.cardId, _pinType,
    );
    if (mounted) { setState(() { _pinned = pinned; _loading = false; }); }
  }

  Future<void> _toggle() async {
    final nowPinned = await PinService.instance.toggle(
      widget.candidate.cardId, _pinType,
    );
    if (!mounted) { return; }

    // Phase 4: Recording a pin also records a recent view, so the card
    // appears in the Home screen's recently viewed strip.
    if (nowPinned) {
      RecentlyViewedService.instance.record(
        widget.candidate.cardId,
        widget.candidate.recordType,
      );
    }

    setState(() => _pinned = nowPinned);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(nowPinned
          ? '${widget.candidate.nameEn} pinned'
          : '${widget.candidate.nameEn} unpinned'),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) { return const SizedBox(width: 32, height: 32); }
    final size = widget.compact ? 18.0 : 22.0;
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          _pinned ? Icons.push_pin : Icons.push_pin_outlined,
          size: size,
          color: _pinned
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).hintColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared widgets (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toStringAsFixed(0);
    final color = confidence >= 0.80 ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$pct% match',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final bool isGeneral;
  const _TypeBadge({required this.isGeneral});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(isGeneral ? 'General' : 'Library Card',
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor,
              fontWeight: FontWeight.w500)),
    );
  }
}