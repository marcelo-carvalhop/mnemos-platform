# Mnemos Web — brief de interface

Para construir o cliente web do Mnemos. Este documento e a pasta `prints/`
são autossuficientes: descrevem o que o produto é, o que cada tela do
aplicativo faz e por quê, e o que muda quando a mesma coisa acontece numa tela
grande.

As cores estão em [CORES.md](CORES.md), com os contrastes medidos e três
correções obrigatórias.

---

## 1. O produto em um parágrafo

Mnemos é uma plataforma de estudo por repetição espaçada com **três
superfícies**: um aplicativo móvel, um terminal físico de tinta eletrônica, e
— agora — a web. O usuário escreve ou gera cards, e o algoritmo FSRS decide
quando cada um volta. O terminal existe porque ler sem notificações é melhor
para estudar; o app e a web existem porque ninguém carrega o terminal o tempo
todo.

**O ponto que decide o desenho:** as três superfícies são intercambiáveis para
estudar. Nenhuma é um acessório da outra. O histórico de revisões é um log
append-only sincronizado entre elas, e o agendamento sai desse log — então
responder um card na web, no telefone ou no terminal produz exatamente o mesmo
efeito.

---

## 2. O que o usuário faz

Em ordem de frequência real, não de importância declarada:

1. **Revisa o que venceu hoje.** Todo dia, alguns minutos. É 90% do uso.
2. **Escreve cards.** Em rajadas, depois de uma aula ou leitura.
3. **Gera cards por IA** a partir de um tópico, uma foto do caderno ou um PDF.
   Cada geração passa por uma fila de aprovação, um card por vez.
4. **Olha o progresso.** Semanalmente, no máximo.
5. **Gerencia o terminal.** Raro: parear uma vez, depois escolher que baralhos
   ficam nele.

A web deve otimizar para 1 e 2. O item 5 pode existir de forma reduzida — quem
tem terminal vai configurá-lo pelo telefone, que é o que está na mão quando o
aparelho está na frente.

---

## 3. As telas do aplicativo

Cada uma abaixo tem o print correspondente em `prints/`. A descrição diz o que
a tela faz, que decisão de produto ela carrega, e o que muda na web.

### `01-hoje.png` — Hoje

A tela de abertura. Três blocos, nesta ordem:

- **Memória acumulada** ("7 dias de conhecimento guardado"). É a soma da
  estabilidade de todos os cards ativos — quanto tempo o conhecimento ainda
  dura na cabeça da pessoa. **É a manchete do produto e nunca é substituída
  por uma contagem de cards.** Um número que só cresce quando alguém lembra de
  algo é honesto; "você tem 400 cards" não é.
- **Meta do dia**, com anel de progresso: "2 / 25 cards".
- **Ação de estudar**: "Estudar agora · 2".

Tem três estados que precisam ser distintos:
1. Há cards vencendo → botão de estudar com a contagem.
2. Nada vencendo, mas existem cards → cartão verde, "Nada vencendo agora / Sua
   memória segue trabalhando sozinha". **É uma mensagem de conclusão, não uma
   tela vazia.**
3. Não existe card nenhum → "Seu primeiro card / Escreva uma pergunta que você
   quer lembrar daqui a um ano", com botão de criar. **Nunca mostre o estado 2
   para quem está no 3** — dizer que a memória está trabalhando para quem não
   tem card é falso.

**Na web:** a manchete pode ser maior e o anel pode virar um gráfico de barras
das próximas duas semanas ao lado, aproveitando a largura. O botão de estudar
continua sendo o único elemento com peso visual de ação.

### `02-biblioteca.png` — Biblioteca

Lista de baralhos com contagem de cards. Botão flutuante "Novo baralho", busca
e configurações na barra superior. O menu de três pontos abre o gerenciamento
do baralho.

**Na web:** lista em duas ou três colunas, com busca sempre visível (não atrás
de um ícone). Uma biblioteca com trinta baralhos numa tela de 1440px não tem
motivo para ser uma coluna.

