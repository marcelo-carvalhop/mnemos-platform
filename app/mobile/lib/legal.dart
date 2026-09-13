/// Os textos e endereços que as lojas exigem antes de cobrar (§5.13).
///
/// Apple App Store Review 3.1.2 e a política de assinaturas do Google Play
/// exigem, **na própria tela de compra**: título e duração da assinatura, preço
/// por período, aviso de renovação automática, e links funcionais para os
/// termos de uso e a política de privacidade. A 3.1.1 exige um caminho de
/// restauração de compra.
///
/// A cópia mora aqui porque aparece em duas telas (o paywall e a assinatura) e
/// duas versões dela divergindo seria exatamente o tipo de coisa que reprova
/// numa revisão.
library;

/// O aviso de renovação automática, em português claro.
///
/// Escrito para ser lido, não para cumprir tabela: diz quando cobra, que
/// renova sozinho, e onde cancelar — que é a informação que as pessoas
/// realmente procuram nesta tela.
const String kRenewalNotice =
    'A assinatura renova sozinha ao fim de cada período e é cobrada na conta '
    'da loja. Dá para cancelar quando quiser, nas assinaturas da própria loja; '
    'cancelar vale a partir do período seguinte.';

/// Endereços dos documentos legais.
///
/// **Nulos de propósito.** São uma entrada de negócio, não uma decisão de
/// engenharia: enquanto não existirem de verdade, um link falso na tela de
/// compra é pior que link nenhum — reprova na revisão e mente para quem toca.
/// As telas escondem as linhas enquanto estiverem nulos.
const Uri? kTermsUrl = null;
const Uri? kPrivacyUrl = null;

/// Se os dois documentos já existem, as telas de compra podem mostrá-los.
bool get hasLegalLinks => kTermsUrl != null && kPrivacyUrl != null;

/// A versão exibida em Configurações.
///
/// Fixa e não lida do `package_info_plus`: o app não tem esse pacote, e
/// acrescentar uma dependência de plataforma para mostrar uma string congela o
/// harness de captura, que roda sem plugins. Atualizar junto do `pubspec` é o
/// preço, e está anotado lá.
const String kAppVersion = '0.4.0';
