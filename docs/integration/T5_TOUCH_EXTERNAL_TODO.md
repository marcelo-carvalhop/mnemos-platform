# T5 Touch — TODO de integração externa

Este arquivo registra somente dependências que pertencem a App, Web ou
Backend. O firmware não altera essas áreas.

## LocalLink / App

O QR pode usar:

- `transport=lan`: `host` é o IP atual do terminal na mesma rede;
- `transport=ap`: fallback SoftAP.

O App não deve assumir `host=192.168.4.1`.

## Capabilities

Tratar como normativo:

```text
primary=touch
touch=true
keyboard=false
typedRecall=false
microSD=true
bleSync=false
display=epaper-960x540
```

## Estudo

No T5 Touch, inclusive `multiple_choice` e `true_false` usam tentativa mental,
revelação e autoavaliação. Não inferir correção automática apenas pelo tipo.

## Timezone

Definir futuramente um campo de timezone por usuário/terminal. Preferir
identificador IANA quando o contrato compartilhado suportar; offset numérico
pode ser transitório.

## OTA

O firmware implementará a instalação, mas a distribuição depende de manifesto
externo com:

- versão;
- modelo de hardware;
- URL HTTPS;
- tamanho;
- SHA-256;
- versão de protocolo compatível;
- obrigatória/opcional.

Não distribuir OTA sem HTTPS e hash.

## Biblioteca SD-first

O firmware passará a manter decks completos no microSD e apenas um cache ativo
em RAM. `max_cards` deverá representar capacidade do cache ativo, não tamanho
máximo da biblioteca do usuário.

Snapshot/sync não deve presumir que toda a biblioteca cabe simultaneamente em
RAM.

## Redes corporativas

Credenciais EAP/certificados devem continuar vindo por provisionamento externo.

## T5S3 Pro

A migração futura deve preservar os contratos acima e expor novas capacidades
de bateria/PMIC via capability.


## Energia / wake

A T5-4.7-S3 atual anuncia `deepSleepTouchWake=false`: o GT911 usa GPIO47 e
não pode acordar EXT0/EXT1 no ESP32-S3. Interfaces externas não devem instruir
o usuário a tocar para acordar quando o terminal estiver em deep sleep. O wake
suportado é o botão onboard GPIO21.

No futuro T5S3 Pro essa capability deve ser reavaliada.


## Biblioteca SD-first — paginação

Na `0.7.0-preview.3`, `max_cards=128` representa a capacidade do catálogo
ativo em RAM. O microSD pode armazenar mais conteúdo, mas o contrato atual de
snapshot ainda entrega no máximo esse conjunto.

Para bibliotecas maiores, App/Backend devem futuramente suportar seleção de
decks ou snapshot paginado/deck-scoped. O firmware não deve ser obrigado a
carregar toda a biblioteca textual simultaneamente.



## OTA remota / distribuição

O firmware implementa primeiro OTA local verificada pelo microSD. Para
distribuição remota, Backend/App não devem enviar binário diretamente para a
flash do terminal. O contrato recomendado é um manifesto HTTPS
`mnemos.ota/v1` com os mesmos campos usados localmente:

- `version`;
- `generation` monotônica;
- `model`;
- `protocolMin` / `protocolMax`;
- `size`;
- `sha256`;
- URL HTTPS da imagem.

A imagem remota deverá ser baixada para staging no microSD, verificada e só
depois instalada no slot OTA.

Para produção, adicionar assinatura criptográfica do manifesto/imagem com uma
chave pública embarcada no firmware. SHA-256 + TLS protegem integridade em
trânsito e correspondência da imagem, mas não substituem code signing contra
comprometimento do servidor de atualização.

Nenhum endpoint de Backend é criado ou modificado pelo firmware.