### `03-dispositivo.png` — Dispositivo

Identidade e estado do terminal pareado: modelo, ID, firmware, protocolo,
capacidade. Quando não há nenhum, oferece parear.

**Na web:** pode ser somente leitura — mostrar o terminal e seu estado, com
"para parear, use o aplicativo". Parear exige BLE, que o navegador só tem em
Chrome e sob HTTPS. Não vale desenhar um fluxo que metade dos usuários não
consegue completar.

### `04-progresso.png` — Progresso

Cinco blocos: memória acumulada, retenção em 90 dias, dias seguidos, previsão
de 14 dias, mapa de calor de 12 semanas, maturidade por baralho.

Duas regras de honestidade que valem para a web:
- **Retenção sem dados é "—", não "0%".** Zero por cento diz a quem nunca
  respondeu um card que ele erra tudo.
- **"Maduro"** é um card com intervalo acima de 21 dias. Nunca escreva
  "concluído": nada é concluído em repetição espaçada.

**Na web:** é a tela que mais ganha com espaço. O mapa de calor pode ser um ano
inteiro em vez de doze semanas, e a previsão pode ter eixo e rótulos.

### `05-card-frente.png` e `06-card-verso-graus.png` — Revisão

O núcleo. Frente do card centralizada, toque revela o verso, e aparecem quatro
botões de grau: **Errei, Difícil, Bom, Fácil**.

**Cada botão mostra o intervalo que vai produzir** — "1 min", "5 min",
"10 min", "2 semanas". Esse número vem do agendador, não é decorativo, e é o
que separa um app sério de um brinquedo: o usuário vê a consequência antes de
escolher.

A ordem dos quatro é sempre a mesma e as cores são fixas: terracota, latão,
sálvia, petróleo.

**Na web:** os quatro botões devem ter atalhos de teclado (1–4), e espaço
deve revelar o verso. Quem estuda no computador estuda com as mãos no teclado.
Este é o maior ganho da web sobre o telefone e vale desenhar em volta dele.

### `07-sessao-concluida.png` — Fim de sessão

"Um pouco mais alto / 7 dias de memória guardada". **Lidera pela memória, não
pela contagem de cards respondidos.**

### `08-outros-modos.png` — Modos alternativos

Quatro modos: múltipla escolha, "só os que erro muito", simulado cronometrado,
áudio.

O selo em cada linha é obrigatório e carrega significado: **verde "Conta para o
agendamento"** contra **âmbar "Treino extra"**. Só a múltipla escolha alimenta
o algoritmo; os outros três não alteram nada. Sem esse selo, alguém treina
achando que adiantou trabalho e distorce o próprio cronograma.

Os modos âmbar **não têm botões de grau** — não há o que registrar.

**Na web:** múltipla escolha e simulado funcionam bem; áudio provavelmente não
vale a pena (é para deslocamento). O modo digitação, que não existe em lugar
nenhum ainda, seria a adição natural para teclado.

### `09-gerenciar-baralho.png` — Gerenciar baralho

Duas seções: adicionar cards (escrever, gerar por tópico, foto/PDF) e o baralho
(renomear, arquivar, apagar).

**A distinção entre arquivar e apagar é o motivo desta tela existir.** Arquivar
some da lista e para de agendar, e volta inteiro. Apagar leva os cards e o
histórico junto. "Terminei esse curso" é o que quase todo mundo quer dizer
quando procura o botão de apagar — e o texto sob cada opção diz isso.

### `10-editor-card.png` — Escrever um card

Frente e verso com contador de caracteres (120 e 240), e uma prévia
**"Como fica no aparelho"** em serifada, imitando o terminal de tinta
eletrônica.

O limite é rígido: acima dele o contador fica vermelho, aparece "N caracteres
acima do limite. O card precisa caber na tela do aparelho", e salvar é
desabilitado. Caracteres são contados como o usuário os vê — um emoji de
família conta 1, não 7.

**Na web:** a prévia fica ao lado dos campos em vez de abaixo, e atualiza
enquanto se digita. "Salvar e criar outro" continua sendo a ação primária, com
atalho de teclado.

