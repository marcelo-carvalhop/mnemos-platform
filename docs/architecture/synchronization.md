# Sincronização

A sincronização externa utiliza objetos versionados em `spec/`. O terminal recebe snapshots completos somente após validação de capacidade e compatibilidade e devolve revisões como eventos idempotentes. Estado interno de armazenamento não deve atravessar a fronteira do protocolo.
