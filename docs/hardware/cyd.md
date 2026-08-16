# Mnemos Terminal CYD v0.4.0

Firmware provisório para ESP32-2432S028. A v0.4 separa estudo, sincronização e conexão na HMI do terminal e introduz Device Protocol v3, perfis de rede conhecidos, provisionamento AP-only, desired-state sync via backend e sincronização direta BLE sob demanda. O conteúdo demonstrativo permanece um único deck `Redes de Computadores` com 10 cards.

A tela **Conexão** configura transporte. Ao iniciar o provisionamento, o terminal suspende Station e cria um SoftAP exclusivo `MNEMOS-...` em `192.168.4.1`; o app grava um `mnemos.network-profile/v1` e, opcionalmente, credencial restrita do backend. Nenhum deck é transferido nesta operação. Somente depois de `/v3/pairing/complete` o SoftAP é encerrado e o terminal volta a procurar redes conhecidas em modo Station.

A tela **Sincronização** oferece backend quando o Wi-Fi está online e BLE direto quando o usuário inicia uma sessão com o celular. BLE transporta os mesmos `mnemos.sync/v1` e `mnemos.review-batch/v1`; a biblioteca só é substituída após validação/commit completo, e reviews só são apagados depois do ACK.

O gerenciador de rede persiste até oito perfis, preserva as credenciais quando Wi-Fi é desligado e só procura outra rede quando está desconectado. A build anuncia explicitamente se Enterprise por usuário/senha está disponível. Captive portal genérico e autenticação Enterprise por certificado não fazem parte da referência v0.4.

O perfil de capacidade do CYD continua deliberadamente restrito: até 48 cards, `type=basic`, `format=plain` e payload local máximo de 90000 bytes. Use `/v3/info` para negociar capacidades em vez de inferir pelo nome da placa.

Abra esta pasta no PlatformIO e compile o ambiente `esp32-2432s028`. As dependências externas são TFT_eSPI, XPT2046_Touchscreen, ArduinoJson 7 e QRCode; Wi-Fi/BLE vêm do framework ESP32 Arduino. As especificações normativas ficam em `spec/` e o guia consolidado em `docs/MNEMOS_V0.4_IMPLEMENTATION_GUIDE.md`.
