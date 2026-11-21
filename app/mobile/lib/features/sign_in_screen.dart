import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../providers_sync.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../ui/ui.dart';

/// Entrar ou criar conta, quando o servidor é só para convidados.
///
/// Num servidor aberto o app nunca mostra esta tela: a conta nasce anônima e
/// presa ao aparelho (§8.1). Um servidor com `INVITE_CODE` recusa isso com
/// `account_required`, e então a pessoa entra com e-mail e senha — criados com
/// o código de convite e confirmados pelo link que chega por e-mail.
///
/// Cards criados aqui e nunca sincronizados vão para a conta na primeira
/// sincronização. Os que já pertencem a outra conta (a anônima de antes do
/// convite) saem do aparelho e continuam no servidor, naquela conta: o
/// servidor não deixa linhas mudarem de dono (SyncClient.adoptAccount).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, required this.onSignedIn, this.onCancel});

  final VoidCallback onSignedIn;

  /// Presente quando a tela foi aberta por escolha (Configurações → Entrar com
  /// e-mail) e não imposta pelo servidor: aí ela tem como fechar.
  final VoidCallback? onCancel;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Mode { signIn, create, sent }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _invite = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _unconfirmed = false;
  String? _problem;
  String? _notice;

  /// Na dúvida, pede o convite: um campo a mais custa menos que um cadastro
  /// recusado sem explicação.
  bool _inviteRequired = true;

  @override
  void initState() {
    super.initState();
    for (final c in [_invite, _email, _password]) {
      c.addListener(() => setState(() {}));
    }
    ref
        .read(authApiProvider)
        .options()
        .then((o) {
          if (mounted) setState(() => _inviteRequired = o.inviteRequired);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _invite.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _valid =>
      _email.text.contains('@') &&
      _password.text.length >= 8 &&
      (_mode != _Mode.create ||
          !_inviteRequired ||
          _invite.text.trim().isNotEmpty);

  void _switch(_Mode mode) => setState(() {
    _mode = mode;
    _problem = null;
    _notice = null;
    _unconfirmed = false;
  });

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _problem = null;
      _notice = null;
      _unconfirmed = false;
    });

    final auth = ref.read(authApiProvider);
    final deviceId = await ref.read(deviceIdProvider.future);
    final email = _email.text.trim();

    try {
      final String userId;
      if (_mode == _Mode.create) {
        final result = await auth.register(
          email: email,
          password: _password.text,
          deviceId: deviceId,
          inviteCode: _invite.text,
        );
        final signedInAs = result.userId;
        if (result.outcome == RegisterOutcome.verificationSent ||
            signedInAs == null) {
          setState(() {
            _busy = false;
            _mode = _Mode.sent;
          });
          return;
        }
        userId = signedInAs;
      } else {
        userId = await auth.login(
          email: email,
          password: _password.text,
          deviceId: deviceId,
        );
      }
      // Before the first sync with this account: cards synced under another
      // account cannot move into it (see SyncClient.adoptAccount).
      await ref.read(syncClientProvider).adoptAccount(userId);
      widget.onSignedIn();
    } on Offline {
      _fail('Sem conexão com o servidor. Tente de novo.');
    } on ApiException catch (e) {
      _unconfirmed = e.detail == 'email_not_verified';
      _fail(_explain(e));
    } on Object {
      _fail(
        _mode == _Mode.create
            ? 'Não consegui criar a conta agora.'
            : 'Não consegui entrar agora.',
      );
    }
  }

  String _explain(ApiException e) {
    if (e.detail == 'invite_invalid') {
      return 'Esse código de convite não confere.';
    }
    if (e.detail == 'email_not_verified') {
      return 'Falta confirmar o e-mail. Abra o link que mandamos quando você criou a conta.';
    }
    if (e.statusCode == 409) return 'Já existe uma conta com este e-mail.';
    if (e.statusCode == 401 || e.statusCode == 403) {
      return 'E-mail ou senha não conferem.';
    }
    if (e.statusCode == 422) {
      return 'Confira o e-mail e use ao menos 8 caracteres na senha.';
    }
    if (e.isTransient) {
      return 'O servidor tropeçou. Tente de novo em instantes.';
    }
    return 'Não consegui agora. Tente de novo.';
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = message;
    });
  }

  Future<void> _resend() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await ref.read(authApiProvider).resendVerification(email);
      setState(() {
        _problem = null;
        _unconfirmed = false;
        _notice =
            'Se houver uma confirmação pendente para $email, um link novo está a caminho.';
      });
    } on Offline {
      setState(() => _problem = 'Sem conexão com o servidor. Tente de novo.');
    } on Object {
      setState(
        () => _problem = 'Não consegui mandar agora. Tente em um minuto.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ScreenBody(
          children: [
            if (widget.onCancel != null)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Fechar',
                ),
              )
            else
              const SizedBox(height: MnemosSpacing.xl),
            const _Brand(),
            const SizedBox(height: 36),
            ...switch (_mode) {
              _Mode.sent => _sent(),
              _ => _form(),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _sent() => [
    const Text('Confirme seu e-mail', style: MnemosText.screenTitleWrapped),
    const SizedBox(height: 10),
    Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Mandamos um link para '),
          TextSpan(
            text: _email.text.trim(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: MnemosColors.ink,
            ),
          ),
          const TextSpan(
            text:
                '. Abra o e-mail, toque em Confirmar e-mail e volte aqui para entrar.',
          ),
        ],
      ),
      style: MnemosText.bodyLong.copyWith(
        fontSize: 15,
        color: MnemosColors.muted,
      ),
    ),
    const SizedBox(height: 10),
    const Text(
      'Não chegou em um minuto? Olhe o spam ou peça outro link.',
      style: MnemosText.bodySmall,
    ),
    const SizedBox(height: 24),
    if (_notice != null) ...[_Note(_notice!), const SizedBox(height: 14)],
    if (_problem != null) ...[
      _Note(_problem!, problem: true),
      const SizedBox(height: 14),
    ],
    FilledButton(
      onPressed: _busy
          ? null
          : () {
              _password.clear();
              _switch(_Mode.signIn);
            },
      child: const Text('Já confirmei, entrar'),
    ),
    const SizedBox(height: 10),
    OutlinedButton(
      onPressed: _busy ? null : _resend,
      child: const Text('Mandar o link de novo'),
    ),
  ];

  List<Widget> _form() {
    final creating = _mode == _Mode.create;
    return [
      Text(
        creating ? 'Criar conta' : 'Entrar',
        style: MnemosText.screenTitleWrapped,
      ),
      const SizedBox(height: 10),
      Text(
        creating
            ? (_inviteRequired
                  ? 'O Mnemos está aberto só para convidados. Use o código que você recebeu.'
                  : 'Seus cards e seu histórico, em qualquer aparelho.')
            : 'Continue de onde parou, em qualquer superfície.',
        style: MnemosText.bodyLong.copyWith(
          fontSize: 15,
          color: MnemosColors.muted,
        ),
      ),
      const SizedBox(height: 24),
      if (creating && _inviteRequired) ...[
        _Field(
          label: 'Código de convite',
          controller: _invite,
          enabled: !_busy,
          autofillHints: const [],
        ),
        const SizedBox(height: 16),
      ],
      _Field(
        label: 'E-mail',
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
      ),
      const SizedBox(height: 16),
      _Field(
        label: 'Senha',
        controller: _password,
        enabled: !_busy,
        obscure: true,
        helper: creating ? 'Ao menos 8 caracteres.' : null,
        autofillHints: [
          creating ? AutofillHints.newPassword : AutofillHints.password,
        ],
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 20),
      if (_problem != null) ...[
        _Note(_problem!, problem: true),
        if (_unconfirmed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _resend,
              child: const Text('Mandar o link de novo'),
            ),
          ),
        const SizedBox(height: 14),
      ],
      if (_notice != null) ...[_Note(_notice!), const SizedBox(height: 14)],
      FilledButton(
        onPressed: _valid && !_busy ? _submit : null,
        child: Text(
          _busy ? 'Um momento…' : (creating ? 'Criar conta' : 'Entrar'),
        ),
      ),
      const SizedBox(height: 18),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            creating
                ? 'Já tem conta?'
                : (_inviteRequired
                      ? 'Recebeu um convite?'
                      : 'Ainda não tem conta?'),
            style: MnemosText.bodySmall,
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _switch(creating ? _Mode.signIn : _Mode.create),
            child: Text(creating ? 'Entrar' : 'Criar uma conta'),
          ),
        ],
      ),
    ];
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandMark(),
        const SizedBox(width: 10),
        const Text(
          'Mnemos',
          style: TextStyle(
            fontFamily: MnemosFonts.sans,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: MnemosColors.ink,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
    this.obscure = false,
    this.keyboardType,
    this.helper,
    this.autofillHints,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? helper;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure && keyboardType != TextInputType.emailAddress,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: label,
        helperText: helper,
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.problem = false});

  final String text;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: problem ? MnemosColors.againSurface : MnemosColors.sunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.45,
          color: problem ? MnemosColors.again : MnemosColors.muted,
        ),
      ),
    );
  }
}