### `11-configuracoes.png` — Configurações

Estudo (cards novos por dia, revisões por dia, meta de retenção), o dia
(hora de virada, fuso), lembrete, conta (sincronização, gerações por IA, seus
dados) e sobre.

Dois textos que precisam sobreviver na web:
- A meta de retenção diz "Mais alto significa intervalos mais curtos e mais
  revisões por dia". É um botão que muda quanto trabalho a pessoa terá.
- A hora de virada diz "Estudar de madrugada conta para o dia anterior. Mudar
  isto não reescreve o passado — vale a partir de hoje".

### `12-gerar-por-topico.png` — Gerar por tópico

Campo de tópico, baralho de destino, nível, quantidade. No topo, **a cota
disponível** — porque o plano grátis é uma geração para toda a vida da conta, e
gastá-la sem avisar é tirar algo que a pessoa não sabia que tinha.

Depois vem uma tela de progresso que **nomeia o estágio** ("lendo o material",
"escrevendo os cards") em vez de uma barra que não sabe onde está, e diz que dá
para sair — leva de 10 a 30 segundos.

Termina numa **fila de aprovação**: cada card com Descartar / Aprovar, contador
"7 de 24", desfazer obrigatório, e "Aprovar restantes". **Nada vira card sem
alguém dizer sim.**

### `13-capturar-material.png` — Foto ou PDF

Três origens: tirar foto, galeria, PDF. O arquivo vai direto para o
armazenamento e é apagado depois que os cards são criados — a tela promete isso
e o servidor cumpre.

**Na web:** arrastar e soltar, e colar do clipboard. Câmera não faz sentido.

---

## 4. O que a web deve fazer diferente

Não é o app numa tela maior. Três coisas mudam de verdade:

**Teclado.** Espaço revela, 1–4 respondem, e navegar entre cards não exige
mouse. Numa sessão de 50 cards isso é a diferença entre alguns minutos e uma
tarefa.

**Duas colunas onde o telefone tem uma.** Biblioteca, fila de aprovação e
editor com prévia ao lado ganham diretamente. A revisão **não** ganha: o card
deve continuar sozinho e centralizado, com largura máxima de leitura
(~65 caracteres). Um card esticado em 1440px é ilegível.

**Escrever em série.** O caso de uso "acabei a aula, vou lançar quinze cards"
é de teclado. O editor deve permitir criar um atrás do outro sem tocar o mouse.

---

## 5. O que a web não deve fazer

- **Não inventar métricas.** Todo número vem do log de revisões. Não existe
  "pontuação", "XP" nem "nível" — foram removidos deliberadamente do desenho
  original porque medem uso, não memória.
- **Não colocar estatística na Home.** Números vivem em Hoje e em Progresso.
- **Não tratar offline como erro.** O app funciona sem internet e a web deve,
  no mínimo, não dramatizar a perda de conexão.
- **Não usar cor sozinha** para os quatro graus nem para o selo
  "conta/treino extra". Ambos vêm com rótulo em texto.

---

## 6. Telas que a web precisa e o app não tem

- **Login por e-mail e senha.** No app a conta começa anônima, presa ao
  aparelho. Na web isso não funciona: a primeira tela é entrar.
- **Uma landing** para quem chega sem conta.
- **Importar/exportar** com mais espaço: o app tem só um botão de exportar
  JSON.

---

## 7. Restrições técnicas que afetam o desenho

- **Cards são exclusivamente texto.** Sem imagem, sem áudio embutido, sem
  formatação rica. O limite de 120/240 caracteres existe por causa da tela do
  terminal.
- **Português do Brasil.** Toda a interface. Acentuação importa: a busca é
  insensível a acento de propósito, porque quem digita rápido não acentua.
- **Um card testa uma ideia só.** Isso vem do prompt de geração e deve
  aparecer no desenho: cards são curtos, e um layout que acomoda parágrafos
  está desenhando para o card errado.
