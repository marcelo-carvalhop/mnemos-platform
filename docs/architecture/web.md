# Arquitetura prevista para o cliente web

O cliente web será implementado em `app/web/`. Ele deverá utilizar a API do backend e os mesmos conceitos de domínio, mas não depender de detalhes internos do Flutter ou do banco local do mobile.

A seleção de framework permanece aberta. Essa decisão deve ser tomada a partir de requisitos concretos de autoria, análise, autenticação, distribuição e manutenção. A estrutura atual permite adotar uma aplicação TypeScript, Flutter Web ou outra tecnologia sem alterar os contratos públicos.
