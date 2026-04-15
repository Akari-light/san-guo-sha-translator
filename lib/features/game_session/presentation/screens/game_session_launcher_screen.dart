import 'package:flutter/material.dart';

import '../controllers/game_session_controller.dart';
import '../widgets/game_session_widgets.dart';

class GameSessionLauncherScreen extends StatefulWidget {
  const GameSessionLauncherScreen({
    super.key,
    required this.controller,
  });

  final GameSessionController controller;

  @override
  State<GameSessionLauncherScreen> createState() => _GameSessionLauncherScreenState();
}

class _GameSessionLauncherScreenState extends State<GameSessionLauncherScreen> {
  final _displayNameController = TextEditingController();
  final _roomCodeController = TextEditingController();
  final _inviteController = TextEditingController();

  @override
  void dispose() {
    _displayNameController.dispose();
    _roomCodeController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final importedInvite = controller.importedInvitePayload;
    if (importedInvite != null && importedInvite.isNotEmpty && _inviteController.text != importedInvite) {
      _inviteController.text = importedInvite;
      _inviteController.selection = TextSelection.collapsed(offset: importedInvite.length);
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Game Session')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          Text(
            'Share the general you are playing with everyone at the table.',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'QR is the fastest join path. Everyone should be on the same Wi-Fi network or personal hotspot, and room code only works after the host room invite has already been imported on this device.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.5),
          ),
          if (controller.pendingSelection != null) ...[
            const SizedBox(height: 16),
            SessionSurface(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.person_search_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pending selection: ${controller.pendingSelection!.generalId}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SessionSurface(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SessionSectionTitle('Player'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      hintText: 'Enter your name',
                    ),
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
                  const SessionSectionTitle('Create'),
                  const SizedBox(height: 12),
                  SessionActionButton(
                    label: controller.busy ? 'Creating...' : 'Create room',
                    icon: Icons.add_circle_outline,
                    primary: true,
                    onPressed: controller.busy
                        ? null
                        : () => controller.createRoom(_displayNameController.text),
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
                  const SessionSectionTitle('Join'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _roomCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Room code',
                      hintText: 'ABC123',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _inviteController,
                    decoration: const InputDecoration(
                      labelText: 'Room invite',
                      hintText: 'Paste the host room invite text if scanning is unavailable',
                    ),
                    minLines: 3,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SessionActionButton(
                        label: 'Scan QR',
                        icon: Icons.qr_code_scanner,
                        onPressed: controller.busy ? null : controller.showScanner,
                      ),
                      SessionActionButton(
                        label: 'Import room invite',
                        icon: Icons.download_rounded,
                        onPressed: controller.busy || _inviteController.text.trim().isEmpty
                            ? null
                            : () => controller.importInvite(_inviteController.text),
                      ),
                      SessionActionButton(
                        label: 'Join room',
                        icon: Icons.login_rounded,
                        primary: true,
                        onPressed: controller.busy
                            ? null
                            : () async {
                                final invite = _inviteController.text.trim();
                                if (invite.isNotEmpty) {
                                  await controller.joinByInvite(
                                    invite,
                                    _displayNameController.text,
                                  );
                                  return;
                                }
                                await controller.joinByRoomCode(
                                  _roomCodeController.text,
                                  _displayNameController.text,
                                );
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 16),
            Text(
              controller.error!,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
