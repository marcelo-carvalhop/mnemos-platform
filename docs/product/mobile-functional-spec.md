# Especificação funcional — App de flashcards

Documento de referência para desenho de interface. Descreve telas, fluxos, estados e regras de negócio. Não trata de arquitetura de backend nem do dispositivo.

---

## 1. Contexto

App móvel que acompanha um e-reader dedicado a estudo sem distração. **Nesta fase o app é desenhado como se o dispositivo não existisse** — pareamento e sincronização entram numa versão posterior. As decisões abaixo, no entanto, já respeitam as restrições do aparelho para evitar retrabalho.

**Restrições que vêm do hardware, mesmo sem ele:**

- Cards são **exclusivamente texto**. Não existe imagem, áudio embutido nem formatação rica.
- Card precisa caber numa tela pequena de e-ink. O editor impõe limite de caracteres.
- Agendamento é calculado no app; o aparelho só consumiria uma fila pronta.

**Backend próprio** existe desde a v1: contas, backup do histórico, geração por IA e cota.

---

## 2. Princípios de design

1. **Card nasce curto.** O limite de caracteres é regra, não sugestão. Ele existe por causa da tela, mas coincide com a boa prática pedagógica.
2. **Nada gerado por IA entra no baralho sem aprovação humana.** Sempre passa pela fila de aprovação.
3. **Gamificação premia resultado, nunca volume.** Nenhuma métrica visível pode ser inflada por esforço bruto.
4. **O app não persegue o usuário.** Notificação só para fila vencida, desligável. Sem push de engajamento.

---

## 3. Modelo conceitual

O designer precisa entender três objetos:

**Baralho** — id estável, versão, nome, descrição, baralho pai (permite aninhamento), autoria, licença, origem (própria ou externa). Os quatro últimos campos existem desde já para viabilizar baralhos compartilhados no futuro, mesmo sem interface para eles agora.

**Card** — id, frente, verso, tags, baralho, estado (`ativo`, `suspenso`, `enterrado`).

**Revisão** — card, momento, grau atribuído, origem. É um **registro imutável de evento**: nunca é editado nem apagado. Todo o agendamento e toda a estatística derivam desse histórico.

Consequência prática para a interface: **editar um card não altera seu agendamento**. Corrigir uma vírgula não pode jogar fora meses de histórico. Se o usuário quiser recomeçar aquele card do zero, isso é uma ação explícita e separada ("reiniciar progresso"), com confirmação.

---

## 4. Estados de um card

| Estado | Significado | Aparece na sessão? |
|---|---|---|
| Novo | Nunca revisado | Sim, respeitando limite diário de novos |
| Em aprendizado | Poucas revisões, intervalos curtos | Sim |
| Em revisão | Intervalo consolidado | Sim, quando vence |
| Maduro | Intervalo acima de 21 dias | Sim, quando vence |
| Suspenso | Retirado temporariamente pelo usuário | Não |
| Enterrado | Escondido até o dia seguinte | Não, hoje |

"Maduro" não é um estado separado no banco — é um recorte de "em revisão" usado nas estatísticas. Mas o usuário precisa vê-lo como categoria, porque é a barra de progresso natural de um baralho.

---

## 5. Fluxos

### 5.1 Onboarding

Primeira abertura, quatro telas no máximo.

1. **Boas-vindas** — uma frase sobre o que o app faz. Botão único.
2. **O que você quer estudar?** — campo de texto livre com sugestões tocáveis. Essa resposta vira o primeiro baralho e alimenta a primeira geração.
3. **Meta diária** — seletor simples com três opções pré-definidas (leve / médio / intenso, traduzidas em número de cards) e opção de personalizar. Editável depois.
4. **Conta** — criar conta ou entrar. Explicar em uma linha que serve para não perder o histórico.

Ao final, o app **já gera o primeiro baralho** a partir da resposta da tela 2 e leva direto para a fila de aprovação. O usuário sai do onboarding com material pronto, não com uma tela vazia.

**Estado vazio, se pular a geração:** home com um único botão grande de criar baralho.

---

### 5.2 Home

Elemento central: **o que precisa ser estudado hoje**.

- Anel ou barra de progresso da meta diária, com número de cards vencidos.
- Botão primário: **Estudar agora**. Se não há nada vencido, ele muda de texto e oferece estudar adiantado ou revisar os difíceis.
- Lista de baralhos, cada um com nome, quantos cards vencem hoje e proporção de maduros.
- Acesso a criar conteúdo (botão flutuante), progresso e ajustes.

**Estado zerado do dia:** mensagem de conclusão com a métrica de memória acumulada em destaque, não um vazio triste.

---

### 5.3 Criar baralho

Nome, descrição opcional, baralho pai opcional. Depois de criado, o app oferece imediatamente as portas de entrada de conteúdo — criar baralho vazio e sair é um beco.

