# Mnemos — Requisitos Técnicos do Motor de Aprendizagem

*Documento de engenharia derivado de "Mnemos — Metodologia Científica de Estudo". Cada requisito abaixo existe para implementar um mecanismo já fundamentado naquele documento; este arquivo não introduz nenhum princípio pedagógico novo, apenas o traduz em sistema.*

---

## Como ler este documento

Cada capacidade é decomposta em três níveis de abstração, do mais alto ao mais técnico:

| Nível | Nome | Responde a | Formato |
|---|---|---|---|
| 1 | **Capacidade** | Por que isso existe, o que o sistema garante | Prosa curta, ligada à seção da Metodologia |
| 2 | **Comportamento** | O que um usuário ou o sistema observa acontecer | Cenários Given/When/Then |
| 3 | **Especificação técnica** | Como isso é calculado, armazenado e testado | Fórmulas, schemas, pseudocódigo, casos de teste |

Given/When/Then é usado em todo lugar onde descreve comportamento observável (Nível 2) ou um caso de teste técnico verificável (Nível 3). Onde o Nível 3 é fundamentalmente uma fórmula ou um schema de dados, e não um comportamento, ele é apresentado como especificação direta, porque forçar esses casos em Given/When/Then obscureceria, não esclareceria, a informação.

Parâmetros numéricos marcados como **(a calibrar)** têm sua estrutura definida por este documento mas seus valores finais dependem de dados reais de uso, coerente com a seção 3.2 da Metodologia: o modelo é determinístico, não é estático para sempre em seus coeficientes internos, apenas nunca deixa de ser uma fórmula auditável.

---

## Tabela de rastreabilidade

| ID | Capacidade | Seção da Metodologia |
|---|---|---|
| RF-01 | Motor de Repetição Espaçada (DSR) | 3.1 |
| RF-02 | Sessão de Estudo e Fila de Revisão | 2.8, 7.1, 7.2, 7.3 |
| RF-03 | Autoavaliação e Registro de Confiança | 2.3, 2.7 |
| RF-04 | Controle do Usuário sobre o Agendamento | 3.3 |
| RF-05 | Modo Cram | 3.4 |
| RF-06 | Geração Assistida de Cartões por IA | 3.2 |
| RF-07 | Editor e Tipos de Cartão | 4.1, 4.3 |
| RF-08 | Painel de Métricas | 6.2 |
| RF-09 | Índice de Prontidão | 7.4 |

---

## RF-01 — Motor de Repetição Espaçada (DSR)

### Nível 1 — Capacidade

O sistema deve calcular e manter, para cada cartão e cada usuário, três variáveis (Dificuldade D, Estabilidade S, Recuperabilidade R) que determinam quando esse cartão específico deve ser revisado novamente. Este motor é o núcleo de todo o produto: nenhuma outra capacidade deste documento funciona sem ele.

### Nível 2 — Comportamento

**Cenário: primeira revisão de um cartão novo**
```
Dado um cartão que nunca foi revisado
Quando o usuário completa a primeira revisão e escolhe uma classificação de recordação
Então o sistema inicializa D e S com valores padrão associados àquela classificação
E agenda a próxima revisão de acordo com a estabilidade inicial resultante
```

**Cenário: revisão bem-sucedida de um cartão já maduro**
```
Dado um cartão com estabilidade S e histórico de revisões anteriores
Quando o usuário revisa o cartão e classifica a resposta como "bom" ou "fácil"
Então a nova estabilidade é maior que a estabilidade anterior
E a próxima data de revisão fica mais distante que o intervalo anterior
```

**Cenário: erro em uma revisão**
```
Dado um cartão com estabilidade S
Quando o usuário erra a resposta
Então a estabilidade é reduzida
E o cartão entra em uma fila de reaprendizado de curto prazo antes de retornar ao ciclo espaçado normal
```

**Cenário: montagem da fila diária**
```
Dado um cartão com estabilidade S e T dias desde a última revisão
Quando o sistema monta a fila de revisão do dia
Então a recuperabilidade R é recalculada usando T e S atuais
E o cartão entra na fila somente se R estiver na ou abaixo da meta de retenção configurada
```

### Nível 3 — Especificação técnica

**Curva de recuperabilidade.** Consistente com a literatura mais recente sobre modelos de esquecimento (função de potência, que se ajusta melhor a dados empíricos do que a exponencial clássica usada em algoritmos como o SM-2 original):

