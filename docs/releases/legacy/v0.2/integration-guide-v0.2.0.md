# Guia de integração — Mnemos 0.2.0

O pacote desta versão contém dois projetos independentes que implementam um único fluxo. O firmware `mnemos-firmware-cyd-v0.2.0` deve ser compilado para o ESP32-2432S028 pelo PlatformIO. O aplicativo `mnemos-android-v0.2.0` continua sendo um projeto Flutter e deve executar `flutter pub get` antes da primeira compilação, porque foram adicionadas as dependências `mobile_scanner` e `http`.

Depois de gravar o firmware, a tela inicial do terminal apresenta a ação “CONECTAR CELULAR”. Essa ação inicia a rede temporária e mostra o QR Code. No aplicativo, “Terminal Mnemos” está disponível no cabeçalho da tela Hoje e em Configurações. O leitor de QR inicia a solicitação de conexão do Android. Em Android 10 ou superior, a confirmação de conexão é apresentada pelo próprio sistema operacional. Uma vez conectado, o aplicativo atualiza a hora do terminal, consulta as capacidades do firmware, permite selecionar baralhos e executa a sincronização bidirecional.

O protótipo limita o envio a 48 cartões porque o ESP32-2432S028 possui recursos de memória significativamente menores que a plataforma e-paper planejada. O aplicativo impede o envio quando a seleção excede o limite informado pelo próprio terminal. A futura LILYGO T5 poderá implementar o mesmo protocolo com capacidade maior sem alterar a experiência do aplicativo.

A aplicação Android usa HTTP local exclusivamente durante o pareamento, razão pela qual `usesCleartextTraffic` permanece habilitado no manifesto desta versão. Essa exceção deve ser revista quando o protocolo do hardware definitivo for estabilizado.

Este pacote foi modificado e validado por inspeção estática no ambiente de geração. O ambiente não dispõe do SDK Flutter nem do PlatformIO CLI, portanto não foi possível executar uma compilação real do APK ou do firmware. A primeira validação física deve confirmar compilação, orientação do TFT, leitura do touchscreen, geração do QR Code e comportamento do diálogo de rede no aparelho Android usado nos testes.
