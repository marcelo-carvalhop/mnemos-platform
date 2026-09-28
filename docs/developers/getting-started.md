# Primeiros passos para desenvolvimento

Parta do [README da raiz](../../README.md) para identificar os componentes e do [índice técnico](../README.md) para escolher o documento vigente. A ramificação `feature/t5-s3-touch` contém implementações em todos os quatro componentes; guias datados de v0.3–v0.5 são históricos. Antes de editar um protocolo, verifique o schema, o produtor, o consumidor e os testes cruzados descritos em [../integration/t5-touch.md](../integration/t5-touch.md).

## Ambiente de serviços

A partir da raiz, copie `backend/.env.example` para `.env`, configure segredos locais e execute, nessa ordem:

```bash
docker compose up -d postgres minio minio-init
docker compose run --rm migrate
docker compose up -d server worker
```

`compose.yaml` é o ambiente de desenvolvimento. `/healthz` indica processo ativo, enquanto `/readyz` verifica banco. A geração externa exige chave de API no ambiente do servidor e do worker; sem ela, as demais rotas podem ser desenvolvidas sem geração real. Não publicar `.env` ou credenciais de dispositivo.

## Clientes e terminal

| Diretório | Preparação e verificação local |
| --- | --- |
| `app/mobile/` | `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`. |
| `app/web/` | Usar Node de `.nvmrc`; `npm ci`, `npm run lint:format`, `npm run test:ci`, `npm run build`. |
| `backend/` | `pip install -e '.[dev]'` em ambiente virtual; executar `pytest` com o PostgreSQL de testes disponível. |
| `firmware/t5-touch/` | `pio run` compila a build de bancada; perfil de produto é explícito. Consultar `docs/BENCH_BUILDS.md` e o checklist antes de upload. |

O contrato gerado deve passar `python shared/generate.py --check`. Para validar os schemas públicos e exemplos localmente, instale `jsonschema>=4` e `referencing` no ambiente Python e execute `python tools/schema-validator/validate_mnemos_examples.py`; o workflow `schemas.yml` instala essas dependências. Os workflows separados em `.github/workflows/` cobrem schemas, móvel, web, backend e o build do **CYD**. Não há job de build do T5 Touch; sua compilação e os ensaios físicos precisam ser conduzidos separadamente.

## Rede e integração

Um ESP32 real precisa de URL da API alcançável pela LAN ou HTTPS com CA confiável. `10.0.2.2` resolve o host para o emulador Android, não para o terminal. O provisionamento local não transfere o bearer da conta ao firmware. Antes de ensaiar revisões remotas, leia [a incompatibilidade de payload](../integration/t5-touch.md#incompatibilidade-de-payload-bloqueador); a API atual responde 422 ao lote gerado por esta versão do firmware.
