import 'package:flutter/material.dart';

import '../../domain/models/game_session_connection_state.dart';

class SessionSurface extends StatelessWidget {
  const SessionSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF202124) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: child,
    );
  }
}

class SessionSectionTitle extends StatelessWidget {
  const SessionSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class SessionStatusPill extends StatelessWidget {
  const SessionStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
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

class SessionStatusBanner extends StatelessWidget {
  const SessionStatusBanner({super.key, required this.status, this.message});

  final GameSessionConnectionStatus status;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      GameSessionConnectionStatus.hosting => (
        Icons.wifi_tethering_rounded,
        'Hosting',
        const Color(0xFF16A34A),
      ),
      GameSessionConnectionStatus.connected => (
        Icons.check_circle_rounded,
        'Connected',
        const Color(0xFF16A34A),
      ),
      GameSessionConnectionStatus.reconnecting => (
        Icons.sync_rounded,
        'Reconnecting',
        const Color(0xFFF59E0B),
      ),
      GameSessionConnectionStatus.handoff => (
        Icons.swap_horiz_rounded,
        'Host handoff',
        const Color(0xFF0EA5E9),
      ),
      GameSessionConnectionStatus.closed => (
        Icons.meeting_room_rounded,
        'Closed',
        const Color(0xFF64748B),
      ),
      GameSessionConnectionStatus.failed => (
        Icons.error_outline_rounded,
        'Connection issue',
        Theme.of(context).colorScheme.error,
      ),
      GameSessionConnectionStatus.connecting => (
        Icons.sync_rounded,
        'Connecting',
        const Color(0xFF0EA5E9),
      ),
      GameSessionConnectionStatus.idle => (
        Icons.info_outline_rounded,
        'Idle',
        const Color(0xFF64748B),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message == null || message!.trim().isEmpty
                  ? label
                  : '$label - ${message!.trim()}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SessionActionButton extends StatelessWidget {
  const SessionActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.arrow_forward),
      style: FilledButton.styleFrom(
        backgroundColor: primary
            ? scheme.primary
            : scheme.surfaceContainerHighest,
        foregroundColor: primary ? scheme.onPrimary : scheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      label: Text(label),
    );
  }
}
