# Mnemos Device Protocol v2

## 1. Objetivo

O Device Protocol v2 é a API HTTP local usada para provisionar e sincronizar um terminal Mnemos. A rede criada pelo terminal é temporária. Depois que o app entrega Wi-Fi de infraestrutura, relógio, biblioteca e opcionalmente credencial de backend, o SoftAP é encerrado e o dispositivo permanece como estação da rede configurada.

O QR Code usa a forma:

```text
mnemos://pair?v=2&id=<device>&ssid=<softap>&pwd=<softap-password>&host=192.168.4.1&token=<session-token>&model=<model>&fw=<version>
```

O `token` do QR é efêmero, exclusivo da API local e não é a credencial de backend.

## 2. Fluxo de estado

```text
HOME/OFFLINE
    |
    | CONFIGURAR / SINCRONIZAR
    v
SOFTAP TEMPORÁRIO (AP+STA)
    |
    | app envia mnemos.provision/v1
    v
TENTATIVA DE WI-FI DE INFRAESTRUTURA
    |
    | app transfere snapshot e reviews
    v
/v2/pairing/complete
    |
    v
SOFTAP ENCERRADO -> STA ONLINE ou OFFLINE COM CREDENCIAIS PERSISTIDAS
```

## 3. Autorização local

Todos os endpoints v2 exigem `?token=<session-token>`. A sessão expira após cinco minutos no firmware de referência. O token não deve ser persistido pelo app como identidade de longo prazo.

## 4. Endpoints

| Método | Endpoint | Corpo/resposta | Semântica |
|---|---|---|---|
| GET | `/v2/info` | JSON | Identidade, versão, capacidade e estado de rede. |
| POST | `/v2/time` | `{"epochSeconds": ...}` | Ajusta relógio do terminal. |
| POST | `/v2/provision` | `mnemos.provision/v1` | Persiste Wi-Fi, backend e periodicidade. |
| GET | `/v2/network/status` | JSON | Estado da conexão de infraestrutura. |
| POST | `/v2/library` | `mnemos.sync/v1` | Aplica snapshot canônico de forma atômica. |
| GET | `/v2/reviews` | `mnemos.review-batch/v1` | Lê reviews ainda não reconhecidos. |
| POST | `/v2/reviews/ack` | vazio | Confirma persistência dos reviews pelo app. |
| POST | `/v2/pairing/complete` | vazio | Encerra o SoftAP temporário. |

## 5. `/v2/info` e negociação de capacidades

```json
{
  "protocol": 2,
  "deviceId": "CYD-A1B2C3",
  "firmware": "0.3.0",
  "model": "ESP32-2432S028",
  "cardCount": 10,
  "maxCards": 48,
  "clockTrusted": true,
  "wifiEnabled": true,
  "wifiConnected": false,
  "infrastructureSsid": "MinhaRede",
  "features": {
    "canonicalSchemas": true,
    "wifiProvisioning": true,
    "backendSync": true,
    "legacyV1": true
  },
  "capabilities": {
    "cardTypes": ["basic"],
    "contentFormats": ["plain"],
    "maxPayloadBytes": 90000
  }
}
```

Um cliente deve verificar `cardTypes`, `contentFormats`, `maxCards` e `maxPayloadBytes` antes da transferência. O CYD v0.3 rejeita `typed`, `multiple_choice`, `cloze`, `true_false` e `markdown` porque ainda não possui interface de apresentação para esses formatos.

## 6. `/v2/time`

O corpo contém segundos Unix UTC e deve representar uma data plausível. O relógio é importante para due dates e reviews mesmo quando o terminal não consegue NTP durante o SoftAP.

```json
{"epochSeconds": 1786888800}
```

## 7. `/v2/provision`

```json
{
  "schema": "mnemos.provision/v1",
  "wifi": {
    "ssid": "MinhaRede",
    "password": "senha-da-rede"
  },
  "backend": {
    "baseUrl": "https://api.exemplo.com",
    "deviceToken": "token-opaco-restrito-ao-terminal"
  },
  "syncIntervalSeconds": 1800,
  "clockEpochSeconds": 1786888800
}
```

`backend` pode ser omitido para operação local. A senha deve estar vazia para rede aberta ou ter 8..63 caracteres. A implementação CYD atual não configura redes Enterprise.

## 8. `/v2/network/status`

```json
{
  "enabled": true,
  "connected": true,
  "ssid": "MinhaRede",
  "ip": "192.168.1.87",
  "lastError": ""
}
```

Falha de conexão não apaga credenciais. O app pode concluir a biblioteca local e informar que a infraestrutura ainda não foi confirmada.

## 9. `/v2/library`

Recebe um `mnemos.sync/v1`. O firmware valida o documento inteiro antes de substituir a biblioteca. Se exceder `maxCards`, responde 409. Se um card usar capacidade não suportada, responde 422. Erros deixam a biblioteca anterior intacta. Snapshot vazio é aceito e limpa o escopo local.

## 10. Reviews e ACK

`GET /v2/reviews` retorna um `mnemos.review-batch/v1`. O app deve persistir todos os eventos que conseguir e somente então chamar `/v2/reviews/ack`. O mesmo `review.id` deve ser preservado se o evento também for enviado diretamente ao backend; isso garante idempotência entre caminho terminal→backend e terminal→app→backend.

## 11. Encerramento e Wi-Fi do terminal

`POST /v2/pairing/complete` pede o fim da sessão. O terminal responde e encerra o SoftAP. O botão `DESLIGAR WI-FI` desativa o rádio e a sincronização sem apagar SSID, senha, URL ou token. `LIGAR WI-FI` reutiliza as credenciais persistidas e dispara reconexão/sincronização.

## 12. Códigos de erro recomendados

`401` representa token local inválido; `400`, JSON ou schema de transporte inválido; `413`, payload acima da capacidade declarada; `409`, biblioteca excede capacidade; `422`, conteúdo estruturalmente aceitável mas incompatível com o perfil do dispositivo; `500`, falha de persistência.

## 13. Compatibilidade legada

Durante a migração v0.2→v0.3, o firmware mantém `/v1/info`, `/v1/library`, `/v1/reviews`, `/v1/reviews/ack` e `/v1/time`. Novas integrações não devem implementar o formato v1 de biblioteca.
