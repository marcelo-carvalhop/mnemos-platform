# Mnemos Web

Cliente web oficial do Mnemos: Angular 22, TypeScript, sem framework de
servidor. Consome a API pública do backend — nunca o banco interno do
aplicativo.

## Rodando

```bash
cd app/web
npm ci
npm start          # http://localhost:4200, com proxy para localhost:8000
```

O backend precisa estar de pé (`docker compose up -d`). O `proxy.conf.json`
encaminha `/api` para ele, o que mantém tudo na mesma origem e tira CORS do
caminho no desenvolvimento.

```bash
npm test           # Vitest, em modo watch
npm run test:ci    # uma passada só
npm run build      # produção, com os budgets do angular.json
npm run format     # Prettier
```

**Node 22.22.3 ou superior** (veja `.nvmrc`). O Angular 22 recusa versões
anteriores com uma mensagem que não parece um erro de versão.

## O que esta interface é

A web é uma superfície de estudo completa, não um painel administrativo. Uma
versão anterior deste arquivo dizia o contrário — *"must not become a second
study surface"* — e a regra foi revista de propósito: quem passa o dia diante de
um monitor não deveria ter de pegar o telefone para responder trinta cards, e
com teclado a resposta é mais rápida do que no aparelho. O que continua valendo
da regra original é o espírito: **nenhuma tela mistura painéis, medalhas ou
widgets de engajamento em assunto alheio**. Progresso mora em Progresso.

Três coisas a web faz melhor que o celular, e são a razão de ela existir:

1. **Estudar pelo teclado.** Espaço revela, 1–4 graduam. A mão não sai do
   lugar, e cada grau mostra o intervalo que produz antes de ser escolhido.
2. **Escrever em série.** No celular cada card é abrir uma tela, escrever,
   salvar e voltar. Aqui a lista fica à esquerda e o editor à direita: salvar
   não fecha nada e o campo volta vazio.
3. **Ver de longe.** Trinta dias de revisões num gráfico só, que num telefone
   seria uma rolagem.

## Como os dados chegam aqui

O servidor **não** expõe REST de baralhos e cards: a API pública de conteúdo é
o protocolo de sync (§6). A web fala o mesmo protocolo que o aplicativo —
mesma ordem de envio, mesma regra de último-a-escrever — e é isso que faz as
duas superfícies concordarem sobre conflito.

A diferença é deliberada: no telefone o SQLite local é a verdade e o servidor é
backup. Aqui não há banco local, e o `Store` é um espelho em memória. Recarregar
a página puxa tudo de novo. Ficar offline continua não sendo erro (§5.14) — o
que muda é que a web, sem persistência, não sobrevive a um fechamento de aba com
mudanças pendentes, e por isso ela sincroniza ao sair.

## FSRS: o acordo entre as duas implementações

§3 diz que o log de revisões é a verdade e `card_state` é um cache reconstruído
**identicamente em qualquer lugar**. O aplicativo usa o pacote `fsrs` do pub e a
web usa `ts-fsrs` do npm: duas implementações independentes do mesmo algoritmo.

Os padrões dos dois pacotes **não** coincidem — o npm traz o vetor do FSRS-6, o
pub traz outro. Herdar o padrão de cada um fazia o navegador e o telefone
calcularem vencimentos diferentes do mesmo histórico, sem nada avisar. Por isso
o vetor está em `shared/contract.yaml` e os dois lados o consomem de lá.

O acordo é testado nas duas pontas:

- `src/app/core/scheduler.spec.ts` reproduz históricos gerados pelo Dart
  (`app/mobile/packages/scheduler/tool/dump_fixtures.dart`). **A data de
  vencimento é comparada exata**; estabilidade e dificuldade toleram erro
  relativo, porque `ts-fsrs` arredonda para oito casas e o pacote do Dart não.
- `app/mobile/packages/scheduler/test/scheduler_test.dart` compara o padrão do
  pacote do pub com o vetor do contrato.

Quando um desses falhar, a pergunta não é qual valor ajustar — é qual das duas
implementações mudou e por quê. Para regerar os fixtures:

```bash
cd app/mobile/packages/scheduler
dart run tool/dump_fixtures.dart > ../../../web/src/app/core/fsrs-fixtures.json
```

## Estrutura

```
src/app/
  core/         contrato gerado, HTTP, sessão, sync, store, escalonador, copy de erro
  shell/        a moldura: navegação à esquerda, tela à direita
  features/     uma pasta por tela, carregada sob demanda
  shared/       o que mais de uma tela usa
```

`core/contract.g.ts` é **gerado** a partir de `shared/contract.yaml` por
`python shared/generate.py`, junto com os equivalentes em Dart e Python. O CI
regenera e compara: um arquivo gerado desatualizado quebra o build em vez de
discordar em silêncio.

## Cores e tipografia

Os tokens estão em `src/styles.css` e vêm de `docs/design/web-brief/CORES.md`,
onde cada cor traz o contraste medido. Três cores da paleta reprovam WCAG AA
como texto pequeno sobre marfim; a web usa as variantes escurecidas
(`#535F4E`, `#806B44`, `#9E5D44`) para texto e reserva as originais para
superfícies grandes.

Duas distinções carregam significado e nunca são só cor — vêm sempre com
rótulo em texto:

- **Os quatro graus** têm ordem: errei → difícil → bom → fácil. Terracota,
  latão, sálvia, petróleo, sempre nessa sequência.
- **"Conta para o agendamento" contra "treino extra".** Sálvia para o que entra
  no cronograma, latão para o que não entra.
