# Cliente móvel

O aplicativo Flutter fica em `app/mobile/`. Ele mantém persistência local, autoria/organização, configuração de terminal, desired-state sync, estatísticas e acesso aos serviços de backend. Ele **não é uma superfície de estudo**: prompts, revelação de respostas e ratings pertencem ao terminal físico.

Os packages Dart que compõem seu domínio permanecem em `app/mobile/packages/` porque o `pubspec.yaml` utiliza referências relativas nessa estrutura. A representação pública dos dados continua definida por `spec/`, não pelas tabelas Drift ou pelas classes Dart.
