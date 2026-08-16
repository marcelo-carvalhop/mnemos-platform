# Mnemos Web

Este diretório está reservado para o futuro cliente web oficial do Mnemos. Nenhum framework foi escolhido neste momento; a decisão poderá ser tomada posteriormente sem alterar a organização do monorepositório.

A aplicação web deverá ser um cliente independente do backend, nunca um consumidor direto do banco interno do aplicativo móvel. As responsabilidades previstas incluem criação e edição em massa de decks e cards, importação e exportação, análise de histórico e retenção, gerenciamento de dispositivos, configurações de conta e administração de sincronização.

Qualquer implementação deve consumir a API pública/estável do backend e utilizar os contratos definidos em `../../spec/` quando trocar objetos interoperáveis.
