# Testes ponta a ponta: terminal ↔ backend

Compila no PC o código **real** de sincronização do firmware
(`backend_sync_service.cpp`, `sync_codec.cpp`, `storage.cpp`,
`text_sanitizer.cpp`, `terminal_identity.cpp`) com stubs mínimos de Arduino,
LittleFS (pasta local) e HTTPClient (socket HTTP) e o roda contra um backend de
verdade. O conteúdo é criado pelos mesmos endpoints que o app e a web usam.

## Como rodar

```bash
# na raiz do monorepo
docker compose up -d && docker compose run --rm migrate

cd firmware/t5s3-pro
pio run -e t5s3-pro-bench          # baixa o ArduinoJson para .pio/libdeps
./tools/host_sync/run.sh            # MNEMOS_API=http://localhost:8000 por padrão
```

Precisa de `g++` (C++17) e Python 3. No Windows, use WSL.

## O que é verificado (31 checagens)

1. Terminal com biblioteca local (microSD) e outbox sujo: prática não sobe,
   relógio inválido e linha corrompida vão para quarentena, revisões de
   cartões que não existem na conta recebem 403 e também vão para quarentena
   sem travar a fila; snapshot vazio não apaga a biblioteca local; o status é
   aceito (sem reportar baralhos locais, que fariam o backend responder 500).
2. Baralhos escolhidos no app/web chegam ao terminal; texto normalizado para
   as fontes do e-paper (aspas, setas, gregos, índices, emoji).
3. Sincronização sem mudanças não regrava nada.
4. Revisões do terminal (ids UUIDv7) aparecem no histórico da conta com o id
   do terminal como dispositivo.
5. Revisões feitas no app chegam ao terminal, sem duplicar depois.
6. Cartão editado na web é atualizado no terminal.
7. Cartão apagado no app com revisão pendente: só ela vai para quarentena.
8. Retenção desejada alterada no app é aplicada (uma vez).
9. Biblioteca acima da capacidade: 409 vira mensagem, biblioteca preservada.
10. Relógio sem referência é ajustado pelo cabeçalho `Date` do backend.
11. Backend fora do ar: nada se perde; a fila esvazia quando ele volta.
12. Nova credencial reinicia cursores sem duplicar histórico.
13. Terminal revogado na web: 401 vira "credencial recusada" e as tentativas
    automáticas param.
14. Pedido de sincronização sem Wi-Fi espera a rede.
15. Terminal não pareado não faz requisições.
