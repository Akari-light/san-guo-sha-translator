import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../generals/data/models/general_card.dart';
import '../../../generals/data/repository/general_loader.dart';
import '../../../generals/presentation/screens/general_detail_screen.dart';
import '../../domain/models/pending_session_selection.dart';
import '../../domain/models/game_session_player.dart';
import '../controllers/game_session_controller.dart';
import 'game_session_general_picker_screen.dart';
import '../widgets/game_session_widgets.dart';

class GameSessionRoomScreen extends StatefulWidget {
  const GameSessionRoomScreen({super.key, required this.controller});

  final GameSessionController controller;

  @override
  State<GameSessionRoomScreen> createState() => _GameSessionRoomScreenState();
}

class _GameSessionRoomScreenState extends State<GameSessionRoomScreen> {
  Map<String, GeneralCard> _generalMap = const {};

  @override
  void initState() {
    super.initState();
    _loadGenerals();
  }

  Future<void> _loadGenerals() async {
    final generals = await GeneralLoader().getGenerals();
    if (!mounted) return;
    setState(() {
      _generalMap = {for (final general in generals) general.id: general};
    });
  }

  Color _presenceColor(GameSessionPresence presence) {
    switch (presence) {
      case GameSessionPresence.online:
        return const Color(0xFF22C55E);
      case GameSessionPresence.away:
        return const Color(0xFFF59E0B);
      case GameSessionPresence.offline:
        return const Color(0xFF94A3B8);
    }
  }

  Future<void> _copyValue(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showInviteSheet() async {
    final room = widget.controller.room;
    if (room == null || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room QR',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ask nearby players to join the same Wi-Fi network or personal hotspot, then scan this QR or import the room invite text.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: SessionSurface(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: QrImageView(
                        data: room.invitePayload,
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  room.roomCode,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Host: ${room.coordinator?.displayName ?? room.coordinatorPlayerId}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SessionActionButton(
                      label: 'Copy room code',
                      icon: Icons.tag_rounded,
                      onPressed: () =>
                          _copyValue(room.roomCode, 'Room code copied.'),
                    ),
                    SessionActionButton(
                      label: 'Copy room invite',
                      icon: Icons.copy_rounded,
                      onPressed: () =>
                          _copyValue(room.invitePayload, 'Room invite copied.'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickMyGeneral() async {
    final selection = await Navigator.of(context).push<PendingSessionSelection>(
      detailRoute(const GameSessionGeneralPickerScreen()),
    );
    if (selection == null) return;
    await widget.controller.setMyGeneral(
      selection.generalId,
      skinId: selection.skinId,
    );
    if (!mounted) return;
    final selected = _generalMap[selection.generalId];
    final selectedLabel = selected?.nameEn ?? selection.generalId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$selectedLabel is now your session General.')),
    );
  }

  Future<void> _openGeneral(String generalId) async {
    final card = await GeneralLoader().findById(generalId);
    if (!mounted || card == null) return;
    Navigator.of(context).push(detailRoute(GeneralDetailScreen(card: card)));
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.controller.room!;
    final connection = widget.controller.connection;
    final canMutateRoom = connection.allowsRoomMutations;
    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${room.roomCode}'),
        actions: [
          IconButton(
            tooltip: 'Back to lobby',
            onPressed: widget.controller.showLauncher,
            icon: const Icon(Icons.grid_view_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showInviteSheet,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('Room QR'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
        children: [
          SessionStatusBanner(
            status: connection.status,
            message: connection.message,
          ),
          const SizedBox(height: 18),
          SessionSurface(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SessionSectionTitle('Room'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.roomCode,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Host: ${room.coordinator?.displayName ?? room.coordinatorPlayerId}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap the Room QR button below to show the QR code and join instructions.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SessionStatusPill(
                                  label: room.status,
                                  color: const Color(0xFF0EA5E9),
                                ),
                                SessionStatusPill(
                                  label: '${room.players.length}/10 players',
                                  color: const Color(0xFF8B5CF6),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SessionSurface(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: SessionSectionTitle('Roster')),
                      SessionActionButton(
                        label: 'Set My General',
                        icon: Icons.person_search_rounded,
                        primary: true,
                        onPressed: canMutateRoom ? _pickMyGeneral : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final player in room.orderedPlayers) ...[
                    _PlayerRow(
                      player: player,
                      isCoordinator:
                          player.playerId == room.coordinatorPlayerId,
                      presenceColor: _presenceColor(player.presence),
                      generalName: player.generalId == null
                          ? null
                          : _generalMap[player.generalId!]?.nameEn ??
                                player.generalId,
                      onTap: player.generalId == null
                          ? null
                          : () => _openGeneral(player.generalId!),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SessionActionButton(
                label: 'Leave room',
                icon: Icons.logout_rounded,
                onPressed: widget.controller.leaveRoom,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.isCoordinator,
    required this.presenceColor,
    required this.generalName,
    this.onTap,
  });

  final GameSessionPlayer player;
  final bool isCoordinator;
  final Color presenceColor;
  final String? generalName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: presenceColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          player.displayName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCoordinator) ...[
                        const SizedBox(width: 8),
                        const SessionStatusPill(
                          label: 'Host',
                          color: Color(0xFF2563EB),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    generalName == null
                        ? 'No General selected'
                        : 'General: $generalName',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (player.skinId != null)
                    Text(
                      'Skin: ${player.skinId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).hintColor,
              ),
          ],
        ),
      ),
    );
  }
}
