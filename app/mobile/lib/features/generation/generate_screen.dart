import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:store/store.dart' show Deck;

import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme.dart';
import 'error_copy.dart';
import 'generating_screen.dart';
import 'paywall_screen.dart';

/// Screen `18 Gerar por tópico` — §5.5.
///
/// The quota line at the top is not decoration. With one generation for the
/// lifetime of the account (§7.7), a user who spends it without realising has
/// been tricked, and the screen that spends it is the one that has to say so.
class GenerateScreen extends ConsumerStatefulWidget {
  const GenerateScreen({super.key, this.deckId, this.deckName});

  final String? deckId;
  final String? deckName;

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  final _topic = TextEditingController();
  String? _deckId;
  String _level = 'intermediario';
  int _count = 10;
  bool _submitting = false;

  // Short enough to fit three across a phone. "Intermediário" wrapped to two
  // lines and broke mid-word.
  static const _levels = {
    'basico': 'Básico',
    'intermediario': 'Médio',
    'avancado': 'Avançado',
  };

  @override
  void initState() {
    super.initState();
    _deckId = widget.deckId;
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  /// The deck the generation will land in.
  ///
  /// One place, used by both the dropdown and the submit. They were separate:
  /// the dropdown *showed* the first deck while `_deckId` stayed null until
  /// someone touched it, so the button looked enabled and silently did
  /// nothing — which is worse than a disabled button, because it reads as the
  /// app being broken rather than as something being missing.
  String? _effectiveDeck(List<Deck> decks) =>
      _deckId ?? (decks.isNotEmpty ? decks.first.id : null);

  Future<void> _submit(String deckId) async {
    if (_topic.text.trim().isEmpty) return;

    setState(() => _submitting = true);
    try {
      final job = await ref.read(generationApiProvider).create(
            sourceType: 'topic',
            targetDeckId: deckId,
            topic: _topic.text.trim(),
            requestedCount: _count,
            level: _level,
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GeneratingScreen(jobId: job.id, deckId: deckId)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final failure = GenerationFailure.forException(e);
      if (failure.showsPaywall) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${failure.title}. ${failure.detail}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider);
    final quota = ref.watch(quotaProvider);
    final deckList = decks.valueOrNull ?? const <Deck>[];
    final targetDeck = _effectiveDeck(deckList);

    return Scaffold(
      appBar: AppBar(title: const Text('Gerar por tópico')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            _QuotaLine(quota: quota),
            const SizedBox(height: 22),
            const Text('Tópico', style: TextStyle(fontSize: 12, color: AppColors.faint)),
            const SizedBox(height: 6),
            TextField(
              controller: _topic,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Funcionamento do protocolo TCP e estabelecimento de conexão',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.faint),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Quanto mais estreito o recorte, melhores os cards. '
              '"Redes" é vago; "handshake TCP e controle de fluxo" é específico.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.faint),
            ),
            const SizedBox(height: 22),
            const Text('Baralho de destino',
                style: TextStyle(fontSize: 12, color: AppColors.faint)),
            const SizedBox(height: 6),
            decks.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (rows) => DropdownButtonFormField<String>(
                value: targetDeck,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final d in rows) DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => _deckId = v),
              ),
            ),
            const SizedBox(height: 22),
            const Text('Nível', style: TextStyle(fontSize: 12, color: AppColors.faint)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                for (final entry in _levels.entries)
                  ButtonSegment(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_level},
              onSelectionChanged: (v) => setState(() => _level = v.first),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(child: Text('Quantos cards', style: TextStyle(fontSize: 14))),
                IconButton(
                  onPressed: _count > 5 ? () => setState(() => _count -= 5) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 40,
                  child: Text('$_count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
                IconButton(
                  onPressed: _count < 40 ? () => setState(() => _count += 5) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submitting || _topic.text.trim().isEmpty || targetDeck == null
                  ? null
                  : () => _submit(targetDeck),
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ivory),
                    )
                  : const Text('Gerar cards'),
            ),
            const SizedBox(height: 10),
            if (deckList.isEmpty && decks.hasValue)
              const Center(
                child: Text(
                  'Crie um baralho primeiro — os cards precisam de um lugar.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.hard),
                ),
              )
            else
              const Center(
              child: Text(
                'Nada é criado sem você aprovar, um card por vez.',
                style: TextStyle(fontSize: 11.5, color: AppColors.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one line that stops someone spending their only generation by accident.
class _QuotaLine extends StatelessWidget {
  const _QuotaLine({required this.quota});

  final AsyncValue<({int remaining, int limit, String plan})> quota;

  @override
  Widget build(BuildContext context) {
    final value = quota.valueOrNull;

    // -1 is "we are offline and do not know" (§5.13). Guessing in either
    // direction would be worse than saying so.
    final (text, colour) = switch (value) {
      null => ('Verificando sua cota…', AppColors.faint),
      (remaining: -1, limit: _, plan: _) => (
          'Sem conexão — não sei quanto resta da sua cota',
          AppColors.muted,
        ),
      (remaining: 0, limit: _, plan: _) => (
          'Sua geração grátis já foi usada',
          AppColors.hard,
        ),
      // Plural agreement, which only ever showed as wrong once a test
      // account had more than one.
      (remaining: final r, limit: _, plan: _) => (
          r == 1 ? '1 geração grátis disponível' : '$r gerações grátis disponíveis',
          AppColors.good,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colour == AppColors.good ? AppColors.goodBg : AppColors.fill,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 12.5, color: colour)),
    );
  }
}
