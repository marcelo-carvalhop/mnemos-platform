import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../providers.dart';
import '../providers_today.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// O que aconteceu com o baralho depois do menu.
enum DeckAction { renamed, archived, deleted }

/// O resultado do menu: o que foi feito e, quando foi renomear, o nome novo.
typedef DeckActionOutcome = ({DeckAction action, String? name});

/// O menu de um baralho — renomear, arquivar, apagar.
///
/// Mora fora das telas porque **duas** o abrem: o "..." do card da Biblioteca
/// e o "..." do detalhe do baralho. Enquanto ele vivia dentro do detalhe, o da
/// Biblioteca era um ícone decorativo dentro de um card clicável — tocá-lo
/// abria o baralho, que é a única coisa que "..." nunca deveria fazer.
///
/// Devolve `null` quando nada foi decidido. Quem chama decide o que fazer com
/// a tela: o detalhe do baralho se fecha depois de arquivar ou apagar, a
/// Biblioteca só se redesenha.
Future<DeckActionOutcome?> showDeckActions(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
  required String name,
}) async {
  final chosen = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MnemosSpacing.lg,
              MnemosSpacing.lg,
              MnemosSpacing.lg,
              MnemosSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(name, style: MnemosText.cardTitle),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Renomear'),
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Arquivar'),
            subtitle: const Text('Some da lista e para de agendar. Volta inteiro.'),
            onTap: () => Navigator.of(context).pop('archive'),
          ),
          ListTile(
            // Coral quer dizer "vence hoje" em todo o resto do app. Um botão
            // que apaga dados não pode falar a mesma língua de um lembrete.
            leading: const Icon(Icons.delete_outline, color: MnemosColors.destructive),
            title: const Text('Apagar', style: TextStyle(color: MnemosColors.destructive)),
            subtitle: const Text('Leva os cards e o histórico junto.'),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    ),
  );

  if (chosen == null) return null;
  if (!context.mounted) return null;

  return switch (chosen) {
    'rename' => _rename(context, ref, deckId: deckId, name: name),
    'archive' => _archive(context, ref, deckId: deckId),
    'delete' => _delete(context, ref, deckId: deckId),
    _ => null,
  };
}

void _invalidateDeckViews(WidgetRef ref, String deckId) {
  ref
    ..invalidate(decksProvider)
    ..invalidate(deckCardCountsProvider)
    ..invalidate(queueProvider)
    ..invalidate(hasAnyCardsProvider)
    ..invalidate(deckMaturityProvider)
    ..invalidate(dueByDeckProvider)
    ..invalidate(deckCardsByBucketProvider(deckId));
}

Future<DeckActionOutcome?> _rename(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
  required String name,
}) async {
  final controller = TextEditingController(text: name);
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nome do baralho'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (chosen == null || chosen.isEmpty || chosen == name) return null;

  final authoring = await ref.read(authoringServiceProvider.future);
  await authoring.renameDeck(deckId, chosen, ref.read(clockProvider)());
  _invalidateDeckViews(ref, deckId);
  return (action: DeckAction.renamed, name: chosen);
}

Future<DeckActionOutcome?> _archive(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
}) async {
  final authoring = await ref.read(authoringServiceProvider.future);
  await authoring.archiveDeck(deckId, ref.read(clockProvider)());
  _invalidateDeckViews(ref, deckId);
  if (!context.mounted) return null;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Arquivado. Nada foi perdido.')),
  );
  return (action: DeckAction.archived, name: null);
}

Future<DeckActionOutcome?> _delete(
  BuildContext context,
  WidgetRef ref, {
  required String deckId,
}) async {
  final counts = await ref.read(deckCardCountsProvider.future);
  if (!context.mounted) return null;
  final total = counts[deckId] ?? 0;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Apagar o baralho?'),
      content: Text(
        total == 0
            ? 'O baralho está vazio. Nada de histórico se perde.'
            : 'Apaga ${plural(total, "card", "cards")} e todo o histórico de '
                'revisão deles. Não dá para desfazer.\n\n'
                'Se você só terminou o assunto, arquivar guarda tudo.',
        style: MnemosText.bodySmall,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: MnemosColors.destructive),
          child: const Text('Apagar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return null;

  final authoring = await ref.read(authoringServiceProvider.future);
  final removed = await authoring.deleteDeck(deckId, ref.read(clockProvider)());
  _invalidateDeckViews(ref, deckId);
  if (!context.mounted) return null;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Baralho apagado ($removed cards).')),
  );
  return (action: DeckAction.deleted, name: null);
}