```
R(t, S) = (1 + t / (9 × S)) ^ (-1)
```
onde `t` = dias desde a última revisão, `S` = estabilidade em dias. Por definição, `R(t=S, S) = 0,9`, o que ancora S como "dias até a recuperabilidade cair a 90%", exatamente como descrito na Metodologia, seção 3.1.

*Verificação numérica:* com S=10 dias, R(10,10)=0,900; R(20,10)=0,818; R(30,10)=0,750. A curva decai de forma suave e previsível, não abrupta.

**Intervalo até a próxima revisão**, dado S atual e a meta de retenção `r_meta` (0,80–0,95) configurada pelo usuário (seção 3.3):

```
I(S, r_meta) = 9 × S × (1 / r_meta − 1)
```
*Verificação numérica:* com S=10 e r_meta=0,90, I=10,0 dias. Com r_meta=0,85, I=15,9 dias, meta mais permissiva produz intervalo maior, como esperado.

**Atualização de estabilidade após acerto** (estrutura do modelo; pesos `w1…w3` são parâmetros **(a calibrar)** a partir de dados reais de revisão, não coeficientes fixos deste documento):
```
S_novo = S_antigo × (1 + e^(w1) × (11 − D) × S_antigo^(−w2) × (e^(w3 × (1−R)) − 1))
```

**Atualização de estabilidade após erro** (mesma ressalva de calibração, pesos `w4…w7`):
```
S_novo = w4 × D^(−w5) × ((S_antigo + 1)^w6 − 1) × e^(w7 × (1−R))
```

**Schema por cartão:**
```
Card {
  card_id, deck_id, tipo (enum: recall_aberto | cloze | imagem | aplicacao),
  D: float [1,10], S: float (dias), reps: int, lapses: int,
  last_review: timestamp, next_review: date,
  state: enum(novo | aprendendo | revisao | reaprendizado),
  origin: enum(manual | ia_assistida)
}
```

**Caso de teste técnico:**
```
Dado D=5,0, S=10,0 dias, T=8 dias desde a última revisão
Quando R é calculado
Então R deve ser 0,918 (± 0,001)
```

---

## RF-02 — Sessão de Estudo e Fila de Revisão

### Nível 1 — Capacidade

O sistema deve compor cada sessão de estudo intercalando disciplinas (seção 2.8), priorizando cartões em padrão de ilusão de domínio (seção 7.1) e limitando a introdução de cartões novos conforme a carga futura já prevista (seção 7.2), sem exigir que o usuário gerencie isso manualmente.

### Nível 2 — Comportamento

**Cenário: intercalação entre disciplinas**
```
Dado uma fila com cartões vencidos de três disciplinas diferentes
Quando a sessão é montada
Então cartões da mesma disciplina não aparecem em mais de K posições consecutivas (K configurável, padrão 2)
```

**Cenário: priorização por ilusão de domínio**
```
Dado dois cartões igualmente vencidos, um com histórico recente de alta confiança seguida de erro e outro sem esse padrão
Quando a fila é ordenada
Então o cartão com padrão de ilusão de domínio aparece antes do outro
```

**Cenário: throttling de cartões novos**
```
Dado que a carga de revisão prevista para os próximos 7 dias está acima do limiar de capacidade configurado
Quando o sistema decide quantos cartões novos introduzir hoje
Então o número de cartões novos introduzidos é reduzido proporcionalmente ao excesso de carga
```

### Nível 3 — Especificação técnica

**Intercalação:** embaralhamento com restrição de janela deslizante; ao montar a fila, nenhuma tag/disciplina pode repetir mais que `K` vezes seguidas, reamostrando quando essa condição é violada.

**Prioridade por calibração:**
```
priority_score = urgencia_base × (1 + β × illusion_flag)
```
onde `illusion_flag = 1` se as últimas N respostas desse cartão incluem confiança ≥ 70 combinada com erro; `β` **(a calibrar)**, ponto de partida sugerido 0,25.

**Throttling de cartões novos:**
```
novos_hoje = novos_base × clamp(1 − (carga_prevista_7d / capacidade_limiar), 0.2, 1.0)
```
o piso de 0,2 evita que a introdução de cartões novos pare por completo mesmo em picos de carga.

---

## RF-03 — Autoavaliação e Registro de Confiança

### Nível 1 — Capacidade

Antes de revelar a resposta correta, o sistema deve capturar a confiança declarada do usuário; depois, deve capturar a autoavaliação de acerto. Esse par de dados alimenta tanto o motor DSR (RF-01) quanto a matriz de calibração metacognitiva (RF-08), conforme seções 2.3 e 2.7.

