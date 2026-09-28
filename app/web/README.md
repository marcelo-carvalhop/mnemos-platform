# Aplicação web Mnemos

Cliente Angular 22 da plataforma. Estudo, biblioteca, criação e aprovação de cartões, progresso, conta e gestão de dispositivo são rotas implementadas em `src/app/app.routes.ts`. A experiência de estudo na web utiliza o mesmo histórico de revisões e o mesmo domínio de agendamento de móvel e servidor. Não depende de estruturas internas do Flutter.

## Desenvolvimento

Usar a versão de Node em `.nvmrc` e instalar dependências a partir deste diretório:

```bash
npm ci
npm start
npm run lint:format
npm run test:ci
npm run build
```

O `Store` em `src/app/core/store.ts` é um espelho reativo em memória; o `Sync` envia a outbox e puxa deltas da API. Ao recarregar a página, o espelho precisa ser reconstruído. O armazenamento do navegador usado pela sessão não constitui persistência offline durável da biblioteca. Consulte [a arquitetura web](../../docs/architecture/web.md) e [o estado de integração](../../docs/status.md).

A web gerencia dados do terminal por meio da conta e da API. A ligação temporária à LAN/SoftAP e o envio local de biblioteca são responsabilidades do aplicativo móvel; a presença de uma página de dispositivo na web não significa acesso direto ao firmware.
