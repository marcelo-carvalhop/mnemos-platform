# Segurança e fronteiras de confiança

Há três credenciais distintas: bearer humano para conta e API, bearer exclusivo do terminal para rotas `/v1/terminal/*` e token efêmero da sessão HTTP local v4. O servidor emite e armazena apenas o hash do token físico; o firmware guarda a forma utilizável para reconexão e exige revogação em caso de perda. O QR local carrega senha do SoftAP temporário quando necessário e o token de sessão; ele não deve carregar senha da infraestrutura do usuário nem bearer humano. Tratar a exibição e a captura do QR como uma operação sensível.

| Fronteira | Autorização e transporte | Falha a evitar |
| --- | --- | --- |
| Móvel/web → API | Conta autenticada, autorização por `user_id`, HTTPS em implantação pública | Aceitar IDs enviados no corpo como identidade ou autorização. |
| Terminal → API | Token restrito e revogável; decks desejados/reportados verificados no servidor | Entregar snapshot fora de escopo ou ingerir review de cartão alheio. |
| Móvel → terminal | Token temporário em `?token=`, modo `provision` ou `sync`, LAN/SoftAP temporários | Confundir token local com credencial de API; deixar a sessão exposta indefinidamente. |
| Firmware → HTTPS | Certificado validado por CA compilada ou `/backend_ca.pem` | Desabilitar verificação de TLS para contornar falhas de configuração. |

`LocalLinkService` limita a sessão local por timeout de 300 segundos e retorna 401 para token inválido. O transporte local é HTTP, de modo que a senha efêmera do SoftAP e o token de sessão não devem ser tratados como sigilo de ponta a ponta em uma LAN compartilhada. O backend usa IDs imutáveis de revisão para deduplicação; confirmar a outbox exige prova de persistência de cada evento, inclusive quando um cartão não está presente no cliente móvel. O fluxo móvel atual ainda não garante isso, e o envio direto da outbox ao backend recebe 422: [matriz de integração](../integration/t5-touch.md).

O terminal valida o snapshot e capacidade antes de trocar a biblioteca; a API devolve 409 em excesso, em vez de truncar. A atualização local A/B exige manifesto, SHA-256, geração maior, tamanho dentro do slot e bateria suficiente quando detectada. A existência de dois slots não garante rollback automático do bootloader; verifique essa configuração no hardware antes de prometer recuperação autônoma. Consulte [`firmware/t5-touch/README.md`](../../firmware/t5-touch/README.md).

Segredos de ambiente e certificados devem ficar fora do repositório. Logs e telemetria podem conter ID do dispositivo, versão, request ID, código HTTP e contagens; nunca incluir token, senha Wi-Fi, QR completo ou corpo privado de cards/reviews. Uma instalação pública também precisa de política de backup, retenção e observabilidade, que não se deduzem do Compose de desenvolvimento.