### Nível 2 — Comportamento

**Cenário: sequência obrigatória de confiança antes de resposta**
```
Dado um cartão apresentado ao usuário
Quando o usuário formula ou digita sua resposta
Então o sistema solicita uma estimativa de confiança antes de revelar a resposta de referência
E a resposta de referência permanece oculta até a confiança ser declarada
```

**Cenário: persistência do par confiança-acerto**
```
Dado uma confiança declarada e uma autoavaliação de acerto para uma revisão
Quando a revisão é registrada
Então o par (confiança, acerto) é persistido associado ao evento, com timestamp e latência de resposta
```

### Nível 3 — Especificação técnica

**Schema do evento de revisão:**
```
ReviewEvent {
  review_id, card_id, user_id, timestamp,
  confidence: int [0,100], rating: enum(errou|dificil|bom|facil),
  response_latency_ms: int, session_type: enum(normal|cram)
}
```

**Classificador de quadrante** (usado por RF-08 e RF-02):
```
Dado confidence=85 e rating=errou
Quando o evento é classificado
Então o evento recebe a etiqueta "ilusão de domínio" (regra: confidence ≥ 70 AND rating = errou)
```

---

## RF-04 — Controle do Usuário sobre o Agendamento

### Nível 1 — Capacidade

Conforme os limites definidos na seção 3.3 da Metodologia, o sistema deve permitir três ajustes específicos (adiar até 3 dias, marcar como já dominado, marcar cartão como mal formulado) e a configuração da meta de retenção entre 80% e 95%, e deve **impedir**, inclusive fora da interface, qualquer definição manual de intervalo específico ou zeramento de estabilidade sem uma revisão real.

### Nível 2 — Comportamento

**Cenário: adiamento dentro do limite**
```
Dado um cartão vencido hoje
Quando o usuário solicita adiar em 2 dias
Então a data de vencimento é movida em 2 dias
E D e S permanecem inalterados
```

**Cenário: tentativa de adiamento acima do limite**
```
Dado um cartão vencido hoje
Quando o usuário solicita adiar em 5 dias
Então o sistema limita o adiamento a 3 dias
E informa o motivo do limite ao usuário
```

**Cenário: tentativa de definir intervalo manual (bloqueio obrigatório)**
```
Dado um cartão qualquer
Quando qualquer camada do sistema, interface ou chamada direta de API, tenta gravar um intervalo de dias definido manualmente para aquele cartão
Então a operação é rejeitada na camada de dados
E o motivo da rejeição é registrado em log de auditoria
```

**Cenário: ajuste de meta de retenção**
```
Dado uma meta de retenção atual de 85%
Quando o usuário ajusta a meta para 92%
Então os intervalos futuros calculados por RF-01 passam a usar r_meta=0,92
E nenhum cartão já agendado tem sua próxima data recalculada retroativamente
```

### Nível 3 — Especificação técnica

**Validação centralizada:** toda operação de agendamento deve passar por uma função única, `validate_schedule_override()`, executada no backend, não apenas na interface, que rejeita: intervalo manual explícito, zeramento de S sem `ReviewEvent` associado, adiamento acima de 3 dias, meta de retenção fora de [0,80; 0,95].

**Log de auditoria:**
```
ScheduleOverride { user_id, card_id, tipo, valor_solicitado, valor_aplicado, aceito: bool, timestamp }
```

---

## RF-05 — Modo Cram

### Nível 1 — Capacidade

Conforme a seção 3.4, o sistema deve oferecer um modo de estudo intensivo ativado explicitamente pelo usuário, operando em fila separada da fila espaçada normal, atualizando a estabilidade dos cartões revisados com peso reduzido, e reagendando esses cartões para reconsolidação assim que a janela de cram se encerra.

### Nível 2 — Comportamento

**Cenário: ativação explícita**
```
Dado que o usuário informa a data de uma prova próxima
Quando o modo cram é ativado
Então o sistema exibe um aviso sobre a natureza de curto prazo do modo
E cria uma fila de estudo separada da fila espaçada normal
```

**Cenário: a fila normal não é afetada**
```
Dado o modo cram ativo
Quando o usuário revisa cartões dentro do modo cram
Então nenhuma revisão agendada na fila espaçada normal é adiantada, adiada ou cancelada por causa disso
```

**Cenário: peso reduzido na atualização de estabilidade**
```
Dado um cartão revisado dentro do modo cram
Quando a estabilidade é recalculada
Então o ganho de estabilidade aplicado é menor que o de uma revisão equivalente fora do modo cram
```

