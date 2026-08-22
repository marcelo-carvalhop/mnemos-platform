# Especificação de autoria de cartões v0.5

O editor deve privilegiar uma peça de informação por card e usar avisos não bloqueantes quando uma resposta parece conter enumerações extensas. O objetivo é melhorar a qualidade do sinal do scheduler, não policiar o texto do usuário.

`open_recall` exige prompt e resposta de referência. `cloze` exige uma frase/contexto e a resposta da lacuna. `application` exige um problema curto e resposta de referência; problemas longos devem ser decompostos. `multiple_choice` exige de duas a quatro opções no CYD e exatamente uma resposta correta. `true_false` usa duas alternativas fixas e um índice correto.

Múltipla escolha é adequada quando reconhecimento objetivo é pedagogicamente relevante; não deve substituir automaticamente recall aberto quando o objetivo é produção ativa. A correção de `multiple_choice` e `true_false` é automática no terminal. Os demais tipos são autoavaliados no protótipo CYD.

Todo card deve ter `id` estável, `deckId`, `type`, `content`, `metadata.revision` e schema `mnemos.card/v2`. Mudança editorial incrementa `revision`, mas não troca o `id`, salvo quando a mudança representa semanticamente outro conhecimento.