---

### 5.4 Criar card manual

Dois campos: **frente** e **verso**.

- Contador de caracteres visível em ambos, com o limite explícito.
- Ao ultrapassar, o campo sinaliza e o botão de salvar desabilita. É restrição dura.
- Seletor de tags.
- **Preview no formato da tela do aparelho** — retângulo com a proporção e o tamanho de fonte reais, mostrando como o card ficaria. Presente mesmo antes do dispositivo existir: é o que ensina o usuário a escrever card curto.
- Salvar e criar outro é a ação padrão; salvar e sair é secundária.

---

### 5.5 Gerar por tópico

1. Campo de texto: o tópico, em linguagem natural.
2. Opções: baralho de destino, quantidade aproximada de cards, nível (introdutório / intermediário / avançado).
3. Botão gerar. Estado de carregamento com indicação de progresso real, não spinner mudo — a geração leva alguns segundos.
4. Resultado cai direto na **fila de aprovação** (5.7).

**Erros a desenhar:** falha de rede, cota esgotada, tópico vago demais para gerar (o sistema pede especificação em vez de gerar lixo).

---

### 5.6 Capturar material

Três portas de entrada que convergem no mesmo lugar:

- **Colar texto** — caixa grande, aceita colagem longa.
- **Enviar PDF** — seletor de arquivo, com opção de escolher intervalo de páginas.
- **Tirar foto** — câmera para página de livro, caderno manuscrito ou quadro de aula. Permite múltiplas fotos numa mesma captura.

Depois da captura, uma tela intermediária mostra o conteúdo detectado e deixa o usuário escolher baralho de destino e quantidade aproximada de cards. Daí segue para a fila de aprovação.

**Erros a desenhar:** foto ilegível, PDF sem texto extraível, arquivo grande demais, material insuficiente.

---

### 5.7 Fila de aprovação (formato swipe)

É a tela mais importante do app. Todo card gerado por IA passa por aqui.

**Interação:**

- Arrastar para a **direita**: aprova, entra no baralho.
- Arrastar para a **esquerda**: descarta.
- **Toque**: abre edição inline (frente, verso, tags), com os mesmos limites de caracteres do editor manual. Ao confirmar, volta para a fila com o card já corrigido.
- **Desfazer** sempre disponível, no mínimo um passo atrás. Obrigatório — o gesto erra.

**Elementos:**

- Contador de posição ("7 de 24") para dar noção de fim.
- Botão secundário **aprovar todos os restantes**, para quem confia na geração e não quer 24 gestos.
- O card na fila é exibido no formato de preview do aparelho, não como texto solto.

**Encerramento:** resumo do que entrou e do que foi descartado, com atalho para começar a estudar aquele baralho.

**Retomada:** se o usuário abandonar no meio, a fila fica pendente e a home mostra o aviso. Não descartar silenciosamente.

---

### 5.8 Sessão de estudo

Fluxo padrão, movido pelo FSRS.

1. Card aparece mostrando só a **frente**.
2. Usuário pensa e toca para revelar o **verso**.
3. Escolhe entre **quatro graus**: errei / difícil / bom / fácil. Cada botão exibe o intervalo resultante ("3 dias", "2 semanas") — isso dá transparência ao algoritmo e é o que separa um app sério de um brinquedo.
4. Próximo card.

**Regras:**

- Limite diário de cards novos, separado do limite de revisões, para não explodir a carga futura.
- Sem cronômetro visível na sessão padrão. Pressa atrapalha recuperação.
- Barra de progresso discreta da sessão.
- Ações rápidas acessíveis durante a sessão: editar card, suspender, enterrar.
- Sair no meio preserva o que já foi revisado — cada resposta é gravada na hora, não no fim.

**Fim da sessão:** resumo com acertos, memória ganha e meta diária atualizada.

---

### 5.9 Modos alternativos de estudo

Todos partem da mesma base de cards.

**Múltipla escolha** — o app monta alternativas a partir de respostas de outros cards do mesmo baralho. Conta como revisão normal para o FSRS, com o grau inferido do acerto e do tempo.

**Só os que erro muito** — recorte dos cards com maior número de lapsos no histórico. Sessão avulsa. **Não altera o agendamento**: é treino extra, não revisão oficial. Isso precisa ficar claro na interface, senão o usuário distorce o próprio cronograma achando que está adiantando o trabalho.

**Simulado cronometrado** — seleção por baralho ou tag, número de questões e tempo total. Formato de prova: sem feedback durante, resultado só no fim. **Também não alimenta o FSRS** — é aferição, não estudo.

**Áudio (TTS)** — lê frente, faz pausa, lê verso. Voltado para deslocamento e academia. Sem botão de grau enquanto o usuário está de fone; a sessão é passiva e não gera revisão.

