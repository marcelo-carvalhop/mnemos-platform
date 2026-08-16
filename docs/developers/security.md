# Mnemos Security Guide v1

## 1. Fronteiras de confiança

O app autenticado representa uma conta. O terminal representa um dispositivo com escopo reduzido. O QR representa apenas uma sessão local temporária. Essas identidades não compartilham bearer token.

## 2. Segredos

A senha do SoftAP e o token de sessão são gerados para cada pareamento. A senha da infraestrutura é digitada no app e enviada somente pela ligação local. O token de backend é gerado pelo servidor para o terminal. Não inclua senha da infraestrutura no QR.

No servidor, armazene somente forma derivada do token do terminal. No hardware, o token precisa existir em forma utilizável para autenticação futura; trate o armazenamento físico como segredo e projete revogação para perda/roubo.

## 3. TLS

Backend público deve usar HTTPS com validação normal. O firmware de referência não chama `setInsecure()`: URLs HTTPS só são aceitas na sincronização quando `BACKEND_ROOT_CA` foi provisionada no firmware. HTTP existe para bancada/LAN controlada e não é recomendação de produção.

Referência Android sobre TLS: https://developer.android.com/privacy-and-security/security-ssl.

## 4. Autorização

O backend deriva usuário e escopo pelo token autenticado. `deviceId`, `deckId` e `cardId` são referências, não provas. Snapshot é filtrado pelos decks atribuídos. Reviews que apontem para card fora desse escopo recebem rejeição.

## 5. Idempotência e replay

Reviews são append-only com id único. Retry com o mesmo id não cria duplicata. O app preserva o id originado pelo terminal ao retransmitir um review ao backend, evitando duplicação entre caminho direto e caminho mediado pelo app.

## 6. Aplicação atômica

Snapshot deve ser validado completamente antes de substituir a biblioteca. Payload acima da capacidade ou card sem capacidade declarada é rejeitado sem aplicar metade da atualização.

## 7. Limites

O CYD v0.3 declara 48 cards, payload local máximo de 90000 bytes e perfil `basic/plain`. O backend deve impor batch máximo, tamanhos de texto e limites de request. Limites são parte tanto de robustez quanto de proteção contra negação de serviço.

## 8. Logs e telemetria

Nunca registre senha Wi-Fi, bearer token, token de QR ou body privado integral. Prefira device id, versão, código HTTP, latência e contagens. Ferramentas de diagnóstico devem aplicar redaction antes de exportar logs.

## 9. Revogação e rotação

Reprovisionamento rotaciona credencial. Backend deve oferecer listagem e revogação por terminal. Uma credencial revogada recebe 401 e o terminal continua apto a estudar offline até ser reprovisionado.
