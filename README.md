# Mnemos Platform

Mnemos é uma plataforma físico-digital para estudo deliberado e revisão adaptativa. Este repositório reúne os clientes oficiais, firmware dos terminais, backend de referência, contratos públicos de interoperabilidade e documentação técnica.

A organização é deliberadamente monorepo porque, nesta fase, alterações de protocolo ainda afetam aplicativo, backend e firmware de forma coordenada. Os contratos em `spec/`, entretanto, são independentes das implementações: um serviço externo pode ser compatível com Mnemos sem reutilizar o aplicativo, o backend ou o firmware oficiais.

## Componentes

| Caminho | Responsabilidade |
|---|---|
| `app/mobile/` | Aplicativo Flutter para Android/iOS, provisionamento, autoria, gerenciamento e sincronização. |
| `app/web/` | Espaço reservado para o futuro cliente web oficial. Nenhum framework foi escolhido ainda. |
| `backend/` | Backend de referência, API, autenticação, persistência, sincronização e geração. |
| `firmware/cyd/` | Firmware atual do protótipo ESP32-2432S028 (CYD). |
| `firmware/t5/` | Espaço reservado para o port para LILYGO T5 4.7". |
| `spec/` | Definições normativas de schemas, protocolos e fixtures canônicos. |
| `docs/` | Explicações de arquitetura, implementação, segurança, releases e documentos de referência. |
| `shared/` | Contrato interno compartilhado entre cliente Flutter e backend, com geração de código. |
| `tools/` | Validadores, verificações de repositório e experimentos preservados. |

## Versões atuais

O produto está na linha `0.3.x`. Os protocolos possuem versionamento independente: `mnemos.card/v1`, `mnemos.deck/v1`, `mnemos.card-state/v1`, `mnemos.review/v1`, `mnemos.sync/v1`, Device Protocol v2 e Backend API v1.

O histórico funcional encontra-se em `CHANGELOG.md`. A documentação para implementadores externos começa em `docs/developers/third-party-integration.md`, enquanto os artefatos normativos ficam em `spec/`.

## Primeira configuração do GitHub

Depois de extrair este pacote, leia `SETUP_GITHUB.md` antes de executar `git add`. O guia cobre identidade Git, autenticação SSH, criação do repositório remoto, verificação de segredos, primeiro commit, primeiro push, tag `v0.3.0` e proteção da branch `main`.

## Desenvolvimento rápido

Para o cliente móvel:

```bash
cd app/mobile
flutter pub get
flutter analyze
flutter test
```

Para o firmware CYD:

```bash
cd firmware/cyd
pio run
```

Para o backend, a configuração local pode ser iniciada pela raiz:

```bash
cp backend/.env.example .env
docker compose up -d postgres minio minio-init
# migração é deliberadamente uma operação separada
docker compose run --rm migrate
docker compose up -d server worker
```

## Licença

Nenhuma licença de código foi selecionada neste pacote. Antes de tornar o repositório público ou aceitar contribuições externas, defina a política em `docs/governance/licensing.md` e adicione um arquivo `LICENSE` apropriado.