**Cenário: reconsolidação pós-prova**
```
Dado o fim da janela de cram configurada
Quando o sistema processa o encerramento do modo
Então todo cartão revisado em modo cram é reagendado na fila espaçada normal
E o intervalo dessa reagendagem é menor que o indicado pela estabilidade nominal calculada
```

### Nível 3 — Especificação técnica

**Fator de peso cram**, aplicado ao termo de ganho da fórmula de acerto de RF-01:
```
S_novo(cram) = S_antigo × (1 + γ_cram × [termo de ganho normal de RF-01])
```
`γ_cram ∈ (0,1)` **(a calibrar)**, ponto de partida sugerido 0,3, refletindo ganho real porém reduzido, coerente com a seção 2.2 e 2.4 da Metodologia.

**Intervalo de reconsolidação**, com teto independente da estabilidade nominal:
```
I_reconsolidacao = min(I(S_novo, r_meta), I_max_reconsolidacao)
```
`I_max_reconsolidacao` **(a calibrar)**, ponto de partida sugerido 3 dias.

---

## RF-06 — Geração Assistida de Cartões por IA

### Nível 1 — Capacidade

Conforme a seção 3.2 (revisada) da Metodologia, o único ponto de entrada de inteligência artificial no sistema é a sugestão de cartões candidatos a partir de um prompt de assunto. Nenhum cartão gerado entra automaticamente no repertório, e o subsistema de geração deve ser tecnicamente isolado do motor de memória (RF-01).

### Nível 2 — Comportamento

**Cenário: geração de rascunhos**
```
Dado que o usuário fornece um prompt de assunto
Quando o sistema processa a solicitação de geração
Então retorna uma lista de cartões candidatos seguindo as regras da seção 4 da Metodologia (informação mínima, cloze quando aplicável)
E nenhum desses cartões é adicionado ao repertório automaticamente
```

**Cenário: aceite com ou sem edição**
```
Dado uma lista de cartões candidatos exibida ao usuário
Quando o usuário aceita um cartão específico, com ou sem edição do texto
Então esse cartão é criado com o mesmo schema e estado inicial de um cartão escrito manualmente
```

**Cenário: descarte**
```
Dado uma lista de cartões candidatos
Quando o usuário descarta um ou mais cartões
Então esses cartões não são persistidos em nenhuma tabela do sistema
```

### Nível 3 — Especificação técnica

**Requisito de arquitetura (obrigatório, verificável por análise estática de dependências):** o módulo de geração de cartões não pode importar, referenciar ou depender de nenhum código do motor DSR (RF-01). A checagem de ausência de import cruzado deve fazer parte do pipeline de build.

**Regra de não-diferenciação:** o campo `origin` no schema de `Card` (RF-01) pode existir para fins de analytics agregados, mas nenhuma função de cálculo de D, S, R ou de priorização de fila (RF-02) pode conter lógica condicional sobre esse campo. Verificável por revisão de código ou teste de mutação direcionado a esse campo.

---

## RF-07 — Editor e Tipos de Cartão

### Nível 1 — Capacidade

O sistema deve suportar os quatro tipos de cartão descritos na seção 4.3 da Metodologia (recall aberto, cloze deletion, imagem, aplicação/problema) e orientar, sem bloquear, a aderência ao princípio da informação mínima descrito na seção 4.1.

### Nível 2 — Comportamento

**Cenário: criação de cartão cloze**
```
Dado que o usuário seleciona o tipo "cloze deletion"
Quando ele marca um trecho de um texto como lacuna
Então o sistema gera a pergunta ocultando apenas o trecho marcado, preservando o restante como contexto visível
```

**Cenário: aviso de possível violação do princípio de informação mínima**
```
Dado um cartão sendo criado com uma resposta contendo múltiplos itens separados por conectivos
Quando o usuário tenta salvar
Então o sistema exibe um aviso sugerindo decompor o cartão em múltiplos cartões
E permite salvar mesmo assim
```

### Nível 3 — Especificação técnica

**Schema por tipo (extensões do schema base `Card` de RF-01):**
```
CardCloze { texto_base, posicoes_lacuna: [int] }
CardImagem { url_imagem, regioes_marcadas: [{x,y,largura,altura,resposta}] }
CardAplicacao { enunciado, resposta_esperada, permite_variantes: bool }
```

**Heurística de aviso de informação mínima:** contar itens separados por conectivos (`e`, `ou`, `;`, quebras de linha) no campo de resposta; disparar aviso não bloqueante quando a contagem exceder um limiar configurável (padrão 2).

