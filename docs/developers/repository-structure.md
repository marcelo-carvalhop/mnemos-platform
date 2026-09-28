# Estrutura do monorepositório

| Diretório | Responsabilidade atual |
| --- | --- |
| `app/mobile/` | Flutter, domínio local, banco Drift, estudo e integração física do terminal. |
| `app/web/` | Angular 22, estudo e demais rotas de produto por meio da API. |
| `backend/` | API FastAPI, modelos, migrações, worker e testes de serviço. |
| `firmware/cyd/`, `firmware/t5/`, `firmware/t5-touch/` | Protótipo anterior, T5 sem touch e T5 Touch nesta ramificação; builds independentes. |
| `shared/` | Contrato interno `contract.yaml` e geração de código para implementações oficiais. |
| `spec/` | JSON Schemas, protocolos públicos versionados, exemplos e validação de interoperabilidade. |
| `docs/` | Arquitetura corrente, integração, status, documentação de desenvolvimento e histórico de releases/decisões. |
| `tools/` e `.github/workflows/` | Validação, utilitários, experimentos preservados e automação por componente. |
| `packages/` | Reserva para pacotes que venham a ser compartilhados entre aplicações; os pacotes Dart atuais ficam em `app/mobile/packages/`. |

Uma alteração do formato de revisão atravessa `spec/schemas/`, serialização no firmware, parser móvel, validador do backend e testes. Uma mudança do contrato interno atravessa `shared/contract.yaml` e todos os arquivos gerados. Não duplicar uma regra de domínio em documentos com nomes de release diferentes sem explicar sua versão e sua autoridade. Para a topologia completa, veja [../architecture/overview.md](../architecture/overview.md).
