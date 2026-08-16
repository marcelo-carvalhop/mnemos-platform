# Segurança

Não publique credenciais Wi-Fi, tokens de terminal, chaves de API, certificados privados, arquivos `.env`, keystores Android ou credenciais de nuvem. O `.gitignore` cobre os nomes mais comuns, mas a responsabilidade final continua sendo de quem cria o commit.

Antes de cada publicação, execute `tools/repository/check-before-commit.sh` e examine `git diff --cached`. Se uma credencial real já tiver sido commitada, removê-la em um commit posterior não é suficiente: revogue-a imediatamente e trate o histórico como comprometido.

Tokens de terminal devem ser distintos dos tokens de sessão do usuário e limitados aos recursos autorizados ao dispositivo. Credenciais Wi-Fi devem ser persistidas somente no terminal após provisionamento explícito e nunca devem aparecer em logs, fixtures ou documentação pública.

Relatórios de vulnerabilidade não devem ser publicados como issue aberta quando contiverem detalhes exploráveis. Defina um canal privado de contato antes de abrir o repositório ao público.
