# Especificação normativa Mnemos

`spec/` contém os contratos que definem interoperabilidade. Diferentemente de `docs/`, que explica decisões e implementações, esta árvore deve ser tratada como fonte normativa para schemas, protocolo do terminal, provisionamento e exemplos canônicos.

Os schemas possuem versionamento independente da versão do produto. Um lançamento Mnemos posterior pode continuar usando `mnemos.card/v1`; uma mudança incompatível no formato de card deve gerar uma nova versão do contrato, não alterar silenciosamente `v1.json`.

O exemplo em `examples/networking/` é o fixture canônico de Redes de Computadores com 10 cards.
