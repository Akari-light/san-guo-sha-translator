// lib/features/ai/presentation/screens/scanner_results_sheet.dart
//
// Results DraggableScrollableSheet for the Discover tab scanner.
// Extracted from scanner_screen.dart so the file stays manageable — same
// pattern as general_filter_sheet.dart and library_filter_sheet.dart.
//
// Shown as a Positioned.fill child inside ai_screen's scan-mode Stack.
// The parent gives it bounded height so DraggableScrollableSheet works.
//
// Displays:
//   • A tap-to-dismiss transparent backdrop
//   • A bottom sheet with handle, match header, top candidate card,
//     and a scrollable list of additional candidates

import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
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
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Stack(
      children: [
        // ── Transparent backdrop ─────────────────────────────────────────────
        // Covers the frozen image area ABOVE the sheet so a tap there dismisses.
        // Uses AbsorbPointer inside to let the sheet's own drag gestures through.
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            // opaque so taps on the frozen image area are captured
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),

        // ── DraggableScrollableSheet ─────────────────────────────────────────
        // expand: true — required when inside a bounded Positioned.fill parent.
        // Three snap points: peek (38%) → half (60%) → full (85%).
        DraggableScrollableSheet(
          expand: true,
          initialChildSize: 0.38,
          minChildSize: 0.18,
          maxChildSize: 0.85,
          snap: true,
          snapSizes: const [0.38, 0.60, 0.85],
          builder: (context, scrollController) {
            return _SheetBody(
              candidates:       candidates,
              onSelect:         onSelect,
              onDismiss:        onDismiss,
              scrollController: scrollController,
              bg:               bg,
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet body — separated from the sheet scaffold so the GestureDetector
// on the handle area doesn't interfere with the drag recogniser.
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
      // Wrap everything in a ListView so the whole sheet scrolls together,
      // including the header. This ensures drag gestures anywhere on the
      // sheet body — not just the list area — move the sheet.
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          // ── Handle + header ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: theme.hintColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Match count + confidence badge
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

          // ── Top candidate ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _TopCandidateCard(
              candidate: candidates.first,
              onTap: () => onSelect(candidates.first),
            ),
          ),

          // ── Other candidates ───────────────────────────────────────────────
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

          // ── Bottom padding ─────────────────────────────────────────────────
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
// _TopCandidateCard — large prominent first result
// ─────────────────────────────────────────────────────────────────────────────

class _TopCandidateCard extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;
  const _TopCandidateCard({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
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
                errorBuilder: (_, _, _) =>
                    Image.asset(placeholder, width: 60, height: 82, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.nameCn,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    candidate.nameEn,
                    style: TextStyle(fontSize: 13, color: theme.hintColor),
                  ),
                  const SizedBox(height: 6),
                  _TypeBadge(isGeneral: isGeneral),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CandidateTile — compact row for additional candidates
// ─────────────────────────────────────────────────────────────────────────────

class _CandidateTile extends StatelessWidget {
  final MatchCandidate candidate;
  final VoidCallback onTap;
  const _CandidateTile({required this.candidate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final pct       = (candidate.confidence * 100).toStringAsFixed(0);
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
                errorBuilder: (_, _, _) =>
                    Image.asset(placeholder, width: 40, height: 55, fit: BoxFit.cover),
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
            Text('$pct%',
                style: TextStyle(
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
// Small shared widgets (used only within this file)
// ─────────────────────────────────────────────────────────────────────────────

class _ConfidenceBadge extends StatelessWidget {
  final double confidence;
  const _ConfidenceBadge({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct   = (confidence * 100).toStringAsFixed(0);
    final color = confidence >= 0.80 ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$pct% match',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
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
      child: Text(
        isGeneral ? 'General' : 'Library Card',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).hintColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}