A distinção entre "o que conta para o agendamento" e "o que é treino extra" é conceitual e precisa aparecer no desenho, com rótulo ou cor consistente.

---

### 5.10 Gerenciar baralho

- Lista de cards com busca e filtro por tag e por estado.
- Seleção múltipla para mover, etiquetar, suspender ou apagar em lote.
- Editar card abre o mesmo editor de 5.4, com aviso de que a edição preserva o histórico.
- **Reiniciar progresso** de um card ou do baralho inteiro: ação destrutiva, com confirmação explícita.
- Renomear, mover para outro baralho pai, arquivar.

---

### 5.11 Progresso

Seção própria, construída sobre resultado e não sobre volume.

**Métrica principal — memória acumulada.** Soma da estabilidade de todos os cards, expressa em tempo ("3 anos e 2 meses de memória guardada"). É o número em destaque, e é o número compartilhável. Sobe com retenção real e cai quando o usuário erra, então não é inflável.

**Métricas de apoio:**

- **Precisão** — retenção real medida contra a meta de retenção configurada.
- **Cards maduros** — quantos passaram de 21 dias, por baralho.
- **Heatmap** de constância diária.
- **Nível por matéria**, derivado da maturidade média do baralho.
- **Previsão de carga** — quantos cards vencem por dia nas próximas semanas. Serve de aviso quando a pessoa está criando material rápido demais.
- **Cards com vazamento** — os que ela esquece sempre apesar de revisar.

**Elementos de engajamento:**

- **Streak de meta batida** (não de app aberto), com dois ou três perdões automáticos por mês.
- **Graduação** — celebração quando um card cruza 6 meses ou 1 ano de intervalo. Evento raro, então merece peso visual.
- **Retrospectiva mensal** no estilo de retrospectiva de fim de ano: matéria mais forte, card mais teimoso, memória ganha no período. Aparece dentro do app, sem push.
- **Card teimoso do mês** — o mais errado, com tom leve. Conteúdo naturalmente compartilhável.

---

### 5.12 Ajustes

- Meta diária.
- Meta de retenção (afeta diretamente o volume de revisões — explicar o trade-off em uma linha).
- Limite de cards novos por dia.
- Notificações: só fila vencida, com horário escolhido, desligável.
- Conta, assinatura, exportar dados, sair.

---

### 5.13 Cota e assinatura

- Indicador de cota de geração por IA visível na tela de geração, não escondido em ajustes.
- Ao esgotar: tela explicando o limite e oferecendo o plano pago, sem bloquear o resto do app. Criar card manual e estudar continuam livres.
- Assinatura inclusa por período na compra do aparelho, quando ele existir.

---

## 6. Decisões pendentes

Precisam de resposta, mas não travam o início do desenho. Onde há sugestão, ela está marcada como tal.

| Tema | Pergunta | Sugestão |
|---|---|---|
| Público-alvo | Estudo técnico, acadêmico e profissional? | Define linguagem, exemplos e baralhos iniciais |
| Conta | Login obrigatório no onboarding ou depois? | Depois da primeira geração, para não perder gente na entrada |
| Meta diária | Em cards, em minutos, ou os dois? | Cards — mais previsível e mais fácil de casar com o FSRS |
| Meta de retenção | Expor ao usuário ou fixar? | Fixar em 90% na v1, expor quando houver base para explicar |
| Limite de caracteres | Qual número exato para frente e verso? | Depende da tela final; escolher um provisório e desenhar com ele |
| Cota gratuita | Quantas gerações por mês no plano grátis? | Número precisa existir para desenhar a tela de limite |
| Estudo offline | Sessão funciona sem rede? | Sim — é requisito de metrô e ônibus, e muda o desenho de erro |
| Idioma | Só português na v1? | Sim |

---

## 7. Fora do MVP

Especificado para não virar reescrita depois.

**Dispositivo:** pareamento, envio de fila, status de bateria, atualização de firmware, painel de controle do aparelho, múltiplos aparelhos por conta.

**Conteúdo pronto e social:** baralhos oficiais por segmento, marketplace com cursinhos e professores com repasse de receita, compartilhamento por link ou QR, grupo de estudo com progresso visível, distribuição para turma com visão agregada para o professor, baralho colaborativo.

**Já contemplado no modelo de dados para viabilizar o acima:** id estável e versionado por baralho, separação entre conteúdo do baralho e histórico de revisão da pessoa, campos de autoria e licença, marcação de origem externa.

**Descartado por decisão:** importação de Anki e CSV, ditado por voz, extensão de navegador, highlights de Kindle, links de artigo e YouTube, detecção automática de card ruim, sugestão de quebra de card composto, reescrita de card por IA, cloze deletion, imagens em cards, modo digitação, modo conversa com IA.
