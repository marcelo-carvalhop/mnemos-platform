# Staging na AWS Lightsail

Uma instância Lightsail roda Postgres, API, worker e Caddy (HTTPS e build da web) com Docker Compose. Os uploads ficam num bucket do Lightsail. Custo: instância `micro_3_0` (US$ 7/mês) e bucket `small_1_0` (US$ 1/mês); o IP estático anexado é gratuito.

| Recurso | Nome | Região |
|---|---|---|
| Instância | `mnemos-1` (Ubuntu 24.04, 1 GB + 2 GB de swap) | `us-east-2a` |
| IP estático | `mnemos-ip` | `us-east-2` |
| Bucket | `mnemos-uploads-71895761` | `us-east-2` |
| Chave SSH | `mnemos-key` | `us-east-2` |

Endereço: `https://mnemos.<ip-com-hífens>.sslip.io`. O `sslip.io` resolve o nome para o IP embutido nele, o que permite certificado Let's Encrypt sem domínio próprio. Trocar por um domínio próprio exige só mudar `DOMAIN` no `.env` e apontar o DNS para o IP estático.

## Rotas

| Caminho | Destino | Quem usa |
|---|---|---|
| `/v1/*`, `/healthz` | API | app móvel e terminal (`API_BASE_URL` = endereço puro) |
| `/api/*` | API, sem o prefixo | web (mesmo contrato do proxy do `ng serve`) |
| demais | build Angular, com fallback para `index.html` | navegador |

## Ambiente

Roda como `ENVIRONMENT=staging`. Produção recusa iniciar sem attestation de dispositivo (§8.1), que o app ainda não implementa. Por isso a geração por IA fica desligada (`ANTHROPIC_API_KEY` vazio): sem attestation, qualquer um cria contas anônimas, e cada uma teria uma geração grátis na chave. Swagger desligado.

### Só para convidados

Com `INVITE_CODE` preenchido, o servidor fecha:

- criar conta (`POST /v1/auth/register`, na web e no app) exige o código de convite, sem diferenciar maiúsculas;
- contas anônimas de aparelho são recusadas (`403 account_required`), e as que já existiam deixam de funcionar: o app e a web mostram a tela de entrar;
- com `REQUIRE_EMAIL_VERIFICATION=true`, o login espera a pessoa abrir o link mandado por e-mail (`/confirmar?token=…`, válido por 7 dias). Abrir o link já entra naquele navegador.

Os e-mails saem por SMTP. No Gmail: ative a verificação em duas etapas, crie uma senha de app em myaccount.google.com/apppasswords e preencha `SMTP_USER` (o endereço) e `SMTP_PASSWORD` (a senha de app). O Gmail envia até ~500 e-mails por dia. Sem `SMTP_HOST`, o link só aparece no log do `server` (`docker compose logs server | grep confirmar`).

Trocar o código: edite `INVITE_CODE` no `.env` e rode `docker compose up -d server worker`. Quem já tem conta não é afetado.

O `.env` existe só no servidor (`/opt/mnemos/deploy/lightsail/.env`, modo 600). Para recriá-lo, use `.env.example`; senhas com `openssl rand`.

## Deploy automático da `main`

O servidor puxa: `autodeploy.sh` roda no cron a cada 3 minutos, consulta a API pública do GitHub e faz deploy do último commit da `main` quando **todos os workflows do GitHub Actions daquele commit terminaram sem falha**. Um commit que nenhum workflow cobre (caminhos que o CI ignora) entra depois de 10 minutos.

Por que puxar e não empurrar: o SCP do projeto AWS bloqueia provedores OIDC no IAM, então o GitHub não teria como ganhar acesso à AWS para abrir o SSH só durante o deploy. Puxar não precisa de segredo nenhum (o repositório é público) e mantém o SSH fechado.

Cada release passa por `apply.sh`: instala os arquivos, builda a imagem da API, migra, reinicia e confere `/healthz`. Se a checagem falhar, volta a imagem anterior da API. Migrações são aditivas (§11.4), então a imagem anterior roda no esquema novo.

```bash
tail -f /opt/mnemos/logs/autodeploy.log            # acompanhar
cat /opt/mnemos/.deployed-sha                      # o que está no ar
/opt/mnemos/deploy/lightsail/autodeploy.sh --ref dev --force   # outra branch, agora
```

Um commit que falhou no CI ou no deploy fica em `/opt/mnemos/.failed-sha` e não é tentado de novo; o próximo commit na `main` destrava.

## Deploy manual

Da máquina de desenvolvimento, com Docker e a chave SSH, para mandar a árvore local sem passar pelo GitHub:

```bash
MNEMOS_HOST=<ip> MNEMOS_SSH_KEY=~/.ssh/mnemos-lightsail.pem deploy/lightsail/deploy.sh
```

Builda a web num container Node local, envia os arquivos por SSH e roda o mesmo `apply.sh`. O autodeploy da `main` substitui esse deploy na próxima mudança da `main`.

SSH: a porta 22 só aceita o IP de quem configurou. Para liberar outro IP:

```bash
aws lightsail put-instance-public-ports --instance-name mnemos-1 --profile mnemos \
  --port-infos "fromPort=22,toPort=22,protocol=tcp,cidrs=<ip>/32" \
               "fromPort=80,toPort=80,protocol=tcp" "fromPort=443,toPort=443,protocol=tcp"
```

## Backup

`backup.sh` roda todo dia às 03:30 UTC pelo cron do usuário `ubuntu` (instalado pelo `apply.sh`, junto com o do autodeploy): `pg_dump` compactado, 7 dias em `/opt/mnemos/backups` e 30 dias no bucket em `backups/`. Restaurar:

```bash
gunzip -c mnemos-<data>.sql.gz | docker compose exec -T postgres psql -U mnemos -d mnemos
```

## Terminal (firmware)

O terminal usa HTTPS e precisa das CAs raiz em `BACKEND_ROOT_CA` ou `/backend_ca.pem`. O certificado é ECDSA P-256 e a cadeia servida hoje (verificada em 2026-11-20) é:

```
servidor -> YE2 -> ISRG Root YE -> ISRG Root X2 (cross) -> ISRG Root X1 (cross)
```

Grave um PEM com as três raízes (**ISRG Root X1**, **ISRG Root X2** e **ISRG Root YE**), em vez de só a X1. Assim a placa valida pelo caminho atual e continua validando quando o Let's Encrypt deixar de servir as assinaturas cruzadas. São raízes, não o certificado do servidor, então as renovações automáticas não afetam a placa. Ainda não testado em hardware.
