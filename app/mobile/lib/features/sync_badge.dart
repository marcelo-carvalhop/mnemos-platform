import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers_sync.dart';
import '../sync/sync_controller.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// What the app says about syncing (§2.2, §5.14).
///
/// Offline-first means offline is not a problem, so this refuses to look like
/// one: no red, no warning triangle, no modal. The honest thing to show is how
/// many changes are waiting, because that is true and reassuring at the same
/// time — nothing has been lost.
///
/// Nothing at all is shown when everything is synced. A permanent green tick
/// trains people to ignore the spot where a real message would appear.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);

    final (label, colour, icon) = switch (sync.phase) {
      SyncPhase.idle when sync.pending == 0 => (null, null, null),
      SyncPhase.idle => (
          '${sync.pending} ${sync.pending == 1 ? "mudança" : "mudanças"} para enviar',
          MnemosColors.faint,
          Icons.cloud_upload_outlined,
        ),
      SyncPhase.syncing => ('Sincronizando', MnemosColors.faint, Icons.sync),
      SyncPhase.resyncing => (
          'Recarregando tudo',
          MnemosColors.faint,
          Icons.sync,
        ),
      SyncPhase.offline => (
          sync.pending == 0
              ? 'Sem conexão'
              : 'Sem conexão · ${sync.pending} para enviar',
          MnemosColors.muted,
          Icons.cloud_off_outlined,
        ),
      // The only state worth a colour: something is wrong that waiting will
      // not fix.
      SyncPhase.failed => (
          'Não consegui sincronizar',
          MnemosColors.due,
          Icons.error_outline,
        ),
    };

    if (label == null) return const SizedBox.shrink();

    return InkWell(
      onTap: () => ref.read(syncControllerProvider.notifier).syncNow(),
      customBorder: squircle(MnemosRadii.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colour),
            const SizedBox(width: 5),
            Text(label, style: MnemosText.monoSmall.copyWith(color: colour)),
          ],
        ),
      ),
    );
  }
}
