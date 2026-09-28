# Aplicativo móvel Mnemos

Cliente Flutter para Android/iOS. O móvel permite estudar, criar e organizar cartões, acompanhar progresso, utilizar geração assistida e configurar um terminal dedicado. O estudo móvel produz revisões no mesmo histórico da web e do backend. A biblioteca e a outbox persistem em Drift/SQLite, de modo que uma sessão local não depende continuamente da rede.

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Os pacotes do domínio ficam em `packages/` e são referenciados por caminho no `pubspec.yaml`. O código gerado de `shared/contract.yaml` é verificado a partir da raiz com `python shared/generate.py --check`. Consulte [a arquitetura móvel](../../docs/architecture/mobile.md) para persistência, sincronização e divisão dos pacotes.

## Terminal e rede

O módulo `lib/device/` decodifica QR, consulta o Device Protocol v4, provisiona a credencial restrita e executa DirectSync por LAN ou SoftAP temporário. A importação preserva IDs para deduplicação e o parser aceita `reviewedAt` em segundos ou `reviewedAtMs` em milissegundos. Contudo, se o cartão estiver ausente no SQLite, o evento é ignorado e o ACK posterior pode apagar a outbox inteira do terminal. A correção e o teste de integridade necessários estão em [DirectSync e confirmação](../../docs/integration/t5-touch.md#directsync-e-confirmação).

O Android pode exigir permissões Wi-Fi e localização para listar redes próximas; o SSID permanece editável manualmente e a senha não é lida do sistema. Uma URL que só funciona no emulador, como `10.0.2.2`, não deve ser provisionada no ESP32 físico. O construtor atual de snapshots para terminal emite `open_recall`; os demais tipos não devem ser anunciados como integrados ponta a ponta até resolver [a lacuna de conteúdo](../../docs/integration/t5-touch.md#conteúdo-e-tipos-de-cartão).
