# Mnemos Device Protocol v4

O v4 é o protocolo obrigatório do firmware CYD v0.5. Todo request local usa HTTP em `192.168.4.1` e o token efêmero do QR como query parameter `?token=...`.

`GET /v4/info` retorna identidade, firmware, modo local e capabilities. `POST /v4/time` aceita `{ "epochSeconds": ... }`. `GET /v4/network/status` retorna estado de conectividade. `POST /v4/provision` é permitido somente em `mode=provision` e recebe `mnemos.provision/v2`. `POST /v4/sync/library` é permitido somente em `mode=sync` e recebe `mnemos.sync/v2`. `GET /v4/sync/reviews` retorna `mnemos.review-batch/v2`. `POST /v4/sync/reviews/ack` confirma persistência dos eventos pelo cliente e limpa apenas a outbox. `GET /v4/metrics` retorna `mnemos.metrics/v1`. `POST /v4/complete` encerra SoftAP e restaura a política STA.

O cliente deve consultar `/v4/info` antes de sincronizar e obedecer `maxCards`, `maxOptions`, `cardTypes` e `contentFormats`.
