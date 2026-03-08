import 'package:flutter/material.dart';
import '../../../../core/services/pin_service.dart';
import '../../../generals/data/models/general_card.dart';
import '../../../generals/data/repository/general_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<GeneralCard> _pinned = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ids = await PinService.instance.getPinnedIds(PinType.general);
    if (ids.isEmpty) {
      if (mounted) setState(() { _pinned = []; _loading = false; });
      return;
    }
    final all = await GeneralLoader().getGenerals();
    final pinned = ids
        .map((id) => all.where((g) => g.id == id).firstOrNull)
        .whereType<GeneralCard>()
        .toList();
    if (mounted) setState(() { _pinned = pinned; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Pin Debug', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Pull to refresh. Pin generals from the Generals tab.',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_pinned.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.push_pin_outlined, size: 40, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Nothing pinned yet.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              ...List.generate(_pinned.length, (i) {
                final card = _pinned[i];
                return ListTile(
                  leading: const Icon(Icons.push_pin, color: Colors.orange, size: 20),
                  title: Text(card.nameEn, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${card.nameCn}  ·  ${card.faction}  ·  ID: ${card.id}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () async {
                      await PinService.instance.unpin(card.id, PinType.general);
                      _load();
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}