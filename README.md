# Mnemos Platform

Mnemos é uma plataforma de estudo com recuperação ativa e revisão adaptativa. O produto abrange aplicativo móvel, aplicação web, backend e um terminal dedicado para sessões com baixa distração. A biblioteca, as revisões e o progresso pertencem à plataforma; o terminal é uma forma adicional de acesso. Este monorepositório reúne as implementações oficiais, contratos compartilhados, schemas públicos e documentação técnica.

## Componentes

| Diretório | Implementação nesta ramificação |
| --- | --- |
| [`app/mobile/`](app/mobile/) | Flutter para Android/iOS; estudo, autoria, progresso, persistência local, sincronização e configuração de terminal. |
| [`app/web/`](app/web/) | Angular 22; estudo, biblioteca, criação, progresso, conta e dispositivo. O espelho de estudo vive em memória e é reconstruído do servidor ao recarregar. |
| [`backend/`](backend/) | FastAPI, PostgreSQL, autenticação, sincronização, tarefas de geração e API de terminal. O worker executa tarefas em segundo plano. |
| [`firmware/t5-touch/`](firmware/t5-touch/) | Firmware do T5-4.7-S3 Touch; HMI por toque, estudo local, biblioteca no microSD, sincronização e OTA A/B local. O ambiente padrão de compilação é de bancada. |
| [`firmware/t5/`](firmware/t5/) | Variante T5 sem touch, mantida separadamente. |
| [`firmware/cyd/`](firmware/cyd/) | Protótipo anterior e referência para compatibilidade histórica. |
| [`shared/`](shared/) e [`spec/`](spec/) | Contrato interno gerado para os clientes oficiais e schemas/protocolos públicos versionados, respectivamente. |

As versões do produto, do firmware, dos schemas e das APIs evoluem independentemente. Não se deve inferir compatibilidade pelo número de uma release. A matriz de versões e o estado efetivo da integração estão em [docs/status.md](docs/status.md) e [docs/integration/t5-touch.md](docs/integration/t5-touch.md).

## Arquitetura e documentação

O [índice técnico](docs/README.md) distingue a documentação corrente dos registros históricos. Comece pela [visão de arquitetura](docs/architecture/overview.md), pelo [modelo de dados](docs/architecture/data-model.md) e pelo [guia de integração](docs/developers/third-party-integration.md). Para alterar uma interface entre componentes, compare os schemas em `spec/`, `shared/contract.yaml`, os handlers e os testes de ambos os lados. Documentação descritiva não substitui uma verificação ponta a ponta.

## Desenvolvimento local

Na raiz, inicie banco e armazenamento, aplique as migrações e só então suba API e worker:

```bash
cp backend/.env.example .env
docker compose up -d postgres minio minio-init
docker compose run --rm migrate
docker compose up -d server worker
```

O aplicativo móvel é preparado em `app/mobile/` com `flutter pub get`, `flutter analyze` e `flutter run`. A web é preparada em `app/web/` com `npm ci`, `npm run test:ci` e `npm start`; a versão de Node consta em `app/web/.nvmrc`. Para o terminal por toque, `cd firmware/t5-touch && pio run` compila o perfil de bancada; consulte o [guia do firmware](firmware/t5-touch/README.md) antes de gravar o hardware. O contrato interno pode ser verificado por `python shared/generate.py --check`, e os schemas por `python tools/schema-validator/validate_mnemos_examples.py`.

O backend físico acessado por um terminal precisa de um endereço alcançável pela rede local ou de HTTPS com CA confiável; `localhost` e `10.0.2.2` do emulador não servem como endereço do ESP32. O envio direto de revisões do T5 Touch ainda contém uma incompatibilidade de payload com a API. O diagnóstico e os critérios para encerrá-la estão documentados em [docs/integration/t5-touch.md](docs/integration/t5-touch.md).

## Escopo desta ramificação

`feature/t5-s3-touch` contém as evoluções do terminal por toque sobre a base dos demais componentes. Os checklists de bancada registram verificações ainda não assinaladas; a presença de implementação não equivale a comprovação de integração completa. O histórico de releases permanece em [`docs/releases/`](docs/releases/) e [`CHANGELOG.md`](CHANGELOG.md).

Nenhuma licença de código foi escolhida; consulte [docs/governance/licensing.md](docs/governance/licensing.md) antes de reutilização externa.
