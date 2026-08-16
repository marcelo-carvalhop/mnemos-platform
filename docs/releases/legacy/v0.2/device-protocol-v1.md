# Protocolo de integração Mnemos — versão 1

## Objetivo

O protocolo permite que o aplicativo móvel e o terminal físico troquem dados diretamente, sem internet e sem infraestrutura externa. O terminal atua temporariamente como ponto de acesso Wi-Fi e servidor HTTP local; o telefone atua como cliente. O backend em nuvem do aplicativo permanece independente desse transporte e pode ser sincronizado antes ou depois da sessão local.

## Pareamento

Ao iniciar o modo de pareamento, o terminal cria um SSID no formato `MNEMOS-XXXXXX`, uma senha WPA2 efêmera de oito caracteres e um token aleatório de 128 bits representado em hexadecimal. O QR Code usa o esquema `mnemos://pair` e carrega a versão do protocolo, identificador do dispositivo, SSID, senha, host e token. Um exemplo estrutural é `mnemos://pair?v=1&id=CYD-A1B2C3&ssid=MNEMOS-A1B2C3&pwd=M1234567&host=192.168.4.1&token=<token>`.

O ponto de acesso permanece disponível por 300 segundos. O token somente autentica a sessão local; ele não é credencial de conta e não deve ser persistido pelo aplicativo.

## API local

`GET /v1/info?token=...` retorna versão do protocolo, identificador, versão de firmware, modelo, quantidade atual e capacidade de cartões, além das capacidades de sincronização e do estado do relógio.

`POST /v1/time?token=...` recebe JSON com `epochSeconds` e atualiza o relógio do terminal a partir da hora UTC do telefone.

`GET /v1/reviews?token=...` retorna NDJSON contendo os eventos de revisão ainda não confirmados pelo aplicativo. Cada evento conserva identificador, cartão, instante, grau, tempo de resposta, confiança e intervalos antes/depois.

`POST /v1/library?token=...` substitui a biblioteca local pela seleção enviada pelo aplicativo. O schema 1 transporta identificadores originais, baralho, frente, verso e o estado de agendamento necessário ao terminal. O firmware CYD limita esta operação a 48 cartões por transferência.

`POST /v1/reviews/ack?token=...` confirma que o aplicativo recebeu e integrou o histórico pendente. O firmware então remove o log local transferido. A chamada só ocorre depois de o envio da biblioteca ter sido concluído.

## Ordem transacional de sincronização

A aplicação conecta-se ao ponto de acesso, sincroniza primeiro o relógio, lê e incorpora os eventos pendentes, reconstrói no banco móvel o estado derivado do agendador, prepara a biblioteca selecionada com esse estado atualizado, envia a biblioteca ao terminal e por fim confirma o log de revisões. Essa ordem faz do histórico de eventos a fonte de verdade e reduz o risco de divergência entre o aplicativo e o hardware.

## Limitações da versão 1

A comunicação usa HTTP sem TLS porque ocorre dentro de uma rede WPA2 efêmera criada pelo próprio terminal; o token da sessão adiciona isolamento lógico, mas este protocolo ainda deve ser tratado como mecanismo de protótipo e não como desenho final de segurança. A versão 1 também não transmite anexos, imagens, áudio ou rich text, e a confiança registrada no terminal ainda não é persistida como coluna própria no banco móvel, embora permaneça disponível no log NDJSON durante a sincronização.
