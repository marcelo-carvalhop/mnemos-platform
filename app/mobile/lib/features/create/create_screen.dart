import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:store/store.dart' show Deck;

import '../../format.dart';
import '../../providers.dart';
import '../../providers_sync.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../ui/ui.dart';
import '../editor_screen.dart';
import '../generation/error_copy.dart';
import '../generation/generating_screen.dart';
import '../generation/paywall_screen.dart';

/// De onde os cards podem vir.
///
/// `topic` e `text` são os dois usos de texto que o servidor distingue em
/// §7.3: um assunto é o que a pessoa **quer** aprender e o modelo escreve o
/// conteúdo; um texto colado é o material que ela **já tem** e o modelo só
/// extrai. Misturar os dois num campo só faria o modelo inventar sobre um
/// capítulo que a pessoa acabou de colar.
enum CreateSource { topic, text, pdf, photo, byHand }

/// A aba Criar — artboard 04.
///
/// Junta o que eram duas telas separadas ("Gerar por tópico" e "Capturar
/// material") mais o editor manual. O design trata as quatro origens como uma
/// escolha, não como quatro caminhos que você precisa saber que existem: antes
/// era preciso abrir um baralho, tocar em "gerenciar" e só então descobrir que
/// dava para mandar um PDF.
class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key, this.deckId});

  /// Baralho de destino quando a tela é aberta a partir de um deles.
  final String? deckId;

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  /// §7.2 — o mesmo teto da tela antiga: acima disso o servidor recusa, e
  /// descobrir isso depois de subir vinte megabytes é a pior hora.
  static const _maxBytes = 25 * 1024 * 1024;
  static const _counts = [5, 8, 12, 20];

  /// §7.3 — o mesmo teto do contrato, para o assunto e para o material.
  static const _maxChars = 20000;

  final _topic = TextEditingController();
  final _material = TextEditingController();
  CreateSource _source = CreateSource.topic;
  String? _deckId;
  int _count = 8;
  bool _busy = false;
  String? _problem;
  ({String name, Uint8List bytes, String contentType})? _picked;

  @override
  void initState() {
    super.initState();
    _deckId = widget.deckId;
  }

  @override
  void dispose() {
    _material.dispose();
    _topic.dispose();
    super.dispose();
  }

  /// O baralho onde a geração vai cair.
  ///
  /// Resolvido num lugar só, para o botão e o envio nunca discordarem — o bug
  /// que a tela antiga tinha era exatamente esse: o seletor mostrava o
  /// primeiro baralho enquanto o estado seguia nulo, e o botão parecia
  /// habilitado sem fazer nada.
  String? _effectiveDeck(List<Deck> decks) =>
      _deckId ?? (decks.isNotEmpty ? decks.first.id : null);

  Future<void> _choose(CreateSource source, List<Deck> decks) async {
    if (source == CreateSource.byHand) {
      final deckId = _effectiveDeck(decks);
      if (deckId == null) {
        setState(() => _problem = 'Crie um baralho antes de escrever um card.');
        return;
      }
      final deck = decks.firstWhere((d) => d.id == deckId);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditorScreen(deckId: deck.id, deckName: deck.name),
        ),
      );
      return;
    }

    setState(() {
      _source = source;
      _problem = null;
      _picked = null;
    });

    if (source == CreateSource.pdf) await _pickPdf();
    if (source == CreateSource.photo) await _pickPhoto();
  }

  Future<void> _pickPhoto() async {
    // "Foto do caderno" quer dizer apontar a câmera para o caderno. Só abrir a
    // galeria obrigaria a fotografar antes, sair do app e voltar — o caminho
    // mais comum sendo o único que a tela não oferecia.
    final from = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (from == null || !mounted) return;

    final file = await ImagePicker().pickImage(
      source: from,
      // Suficiente para o modelo ler uma página; muito menos que o original de
      // doze megapixels, que são minutos de upload sem ganho de legibilidade.
      maxWidth: 2200,
      imageQuality: 88,
    );
    if (file == null) return;
    _accept(file.name, await file.readAsBytes(), 'image/jpeg');
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;

    final bytes =
        file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    _accept(file.name, bytes, 'application/pdf');
  }

  void _accept(String name, Uint8List bytes, String contentType) {
    if (!mounted) return;
    if (bytes.length > _maxBytes) {
      setState(() {
        _picked = null;
        _problem = GenerationFailure.forCode('file_too_large').detail;
      });
      return;
    }
    setState(() {
      _picked = (name: name, bytes: bytes, contentType: contentType);
      _problem = null;
    });
  }

  Future<void> _generate(String deckId) async {
    setState(() {
      _busy = true;
      _problem = null;
    });

    final api = ref.read(generationApiProvider);
    try {
      final job = switch (_source) {
        CreateSource.topic => await api.create(
            sourceType: 'topic',
            targetDeckId: deckId,
            topic: _topic.text.trim(),
            requestedCount: _count,
          ),
        // O material colado viaja no mesmo campo `topic` do contrato; o que
        // muda o comportamento do servidor é o `source_type`.
        CreateSource.text => await api.create(
            sourceType: 'text',
            targetDeckId: deckId,
            topic: _material.text.trim(),
            requestedCount: _count,
          ),
        _ => await () async {
            final picked = _picked!;
            final target = await api.createUpload(picked.contentType);
            await api.upload(target.url, picked.bytes, picked.contentType);
            return api.create(
              sourceType: picked.contentType == 'application/pdf' ? 'pdf' : 'photo',
              targetDeckId: deckId,
              uploadKey: target.uploadKey,
              requestedCount: _count,
            );
          }(),
      };

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GeneratingScreen(jobId: job.id, deckId: deckId)),
      );
      if (mounted) setState(() => _busy = false);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final failure = GenerationFailure.forException(e);
      if (failure.showsPaywall) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
        return;
      }
      if (mounted) setState(() => _problem = '${failure.title}. ${failure.detail}');
    }
  }

  Future<void> _pickDeck(List<Deck> decks) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final deck in decks)
              ListTile(
                title: Text(deck.name),
                trailing: deck.id == _effectiveDeck(decks)
                    ? const Icon(Icons.check, color: MnemosColors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(deck.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) setState(() => _deckId = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(decksProvider).valueOrNull ?? const <Deck>[];
    final quota = ref.watch(quotaProvider);
    final target = _effectiveDeck(decks);

    final ready = switch (_source) {
      CreateSource.topic => _topic.text.trim().isNotEmpty && target != null,
      CreateSource.text => _material.text.trim().isNotEmpty && target != null,
      CreateSource.pdf || CreateSource.photo => _picked != null && target != null,
      CreateSource.byHand => false,
    };

    return Column(
      children: [
        Expanded(
          child: ScreenBody(
            bottomPadding: MnemosSpacing.md,
            children: [
              const Text('Criar cards', style: MnemosText.screenTitle),
              const SizedBox(height: 6),
              const Text(
                'Escreva à mão ou deixe o Mnemos gerar a partir do seu material.',
                style: MnemosText.bodySmall,
              ),
              const SizedBox(height: MnemosSpacing.xl),
              Row(
                children: [
                  SourceTile(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Tópico',
                    selected: _source == CreateSource.topic,
                    onTap: () => _choose(CreateSource.topic, decks),
                  ),
                  const SizedBox(width: MnemosSpacing.md),
                  SourceTile(
                    icon: Icons.notes_outlined,
                    label: 'Texto',
                    selected: _source == CreateSource.text,
                    onTap: () => _choose(CreateSource.text, decks),
                  ),
                  const SizedBox(width: MnemosSpacing.md),
                  SourceTile(
                    icon: Icons.description_outlined,
                    label: 'PDF',
                    selected: _source == CreateSource.pdf,
                    onTap: () => _choose(CreateSource.pdf, decks),
                  ),
                  const SizedBox(width: MnemosSpacing.md),
                  SourceTile(
                    icon: Icons.photo_camera_outlined,
                    label: 'Foto',
                    selected: _source == CreateSource.photo,
                    onTap: () => _choose(CreateSource.photo, decks),
                  ),
                ],
              ),
              const SizedBox(height: MnemosSpacing.xl),
              _sourceBody(decks, target),
              const SizedBox(height: MnemosSpacing.xl),
              const Eyebrow('quantos cards'),
              const SizedBox(height: MnemosSpacing.md),
              Row(
                children: [
                  for (final (i, n) in _counts.indexed) ...[
                    if (i > 0) const SizedBox(width: MnemosSpacing.sm),
                    MnemosChip(
                      label: '$n',
                      selected: _count == n,
                      expand: true,
                      onTap: () => setState(() => _count = n),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: MnemosSpacing.xl),
              _QuotaCard(quota: quota),
              if (_problem != null) ...[
                const SizedBox(height: MnemosSpacing.lg),
                Text(
                  _problem!,
                  style: MnemosText.bodySmall.copyWith(color: MnemosColors.dueText),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MnemosSpacing.screen,
            0,
            MnemosSpacing.screen,
            MnemosSpacing.md,
          ),
          child: Column(
            children: [
              FilledButton(
                onPressed: (!ready || _busy) ? null : () => _generate(target!),
                child: Text(_busy ? 'Enviando…' : 'Gerar $_count cards'),
              ),
              const SizedBox(height: MnemosSpacing.sm),
              // Escrever à mão não gasta geração e não depende de rede. O
              // caminho nunca some, nem quando a cota acabou.
              //
              // Contornado e da mesma altura do primário, não um link: os dois
              // formam um par de ações. Como texto solto abaixo de uma barra
              // preenchida, ele lia como nota de rodapé — justamente quando é o
              // único caminho aberto se o primário está desligado.
              OutlinedButton(
                onPressed: _busy ? null : () => _choose(CreateSource.byHand, decks),
                child: const Text('Escrever um card à mão'),
              ),
              const SizedBox(height: MnemosSpacing.xs),
              Text(
                ready
                    ? 'Nada vira card sem você aprovar, um por vez.'
                    : switch (_source) {
                        CreateSource.topic => 'Escreva o tópico para continuar.',
                        CreateSource.text => 'Cole o texto para continuar.',
                        CreateSource.pdf => 'Escolha um PDF para continuar.',
                        CreateSource.photo => 'Escolha uma foto para continuar.',
                        CreateSource.byHand => '',
                      },
                style: MnemosText.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// O corpo muda com a origem escolhida — o assunto para tópico, o arquivo
  /// escolhido para PDF e foto.
  Widget _sourceBody(List<Deck> decks, String? target) {
    final deckName = target == null
        ? 'Nenhum baralho'
        : decks.firstWhere((d) => d.id == target).name;

    return SurfaceCard(
      radius: MnemosRadii.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(switch (_source) {
            CreateSource.topic => 'sobre o que',
            CreateSource.text => 'cole o texto',
            _ => 'material',
          }),
          const SizedBox(height: MnemosSpacing.md),
          if (_source == CreateSource.text)
            _MaterialField(controller: _material, maxChars: _maxChars, onChanged: () => setState(() {}))
          else if (_source == CreateSource.topic)
            TextField(
              controller: _topic,
              minLines: 2,
              maxLines: 4,
              maxLength: _maxChars,
              buildCounter: _noCounter,
              style: MnemosText.cardTitle.copyWith(fontWeight: FontWeight.w400, height: 1.4),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Camada de transporte: TCP, UDP e controle de congestionamento',
                hintStyle: MnemosText.body.copyWith(
                  height: 1.4,
                  color: MnemosColors.faint,
                ),
              ),
            )
          else
            // Tocável: quem cancela o seletor por engano fica com um cartão
            // vazio, e sem isto o único jeito de reabri-lo é tocar de novo no
            // azulejo que já está aceso — o que não parece um botão.
            InkWell(
              onTap: _busy
                  ? null
                  : () => _source == CreateSource.pdf ? _pickPdf() : _pickPhoto(),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _picked?.name ??
                          (_source == CreateSource.pdf
                              ? 'Escolher um PDF'
                              : 'Escolher uma foto'),
                      style: _picked == null
                          ? MnemosText.body.copyWith(color: MnemosColors.faint)
                          : MnemosText.cardTitle.copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
                  Icon(
                    _picked == null ? Icons.attach_file : Icons.change_circle_outlined,
                    size: 20,
                    color: MnemosColors.primaryDeep,
                  ),
                ],
              ),
            ),
          const SizedBox(height: MnemosSpacing.lg),
          const Divider(),
          const SizedBox(height: MnemosSpacing.md),
          Row(
            children: [
              const Text('Baralho', style: MnemosText.bodySmall),
              const Spacer(),
              Flexible(
                child: InkWell(
                  onTap: decks.isEmpty ? null : () => _pickDeck(decks),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          deckName,
                          overflow: TextOverflow.ellipsis,
                          style: MnemosText.labelSmall.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: MnemosColors.primaryDeep,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 18, color: MnemosColors.primaryDeep),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// O bloco de cota — artboard 04, o círculo em menta com o número restante.
/// O contador embutido do `TextField` desenha um "0/20000" cinza sob todo campo
/// com `maxLength`. Num teto de vinte mil isso é ruído: ninguém digita um
/// assunto perto do limite, e o número só interessa quando a régua aperta.
Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required int? maxLength,
  required bool isFocused,
}) =>
    null;

/// O campo do texto colado.
///
/// Separado do campo de tópico porque o que se espera dele é outro: um assunto
/// cabe em duas linhas e é lido como título; um capítulo colado tem centenas de
/// linhas e é lido como texto corrido. Daí o corpo em vez da serifa de título,
/// a altura maior, e o contador — que só aparece quando o limite do contrato
/// (§7.3) fica perto, para avisar antes de o servidor recusar.
class _MaterialField extends StatelessWidget {
  const _MaterialField({
    required this.controller,
    required this.maxChars,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int maxChars;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.characters.length;
    final tight = length > maxChars - 2000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          minLines: 6,
          maxLines: 12,
          maxLength: maxChars,
          buildCounter: _noCounter,
          keyboardType: TextInputType.multiline,
          style: MnemosText.body.copyWith(height: 1.5),
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Cole aqui o trecho da apostila, o resumo da aula ou as '
                'suas anotações. O Mnemos extrai os cards do que está escrito, '
                'sem inventar o que não está.',
            hintStyle: MnemosText.body.copyWith(height: 1.5, color: MnemosColors.faint),
          ),
        ),
        if (tight) ...[
          const SizedBox(height: MnemosSpacing.sm),
          Text(
            length > maxChars
                ? 'Passou do limite em ${plural(length - maxChars, "caractere", "caracteres")}. '
                    'Divida o material em duas gerações.'
                : '${plural(maxChars - length, "caractere restante", "caracteres restantes")}.',
            style: MnemosText.caption.copyWith(
              color: length > maxChars ? MnemosColors.destructive : MnemosColors.faint,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});

  final AsyncValue<({int remaining, int limit, String plan})> quota;

  @override
  Widget build(BuildContext context) {
    final value = quota.valueOrNull;

    // §5.13 — offline a resposta honesta é "não sabemos", e o app não deve
    // chutar nem a favor nem contra o usuário.
    final unknown = value == null || value.remaining < 0;
    final remaining = unknown ? null : value.remaining;

    return SurfaceCard(
      radius: MnemosRadii.control,
      background: MnemosColors.soft,
      padding: const EdgeInsets.symmetric(
        horizontal: MnemosSpacing.lg,
        vertical: MnemosSpacing.md,
      ),
      child: Row(
        children: [
          // Um glifo, não um anel menta com um dígito dentro: o mesmo anel
          // menta é "etapa concluída" na tela de gerando, e o mesmo desenho com
          // dois sentidos ensina os dois errado.
          Icon(
            unknown ? Icons.cloud_off_outlined : Icons.auto_awesome_outlined,
            size: 22,
            color: MnemosColors.settledDeep,
          ),
          const SizedBox(width: MnemosSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unknown
                      ? 'Cota desconhecida'
                      : plural(remaining!, 'geração grátis restante',
                          'gerações grátis restantes'),
                  style: MnemosText.labelSmall.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: MnemosColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unknown
                      ? 'Sem conexão com o servidor agora.'
                      : 'Assinar remove o limite.',
                  style: MnemosText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
