# Manifesto do pacote inicial

Este monorepositório foi consolidado a partir da linha Mnemos v0.3.0. O objetivo é produzir um ponto de partida limpo para Git, e não armazenar ZIPs históricos dentro do próprio histórico do repositório.

O código corrente do aplicativo Flutter foi colocado em `app/mobile/`; o backend em `backend/`; o firmware CYD em `firmware/cyd/`; os schemas e protocolos públicos em `spec/`; o Developer Integration Specification e o guia técnico de Card Schema foram preservados em `docs/reference/`; os documentos v0.2 relevantes foram mantidos em `docs/releases/legacy/v0.2/`; e os experimentos de geração foram preservados em `tools/experiments/`.

Os arquivos ZIP de v0.1, v0.2 e v0.3 não são incorporados ao repositório, porque duplicariam o código-fonte e aumentariam desnecessariamente o histórico Git. Depois do primeiro push, pacotes distribuíveis devem ser anexados a GitHub Releases associados às tags correspondentes.

A pasta `app/web/` e a pasta `firmware/t5/` foram criadas como pontos de extensão sem selecionar prematuramente um framework web ou uma implementação de hardware.
