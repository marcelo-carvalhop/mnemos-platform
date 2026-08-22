# Wi-Fi Local Sync v1

DirectSync é o fallback sem infraestrutura. O usuário inicia explicitamente `SINCRONIZAR > COM O CELULAR`; o terminal interrompe temporariamente STA, cria SoftAP `MNEMOS-XXXXXX` em 2,4 GHz e mostra QR. O telefone conecta à rede local sem Internet, executa Device Protocol v4 e encerra com `/v4/complete`. Depois o terminal desliga SoftAP e volta a procurar redes conhecidas.

Provisionamento usa o mesmo mecanismo físico, mas `mode=provision`. A separação de modos é obrigatória: configurar rede não transfere decks e sincronizar conteúdo não altera credenciais Wi-Fi.
