# Primeiros passos para desenvolvedores

O ponto de entrada depende do objetivo. Quem deseja contribuir com o produto oficial deve partir do `README.md` da raiz e do componente correspondente. Quem deseja apenas implementar compatibilidade deve começar por `third-party-integration.md` e pelos artefatos normativos em `../../spec/`.

O aplicativo móvel permanece em `app/mobile/`, o backend em `backend/`, o firmware provisório em `firmware/cyd/` e o futuro cliente web em `app/web/`. Nenhuma implementação externa deve depender da estrutura interna do Drift/SQLite ou da organização em memória do firmware.

Para preparar Git e GitHub em uma cópia recém-extraída, consulte `../../SETUP_GITHUB.md`.