---

## RF-08 — Painel de Métricas

### Nível 1 — Capacidade

O sistema deve calcular e exibir os oito indicadores definidos na seção 6.2 da Metodologia, todos recomputáveis de forma determinística a partir do log bruto de `ReviewEvent` (RF-03), sem estado intermediário que não possa ser reconstruído.

### Nível 2 — Comportamento

**Cenário: recomputação determinística (aplica-se a todas as 8 métricas)**
```
Dado um mesmo log bruto de eventos de revisão
Quando qualquer métrica deste painel é recalculada em momentos diferentes
Então o resultado é idêntico, sem dependência de estado externo ou de qualquer componente não determinístico
```

**Cenário: atualização do heatmap de consistência**
```
Dado uma sessão de estudo concluída em um dia específico
Quando o heatmap de consistência é renderizado
Então a célula correspondente àquele dia reflete o volume de revisões concluídas naquele dia
```

### Nível 3 — Especificação técnica (fórmula por indicador)

| # | Indicador | Fórmula / regra |
|---|---|---|
| 1 | Retenção realizada | `revisões_corretas / total_revisões × 100`, janela móvel de 30 dias |
| 2 | Retenção real vs. meta | Série semanal do indicador 1, plotada contra a constante `r_meta` |
| 3 | Calibração metacognitiva | Índice de sobreconfiança = `revisões_erradas_confiança≥70 / total_revisões_erradas × 100`; associação medida por correlação gama (confidence binarizada em 50, rating binarizado em acerto/erro) |
| 4 | Consistência de revisão | Matriz `dia_da_semana × semana`, célula = contagem de revisões |
| 5 | Maturidade do repertório | Contagem de cartões por bucket de S: novo (reps=0), aprendendo (S<1 dia), jovem (1≤S<21 dias), maduro (S≥21 dias) |
| 6 | Carga de revisão prevista | Para cada um dos próximos 30 dias, contagem de cartões com `next_review` naquela data |
| 7 | Desempenho por disciplina | Indicador 1 segmentado por tag/disciplina do cartão |
| 8 | Distribuição de dificuldade | Histograma de `D` em 10 bins (1 a 10) |

---

## RF-09 — Índice de Prontidão

### Nível 1 — Capacidade

Conforme a seção 7.4, o sistema deve oferecer, como camada opcional de simplificação sobre o painel completo (RF-08), um único índice composto de 0 a 100.

### Nível 3 — Especificação técnica

```
Indice_Prontidao = w_a × retencao_normalizada
                  + w_b × (100 − indice_sobreconfianca)
                  + w_c × consistencia_normalizada
```
com `w_a + w_b + w_c = 1`; ponto de partida sugerido: pesos iguais (1/3 cada), ajustáveis **(a calibrar)** conforme percepção de utilidade dos primeiros usuários do MVP.

---

## Requisitos não funcionais

| ID | Requisito | Justificativa |
|---|---|---|
| RNF-01 | Todo cálculo de RF-01, RF-02, RF-03, RF-04, RF-05 e RF-08 deve executar localmente no dispositivo ou no aplicativo, sem exigir chamada de rede para produzir um resultado | Seção 3.2 da Metodologia: motor de memória local e auditável |
| RNF-02 | O único subsistema com dependência de serviço externo (API de IA) é RF-06, e sua indisponibilidade não pode degradar nenhuma outra capacidade | Isolamento arquitetural exigido por RF-06 |
| RNF-03 | Todo evento de `ReviewEvent` deve ser gravado localmente antes de qualquer tentativa de sincronização, para que o motor DSR nunca dependa de conectividade | Consistência com o terminal físico como dispositivo primário |
| RNF-04 | Toda métrica de RF-08 deve ser recomputável a partir do log bruto, sem uso de valores cacheados como fonte de verdade | Critério de aceite já definido na Metodologia, seção 8 |

---

## Próximos passos de engenharia

1. Implementar RF-01 isoladamente com testes unitários baseados nos casos numéricos deste documento antes de qualquer interface.
2. Validar RF-03 e RF-04 em conjunto, já que o registro de confiança e os limites de controle do usuário compartilham a mesma camada de persistência.
3. RF-06 pode ser desenvolvido em paralelo, dado o isolamento arquitetural exigido, sem bloquear o restante do sistema.
4. RF-08 depende apenas do schema de `ReviewEvent` (RF-03) estar estável; pode ser desenvolvido assim que esse contrato de dados for congelado.
