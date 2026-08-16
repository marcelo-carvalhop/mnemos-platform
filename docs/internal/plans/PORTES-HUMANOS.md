# Portes humanos

Três coisas que o código está pronto para receber e que **eu não consigo
concluir daqui**, porque nenhuma delas é sobre escrever código: todas precisam
de uma conta, um aparelho ou um cartão em nome de alguém.

Cada uma abaixo diz exatamente o que falta, onde o código já espera, e como
verificar que funcionou. Nada aqui é "depois a gente vê" — são as últimas
coisas entre o app e uma loja.

---

## 1. Credenciais de atestação (§8.1)

**Por que é um portão.** O verificador exige uma service account do Play
Console e um iPhone real. Não dá para simular: um Play Integrity token só é
emitido para um APK que o Google reconhece, e o App Attest é assinado por
hardware da Apple.

**Por que importa mais do que parece.** O plano grátis é uma geração para toda
a vida da conta (§7.7.1). Sem atestação, reinstalar dá outra — e reinstalar é
grátis. É a diferença entre um custo previsível e uma torneira aberta.

### Android — Play Integrity

1. No Play Console, ativar a Play Integrity API para `br.com.flashcards.flashcards`.
2. Criar uma service account no projeto GCP vinculado, com o papel de
   **Play Integrity API user**, e baixar a chave JSON.
3. No ambiente do servidor:
   ```
   PLAY_INTEGRITY_PACKAGE=br.com.flashcards.flashcards
   GOOGLE_CREDENTIALS_JSON=<conteúdo do JSON, em uma linha>
   REQUIRE_ATTESTATION=true
   ```
4. No app, produzir o token com o plugin de integridade e enviá-lo em
   `POST /v1/auth/device` junto com o `nonce` de `POST /v1/auth/challenge`.
   **O lado do app é o que falta em código** — o servidor já verifica.

**Como saber que funcionou:** um device registra e recebe token; um emulador
é recusado com `device integrity not met`. O segundo é o teste que importa.

### iOS — App Attest

1. Ativar a capability *App Attest* no perfil do app.
2. `APP_ATTEST_APP_ID=<TEAM_ID>.br.com.flashcards` e a raiz da Apple em
   `APP_ATTEST_ROOT_PEM` (de <https://www.apple.com/certificateauthority/>).
3. Produzir o attestation object no app e enviá-lo do mesmo jeito.

**Já está pronto no servidor:** cadeia até a raiz, nonce, app id, contador
zero e unicidade da chave. O que nunca rodou é contra um attestation real.

---

## 2. Billing das lojas (§5.13)

**Por que é um portão.** Precisa de produtos configurados no Play Console e no
App Store Connect, de uma conta de sandbox, e de um build assinado. Uma compra
de teste não existe fora disso.

**O que já está no lugar:** o servidor recusa a segunda geração com **402**, o
app abre o paywall nesse código, e a tela de assinatura (§5.13) existe
separada do paywall. Os dois botões que tocam a loja — *Assinar* e *Restaurar
compras* — estão **desabilitados com a frase "A loja ainda não está ligada
nesta build"**. Isso é deliberado: um botão que parece cobrar e não cobra é
pior que um que admite não estar pronto.

**O que falta:**

1. Produtos: uma assinatura mensal e uma anual, nos dois lados.
2. `in_app_purchase` no app, com a compra e o restore.
3. Um endpoint que **valide o recibo no servidor** e conceda o direito. Sem
   isso o direito vive no cliente, que é o mesmo que não existir.
4. O caminho do §5.13 que não passa por loja nenhuma: "assinatura inclusa na
   compra do aparelho", que é uma concessão pelo servidor e precisa coexistir
   com o estado vindo da loja sem um sobrescrever o outro.

**Como saber que funcionou:** comprar no sandbox, reinstalar, restaurar, e ver
a cota mudar de `free` para o plano pago sem passar por suporte.

---

## 3. Build iOS

**Por que é um portão.** Precisa de macOS. Não há como contornar.

**O que já está pronto:** o projeto foi criado com `--platforms=android,ios`,
o código é todo Flutter e Dart puro, e nada no app usa API só de Android. As
dependências nativas — `flutter_secure_storage`, `flutter_local_notifications`,
`flutter_tts`, `image_picker`, `file_picker`, `sqlite3_flutter_libs` — todas
têm suporte a iOS.

**O que provavelmente vai aparecer na primeira tentativa,** com base no que
apareceu no Android:

- `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` no
  `Info.plist` — §5.6 usa câmera e galeria, e o iOS derruba o app sem a
  string, em vez de só negar a permissão.
- Permissão de notificação pedida no momento certo: o
  `DarwinInitializationSettings` está com os três `request*` em `false`
  justamente para que o pedido aconteça quando o usuário liga o lembrete, não
  na primeira abertura.
- Deployment target mínimo — o Android precisou subir para 24 pelos plugins;
  o iOS provavelmente vai precisar de 12 ou 13.

**Como saber que funcionou:** `flutter build ios`, rodar no simulador, e andar
o mesmo roteiro que eu andei no emulador Android — onboarding, um card,
estudar, gerar, aprovar.

---

## 4. Julgamento sobre a qualidade dos cards

Não é técnico e por isso é fácil de adiar. Duas gerações reais rodaram e o
resultado está no banco; eu li e achei bom, mas "bom" para mim não é o mesmo
que bom para quem está estudando redes de computadores. Vale gerar sobre um assunto que
você conhece de verdade e julgar.

O que observar, porque é o que o prompt tenta garantir: um card testa uma
ideia só; a frente é pergunta direta; o verso é a resposta mínima, sem "trata-
se de"; e nada sobre metadados do material.
