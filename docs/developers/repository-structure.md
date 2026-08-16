# Estrutura do monorepositório

```text
mnemos-platform/
├── app/
│   ├── mobile/        Flutter Android/iOS
│   └── web/           futuro cliente web
├── backend/           backend oficial/de referência
├── firmware/
│   ├── cyd/           protótipo ESP32-2432S028
│   └── t5/            port futuro LILYGO T5
├── spec/              contratos normativos
├── docs/              documentação explicativa
├── shared/            contrato interno gerado Dart/Python
├── packages/          reservado para pacotes realmente cross-app
├── tools/             validação, scripts e experimentos
└── .github/           CI, PR e templates
```

A regra central é separar contrato de implementação. `spec/` define interoperabilidade; `app/`, `backend/` e `firmware/` são consumidores desses contratos. `docs/` explica decisões, enquanto `shared/` contém um contrato interno específico das implementações oficiais.
