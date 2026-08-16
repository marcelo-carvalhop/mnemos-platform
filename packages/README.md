# Packages compartilhados entre aplicações

Este diretório está reservado para pacotes que sejam realmente reutilizados por mais de uma aplicação de alto nível, por exemplo mobile e web. Os pacotes Dart atuais permanecem em `app/mobile/packages/` para preservar as dependências relativas e evitar uma migração sem benefício imediato.

Quando um módulo passar a ser compartilhado entre clientes diferentes, ele pode ser promovido para esta área mediante uma mudança explícita de build e documentação.
