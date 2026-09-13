import 'package:authoring/authoring.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';

/// Screen `17 Criar card`.
///
/// The counter and the device preview are the point (§5.4): the limit exists
/// because of the e-reader screen, and showing the card at that shape is what
/// teaches someone to write a short card. Save is disabled while over — it is
/// a hard restriction, not a suggestion.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.deckId, required this.deckName});

  final String deckId;
  final String deckName;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _front = TextEditingController();
  final _back = TextEditingController();

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  int get _frontLength => CardText.graphemeLength(_front.text);
  int get _backLength => CardText.graphemeLength(_back.text);

  bool get _canSave =>
      _front.text.trim().isNotEmpty &&
      _back.text.trim().isNotEmpty &&
      _frontLength <= kFrontMaxGraphemes &&
      _backLength <= kBackMaxGraphemes;

  Future<void> _save({required bool another}) async {
    final authoring = await ref.read(authoringServiceProvider.future);
    try {
      await authoring.createCard(
        deckId: widget.deckId,
        front: _front.text.trim(),
        back: _back.text.trim(),
        at: ref.read(clockProvider)(),
      );
    } on CardTooLong catch (e) {
      // Belt and braces: the button is disabled, and the service refuses
      // anyway. The rule has one home (§5.4).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }

    ref.invalidate(deckMaturityProvider);
    ref.invalidate(queueProvider);

    if (!mounted) return;
    if (another) {
      _front.clear();
      _back.clear();
      setState(() {});
      FocusScope.of(context).unfocus();
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Há trabalho na tela que um gesto de voltar apagaria.
  bool get _dirty => _front.text.trim().isNotEmpty || _back.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscard(context)) navigator.pop();
      },
      child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: ScreenBody(
          children: [
            BackHeader(label: widget.deckName),
            const SizedBox(height: MnemosSpacing.md),
            const Text('Novo card', style: MnemosText.screenTitle),
            const SizedBox(height: MnemosSpacing.xl),
            _Field(
              label: 'Frente',
              controller: _front,
              length: _frontLength,
              limit: kFrontMaxGraphemes,
              minLines: 2,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 20),
            _Field(
              label: 'Verso',
              controller: _back,
              length: _backLength,
              limit: kBackMaxGraphemes,
              minLines: 3,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 26),
            const Text('Como fica no aparelho',
                style: MnemosText.caption),
            const SizedBox(height: 8),
            _DevicePreview(text: _front.text.isEmpty ? 'Frente do card' : _front.text),
          ],
        ),
      ),
      // Fixa no rodapé, como o artboard 04 faz com "Gerar": a ação principal
      // de um formulário não deve depender de rolar até o fim para existir.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            MnemosSpacing.screen,
            MnemosSpacing.sm,
            MnemosSpacing.screen,
            MnemosSpacing.md,
          ),
          // Empilhados e não lado a lado: "Salvar e criar outro" não cabe em
          // meia largura sem quebrar em duas linhas, e um rótulo quebrado num
          // botão lê como defeito.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: _canSave ? () => _save(another: true) : null,
                child: const Text('Salvar e criar outro'),
              ),
              const SizedBox(height: MnemosSpacing.sm),
              OutlinedButton(
                onPressed: _canSave ? () => _save(another: false) : null,
                child: const Text('Salvar e sair'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.length,
    required this.limit,
    required this.minLines,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int length;
  final int limit;
  final int minLines;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final over = length > limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: MnemosText.caption),
            Text(
              '$length / $limit',
              style: TextStyle(
                fontSize: 12,
                color: over ? MnemosColors.dueText : MnemosColors.faint,
                fontWeight: over ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: minLines + 3,
          onChanged: (_) => onChanged(),
          // Preenchido, não um retângulo do mesmo tom do fundo com um fio de
          // 1 px em volta. Os campos de Lembretes e Notas têm superfície
          // própria, que funciona com brilho baixo e sem foco — aqui o campo
          // só ganhava estado ao ser tocado, o que é tarde para dizer "digite
          // aqui".
          decoration: InputDecoration(
            filled: true,
            fillColor: over ? const Color(0xFFFEFBFB) : MnemosColors.raised,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MnemosRadii.control),
              borderSide: BorderSide(
                color: over ? const Color(0xFFE8B4AE) : MnemosColors.hairline,
                width: over ? 1.6 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MnemosRadii.control),
              borderSide: BorderSide(
                width: 2,
                color: over ? MnemosColors.dueText : MnemosColors.primary,
              ),
            ),
          ),
        ),
        if (over) ...[
          const SizedBox(height: 6),
          Text(
            '${length - limit} ${length - limit == 1 ? "caractere acima" : "caracteres acima"} do limite. '
            'O card precisa caber na tela do aparelho.',
            style: MnemosText.caption.copyWith(color: MnemosColors.dueText),
          ),
        ],
      ],
    );
  }
}

/// The card at the shape and type size of the device (§5.4).
///
/// Present before the device exists, because it is what teaches the user to
/// write short.
class _DevicePreview extends StatelessWidget {
  const _DevicePreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: ShapeDecoration(
        color: MnemosColors.raised,
        shape: squircle(10, side: BorderSide(color: MnemosColors.hairline)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        // A mesma Literata do terminal: o preview só vale se for o que o
        // aparelho realmente desenha.
        style: MnemosText.cardTitle.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.4,
          color: MnemosColors.inkSoft,
        ),
      ),
    );
  }
}
