# Documentação técnica Mnemos

Este índice descreve a ramificação `feature/t5-s3-touch` auditada em 28/09/2026. A documentação de releases anteriores foi preservada para investigação histórica, mas não deve ser lida como especificação do produto atual. Quando houver desacordo, examine a versão do contrato, o código do produtor e do consumidor e seus testes; a divergência deve ser registrada e corrigida antes de afirmar conformidade.

## Sistema corrente

| Tema | Documento de entrada | Implementação de referência |
| --- | --- | --- |
| Estado e bloqueadores | [status.md](status.md) | Workflows em `.github/workflows/` e checklists de hardware. |
| Arquitetura | [architecture/overview.md](architecture/overview.md) | `app/`, `backend/`, `firmware/`, `shared/`. |
| Persistência e DER lógico | [architecture/data-model.md](architecture/data-model.md) | `backend/app/models.py`, migrações Alembic, Drift e armazenamento do terminal. |
| Sincronização e conectividade | [architecture/synchronization.md](architecture/synchronization.md) e [connectivity.md](architecture/connectivity.md) | Clientes de sync, API e firmware. |
| Integração T5 Touch | [integration/t5-touch.md](integration/t5-touch.md) | `firmware/t5-touch/src/`, `backend/app/terminal/`, `app/mobile/lib/device/`. |
| Interoperabilidade externa | [developers/third-party-integration.md](developers/third-party-integration.md) | Schemas e protocolos em `spec/`. |
| Setup de desenvolvimento | [developers/getting-started.md](developers/getting-started.md) | `compose.yaml`, READMEs de componente e workflows. |
| HMI por toque | [ux/HMI_T5_TOUCH_GUIDELINES_v0.1.md](ux/HMI_T5_TOUCH_GUIDELINES_v0.1.md) | Firmware, checklist HMI e ensaios em bancada. |

A documentação de API de terminal por versão está em `spec/protocol/`; schemas JSON em `spec/schemas/`; o contrato interno que gera enums e constantes para os clientes oficiais está em `shared/contract.yaml`. Um documento de protocolo v1 ou v0.4 não especifica automaticamente a variante touch em v0.7. Os arquivos de `docs/releases/`, `docs/internal/specs/`, `docs/internal/plans/` e os documentos com sufixo de versão anterior são registros datados, úteis para rastrear decisões, mas não constituem o estado atual.

## Regra de manutenção

Uma alteração de contrato precisa atualizar o schema afetado, a documentação do protocolo, a serialização de quem envia, a validação de quem recebe e um teste cruzado com payload real. Para o terminal, manter também a matriz de compatibilidade e o checklist de falhas em [integration/t5-touch.md](integration/t5-touch.md). Não marcar um teste físico como concluído apenas porque o firmware compilou ou porque o backend aceitou um fixture escrito à mão.
