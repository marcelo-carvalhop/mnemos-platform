# Conectividade

Na v0.4, Conexão e Sincronização são responsabilidades separadas. O provisionamento temporário identifica o terminal e grava um `mnemos.network-profile/v1` mais uma credencial restrita do backend quando disponível; ele **não transfere decks**.

O SoftAP de provisionamento opera em modo AP exclusivo. Somente após `/v3/pairing/complete` o terminal encerra o AP e volta ao modo Station. O terminal persiste múltiplas redes conhecidas, tenta autoconexão apenas quando está desconectado e mantém perfis mesmo com o rádio Wi-Fi desligado.

BLE é um transporte direto de sincronização iniciado pelo usuário e desligado após a sessão. Veja `docs/architecture/connectivity-v0.4.md` para o desenho completo.
