# Aplicação web

`app/web/` contém uma aplicação Angular 22 em TypeScript. As rotas em `src/app/app.routes.ts` oferecem entrada, Hoje, estudo, biblioteca e detalhe do baralho, criação/geração/aprovação, progresso, dispositivo e configurações. O estudo é uma superfície primária do produto; sua revisão escreve no mesmo domínio de eventos usado pelo móvel e pelo servidor.

A camada `src/app/core/` separa sessão/autenticação, transporte API, espelho de dados, sincronização, scheduler e geração. `Store` usa signals para as entidades e recompõe o estado de cartões pelo replay de revisões e resets. `Sync` envia a outbox na ordem definida pelo contrato e puxa deltas por tabela; o servidor atribui `server_seq` e devolve os IDs confirmados. A web não depende das tabelas Drift do móvel e não persiste a biblioteca inteira no navegador: o espelho é reconstruído após uma nova carga da página. Por isso não se deve prometer estudo offline durável na web.

A sessão utiliza armazenamento do navegador para dados mínimos de autenticação/instalação; essa persistência não é a persistência pedagógica. O browser não participa do SoftAP do terminal. A página de dispositivo gerencia estado de conta pela API, enquanto provisionamento físico e DirectSync dependem do aplicativo móvel. A integridade do conteúdo e das revisões no backend continua necessária para a convergência entre web e móvel.

Para desenvolvimento: `npm ci`, `npm start`, `npm run test:ci`, `npm run lint:format` e `npm run build` a partir de `app/web/`. Use a versão de Node declarada em `.nvmrc`. Consulte [a integração do T5 Touch](../integration/t5-touch.md) antes de declarar que uma revisão originada no terminal aparece no histórico da web.
