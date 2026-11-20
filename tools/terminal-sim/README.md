# Terminal simulado

Faz pela rede o mesmo que o firmware `t5s3-pro` faz em `BackendSyncService::syncNow()`: envia a outbox de revisões, baixa o snapshot `mnemos.sync/v2`, puxa revisões, remarcações e preferências e reporta o estado. Serve para testar o contrato entre terminal e backend sem a placa.

Não cobre o firmware em si (parser no ESP32, tela, Wi-Fi, HTTPS com CA) nem o pareamento por QR, BLE ou SoftAP: o terminal é registrado direto pela API, com o token da conta do app.

## Uso

Com o backend no ar (`docker compose up -d`), rode dentro do container, que já tem Python:

```bash
SIM=tools/terminal-sim/terminal_sim.py

# id do aparelho do app e baralhos da conta
docker compose exec -T postgres psql -U flashcards -d flashcards -c \
  "select d.id device, k.id deck, k.name from devices d join decks k on k.user_id = d.user_id"

docker compose exec -T server python - register <device_id> <deck_id>,<deck_id> < $SIM
docker compose exec -T server python - sync    < $SIM   # uma rodada, como a placa
docker compose exec -T server python - study 3 < $SIM   # 3 revisões na outbox
docker compose exec -T server python - sync    < $SIM   # envia as revisões
docker compose exec -T server python - show    < $SIM   # biblioteca local
```

O `register` usa `POST /v1/auth/device` com o id do aparelho do app, que devolve um token novo da mesma conta sem revogar o do app. O estado (token, cursores, biblioteca, outbox) fica em `/tmp/terminal_sim_state.json` no container, como a flash da placa. Recriar o container zera o estado; rode `register` de novo.

## O que observar

- `sync` imprime cards novos, alterados e removidos em relação à rodada anterior e termina com a mesma linha `[backend] sync push=… snapshot=…` que o firmware escreve no serial.
- Revisões de `study` aparecem no app depois da próxima sincronização dele, com `device_id` igual ao id do terminal.
- Mudar os baralhos do terminal (`POST /v1/terminals/{id}/decks`) faz o próximo snapshot remover ou incluir os cards correspondentes.
