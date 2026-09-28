# Mnemos T5 Touch — preview.4.2 config fix r2

Este reparo corrige a falha do aplicador original da `preview.4.2`.

O erro original ocorreu nesta sequência:

1. o aplicador substituiu `APP_VERSION` por um bloco contendo também
   `OTA_GENERATION=70402/70403`;
2. depois tentou remover a antiga declaração `OTA_GENERATION=70402`;
3. a substituição removeu a primeira ocorrência encontrada, que já era a
   declaração `70402` dentro do novo ramo SOURCE;
4. a declaração antiga e incondicional `70402` permaneceu abaixo do bloco.

O resultado fazia o TARGET enxergar simultaneamente `70403` e `70402`.

A revisão r2 não depende de indentação nem da forma quebrada atual. Ela:

- encontra o bloco `MNEMOS_OTA_TEST_SOURCE` que contém `APP_VERSION`;
- substitui o bloco inteiro pela forma canônica;
- remove todas as declarações `OTA_GENERATION` fora desse bloco;
- exige exatamente uma definição `70402` e uma `70403`.

Nenhuma nova geração OTA é consumida.
