# Roteiro de validacao da v0.1

## 1. Inicializacao

- [ ] A placa aparece como porta serial.
- [ ] O firmware e gravado sem erro.
- [ ] O monitor serial abre em 115200 bit/s.
- [ ] A tela acende e exibe a calibracao no primeiro boot.
- [ ] Os quatro alvos de calibracao aceitam o toque.
- [ ] A tela inicial aparece apos a calibracao.

## 2. Touchscreen

- [ ] O botao `INICIAR SESSAO` responde em toda a sua area.
- [ ] Cada opcao de confianca pode ser selecionada.
- [ ] A opcao selecionada recebe destaque visual.
- [ ] `MOSTRAR RESPOSTA` permanece desabilitado antes da confianca.
- [ ] Os quatro botoes de avaliacao acionam apenas a opcao tocada.
- [ ] Manter o dedo pressionado nao gera varios eventos consecutivos.

## 3. Fluxo de estudo

- [ ] A sessao inicia com dez cartoes no primeiro uso.
- [ ] A pergunta e exibida antes da resposta.
- [ ] A resposta aparece somente apos selecionar a confianca.
- [ ] O progresso avanca de 1/10 ate 10/10.
- [ ] O resumo apresenta os totais corretos por avaliacao.
- [ ] O tempo total da sessao e apresentado.

## 4. Persistencia

- [ ] Concluir pelo menos uma revisao.
- [ ] Reiniciar a placa.
- [ ] Verificar que o numero de revisoes pendentes foi preservado.
- [ ] Aguardar o intervalo comprimido do modo demonstracao.
- [ ] Verificar que o cartao volta a ficar pendente.

## 5. Relogio

### Sem Wi-Fi

- [ ] A tela inicial indica `hora aprox.`.
- [ ] O agendamento funciona enquanto a placa permanece ligada.
- [ ] O sistema continua com um valor monotonicamente crescente apos reiniciar.

### Com Wi-Fi configurado

- [ ] O monitor serial informa conexao a rede.
- [ ] O monitor serial informa sincronizacao NTP.
- [ ] A tela inicial indica `hora online`.

## 6. Recuperacao

- [ ] Manter `BOOT` pressionado durante a inicializacao refaz a calibracao.
- [ ] Desligar durante a tela de pergunta nao corrompe o estado anterior.
- [ ] Desligar depois de avaliar um cartao preserva a avaliacao.

## 7. Evidencias para o relatorio

Registrar:

- fotografia da tela inicial;
- fotografia de uma pergunta;
- fotografia da avaliacao;
- fotografia do resumo;
- trecho do monitor serial com calibracao;
- conteudo de um evento de `/reviews.ndjson`;
- tabela com os resultados de pelo menos cinco sessoes de teste.
