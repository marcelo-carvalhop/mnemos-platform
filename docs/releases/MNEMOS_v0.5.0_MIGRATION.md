# Migração v0.4.1 -> v0.5.0-preview.3

A mudança é incompatível no transporte local: BLE deixa de ser obrigatório e Device Protocol passa a v4. App/web devem migrar para Card v2, Review v2 e Sync v2. Cards `basic` já persistidos localmente são migrados pelo firmware para `open_recall`. Estados antigos sem D/S recebem uma aproximação inicial de S derivada de `intervalSeconds`; a partir do primeiro review v0.5 passam a usar o LearningModel novo.

Não copie arquivos de app/mobile deste pacote sobre o trabalho do outro desenvolvedor. O overlay entregue contém firmware, specs e documentação justamente para permitir integração paralela.
