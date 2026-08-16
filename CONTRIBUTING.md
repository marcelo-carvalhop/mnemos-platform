# Contribuindo com Mnemos

O fluxo recomendado mantém `main` estável. Mudanças devem ocorrer em branches temporárias com nomes como `feature/wifi-provisioning`, `fix/cyd-touch`, `docs/backend-guide` ou `test/schema-validation`, seguidas por Pull Request.

Commits devem descrever uma unidade lógica de alteração. O padrão adotado é compatível com Conventional Commits, usando prefixos como `feat`, `fix`, `docs`, `refactor`, `test`, `build` e `chore`. Exemplos: `feat(firmware): add T5 display abstraction` e `fix(mobile): preserve terminal token after reprovisioning`.

Antes de abrir um Pull Request, execute `tools/repository/check-before-commit.sh`. Quando as toolchains estiverem disponíveis, execute também análise e testes do componente modificado. Uma alteração em `spec/` deve ser acompanhada de fixture ou teste de conformidade e deve considerar compatibilidade com versões já publicadas.

Mudanças incompatíveis nos contratos públicos não devem substituir silenciosamente um schema existente. Crie uma nova versão de protocolo quando a semântica obrigatória mudar.
