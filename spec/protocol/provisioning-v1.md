# Mnemos Provisioning and Wi-Fi v1

## 1. Objetivo

A operação `CONFIGURAR / SINCRONIZAR` não cria uma dependência permanente do telefone. Ela abre um canal temporário para o app provisionar o terminal. Depois, o terminal permanece conectado à mesma infraestrutura Wi-Fi informada pelo usuário e pode sincronizar diretamente com um backend compatível.

## 2. Estados

`UNPROVISIONED` significa ausência de credenciais de infraestrutura. `ONLINE` significa rádio habilitado e associação ao AP configurado. `OFFLINE_RETRY` significa credenciais preservadas mas rede temporariamente indisponível. `RADIO_OFF` significa rádio explicitamente desligado pelo usuário; SSID, senha, backend e token continuam persistidos.

## 3. Sequência completa

O terminal abre SoftAP WPA2 temporário e mostra QR. O app lê o QR e, antes de abandonar a Internet normal, pode registrar o terminal no backend e obter um token de dispositivo. O app tenta identificar o SSID atual apenas como conveniência; o campo permanece editável. A senha da rede precisa ser fornecida pelo usuário, pois o fluxo não depende de recuperar senha salva pelo Android.

O app pede ao Android uma conexão local ao SoftAP, sincroniza relógio, envia `mnemos.provision/v1`, transfere biblioteca e coleta reviews. O ESP32 fica em AP+STA enquanto tenta a infraestrutura. O app consulta `/v2/network/status`. Ao concluir, chama `/v2/pairing/complete`, libera a rede temporária no Android e o terminal encerra o SoftAP.

## 4. Android

Android 10+ usa `WifiNetworkSpecifier` para a solicitação de rede local. Android 13+ requer tratamento da permissão `NEARBY_WIFI_DEVICES` para operações Wi-Fi compatíveis com esse modelo; versões anteriores podem exigir `ACCESS_FINE_LOCATION` conforme API/target. O projeto pede permissões em runtime e mantém entrada manual de SSID quando o sistema não expõe o nome atual.

Referências oficiais: https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap e https://developer.android.com/develop/connectivity/wifi/wifi-permissions.

## 5. Perfil de rede suportado

O CYD v0.3 aceita SSID de 1..32 caracteres e senha vazia para rede aberta ou 8..63 caracteres para rede pessoal. Redes 802.1X/Enterprise, portais cativos e fluxos que exigem navegador não fazem parte do perfil atual. Um app deve informar isso antes de prometer provisionamento em ambientes corporativos.

## 6. Persistência no firmware

O namespace `mnemos-net` armazena `enabled`, `ssid`, `password`, `backend`, `token` e `sync`. Desligar Wi-Fi altera apenas `enabled=false`; não apaga segredo nem escopo. Reprovisionar substitui credenciais. Reset de fábrica futuro deve limpar esse namespace explicitamente.

## 7. Economia de bateria

O botão `DESLIGAR WI-FI` chama uma desativação real do rádio. Estudo, scheduling local e log de reviews continuam funcionando. `LIGAR WI-FI` ativa o rádio, reconecta e dispara sincronização quando há backend. Quando habilitado mas sem rede, o firmware espaça tentativas automáticas em vez de executar loop agressivo.

A sincronização periódica padrão é 30 minutos, configurável de 5 minutos a 24 horas. Essa estratégia evita uma conexão permanente apenas para verificar atualizações. Referência oficial para modos de Wi-Fi do ESP32: https://docs.espressif.com/projects/arduino-esp32/en/latest/api/wifi.html.

## 8. Falhas recuperáveis

Senha incorreta, AP fora de alcance e backend indisponível não apagam biblioteca. O terminal pode concluir o provisionamento de conteúdo local mesmo se a infraestrutura não for confirmada. O usuário pode abrir `CONFIGURAR / SINCRONIZAR` novamente e substituir dados de rede.

## 9. Relação com backend

Se o backend estiver configurado e alcançável, o terminal sincroniza imediatamente após concluir o pareamento, ao habilitar Wi-Fi e nos intervalos periódicos. Reviews são enviados primeiro; depois o snapshot de conteúdo é obtido. Assim, o snapshot pode ser construído depois de o servidor conhecer os eventos mais recentes do próprio terminal.
