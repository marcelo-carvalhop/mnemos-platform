# Provisionamento e conectividade do T5 Touch

O provisionamento configura o terminal físico sem acoplar o estudo à presença do telefone. A HMI expõe uma sessão local temporária em modo `provision` ou `sync`. Se já existe Wi-Fi funcional, `LocalLinkService` anuncia o IP da LAN sem alternar a interface; caso contrário, inicia SoftAP com SSID `MNEMOS-<sufixo>` e senha efêmera. O QR `mnemos://local` contém `v=4`, modo, transporte, host, identificador, dados do acesso temporário, token efêmero, modelo e firmware. Esse QR é uma credencial de sessão local, não o bearer da conta nem a senha da infraestrutura a ser configurada.

## Transação de provisionamento

1. O app lê o QR e, se a API é alcançável, registra o terminal com credencial própria; falha no registro não impede operação offline. A biblioteca desejada começa vazia, salvo seleção explícita posterior.
2. O app conecta ao endereço indicado, envia o relógio a `POST /v4/time` e lê `/v4/info`, inclusive capacidades. A conexão em SoftAP pode interromper o acesso normal do telefone à Internet; registrar antes evita depender da API durante essa etapa.
3. Em `mode=provision`, `POST /v4/provision` recebe `mnemos.provision/v2`: `networkProfile`, intervalo e, opcionalmente, `backend.baseUrl` e `backend.deviceToken`. O firmware guarda o perfil de rede e a credencial física, sem transferir o bearer humano. O modo `sync` não aceita essa rota (409).
4. `POST /v4/complete` encerra a sessão local e devolve a política normal de conexão. `/v4/network/status` informa conectividade e último erro; não equivale a confirmação de sincronização de conteúdo ou revisões.

O perfil de rede admite rede aberta ou pessoal e pode anunciar `enterprise-password` somente se a build oferecer suporte. O app consulta essa capacidade antes de enviar Enterprise. Redes conhecidas e preferência de rádio são persistidas; scans e reconexão usam fluxo cooperativo para não congelar a HMI. O RTC e a obtenção posterior de NTP seguem caminhos separados. Informações de protocolo e semântica dos perfis estão em [`spec/protocol/provisioning-v2.md`](../../spec/protocol/provisioning-v2.md).

## Sincronização local e remota

`mode=sync` aceita `POST /v4/sync/library`, `GET /v4/sync/reviews`, `POST /v4/sync/reviews/ack` e `GET /v4/metrics`. O token do QR é obrigatório em `?token=`; uma requisição em modo errado recebe 409. O móvel coleta revisões antes de transmitir o snapshot, mas o ACK atual limpa toda a outbox e pode incluir revisões que a importação ignorou por falta do cartão local. Tratar esse caso como bloqueador de integridade, conforme [integração](../integration/t5-touch.md#directsync-e-confirmação). Não confundir sucesso de `/v4/complete` com persistência remota dos eventos.

Depois do provisionamento, `BackendSyncService` usa a rede de infraestrutura para falar com `/v1/terminal/*`. `10.0.2.2` é exclusivo do emulador Android e não resolve o backend para um ESP32 real. Usar endereço LAN roteável pelo terminal ou hostname HTTPS com CA configurada em `Config::BACKEND_ROOT_CA` ou `/backend_ca.pem`. HTTPS sem CA é recusado; HTTP deve ficar restrito a laboratório/LAN controlada. Se a rede falhar, conteúdo e histórico local permanecem utilizáveis, e a outbox deve aguardar a próxima tentativa.
