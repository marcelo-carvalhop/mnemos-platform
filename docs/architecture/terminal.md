# Terminal dedicado

Esta ramificação desenvolve `firmware/t5-touch/` para o T5-4.7-S3 com e-paper 960×540 e entrada capacitiva. A variante sem touch em `firmware/t5/` e o protótipo CYD em `firmware/cyd/` permanecem separados; não se deve aplicar a eles automaticamente limites, controles ou procedimentos da variante touch. O terminal é uma forma de estudo da plataforma, não a única superfície de revisão.

A HMI por toque apresenta uma pergunta por vez e usa tentativa mental, revelação e autoavaliação; nenhum tipo requer digitação. O firmware anuncia cinco tipos de cartão em `/v4/info`, limite de catálogo ativo de 128 cartões, `typedRecall=false` e `bleSync=false`. O cálculo FSRS e as sessões ocorrem localmente. RTC PCF8563 e controlador GT911 compartilham I²C; a orientação pode ser alterada na HMI. Os detalhes de desenho estão em [../ux/HMI_T5_TOUCH_GUIDELINES_v0.1.md](../ux/HMI_T5_TOUCH_GUIDELINES_v0.1.md).

Quando há microSD, as definições completas residem em `/mnemos/library/cards.ndjson` e a RAM contém um catálogo leve; a definição ativa é carregada quando necessária. LittleFS retém estados, histórico, outbox, cursores e retomada de sessão, além de fallback de biblioteca; perfis e token remoto ficam em NVS. Rede e NTP são conduzidos sem espera bloqueante na HMI. O SoftAP é fallback local e a LAN pode hospedar a ligação temporária. HTTPS exige CA compilada ou `/backend_ca.pem`; HTTP deve ser restrito à bancada/LAN controlada.

O firmware contém sleep em dois níveis e OTA local A/B por microSD, com manifesto, SHA-256, geração monotônica e limite de tamanho. A build padrão é de bancada e desliga sleep/OTA automática; a build de produto habilita esses comportamentos. O rollback automático do bootloader não deve ser presumido sem sua configuração e prova no dispositivo. Consulte [firmware/t5-touch/README.md](../../firmware/t5-touch/README.md) e [BENCH_BUILDS.md](../../firmware/t5-touch/docs/BENCH_BUILDS.md).

O envio de revisões à API está implementado como tentativa e preserva a outbox após erro, mas não é compatível com a validação atual do servidor. A matriz de payload e os critérios de teste estão em [../integration/t5-touch.md](../integration/t5-touch.md).
