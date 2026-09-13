# Prints do aplicativo Mnemos

Capturados no emulador Android (Pixel, 1080×2400) em 22/08/2026, na versão que
está em `app/mobile/`. São a interface real, não mockups — o que está aqui
roda.

A conta usada tem dois cards escritos à mão e uma sessão respondida, para que
os números sejam plausíveis em vez de zerados.

| Arquivo | Tela | O que observar |
|---|---|---|
| `01-hoje.png` | Hoje | A manchete é memória acumulada, não contagem de cards. Barra inferior com quatro destinos. |
| `02-biblioteca.png` | Biblioteca | Lista de baralhos, botão flutuante, busca e configurações na barra. |
| `03-dispositivo.png` | Dispositivo | Estado do terminal pareado. Ícone de sincronização na barra. |
| `04-progresso.png` | Progresso | Retenção, dias seguidos, previsão de 14 dias, mapa de calor, maturidade por baralho. |
| `05-card-frente.png` | Revisão — frente | Card sozinho e centralizado. "1 / 2" e barra de progresso da sessão. |
| `06-card-verso-graus.png` | Revisão — verso | **Os quatro graus com o intervalo que cada um produz.** O elemento mais importante do produto. |
| `07-sessao-concluida.png` | Fim de sessão | Lidera pela memória guardada, não pelo número de cards. |
| `08-outros-modos.png` | Outros modos | O selo verde/âmbar separando o que conta do que é treino extra. |
| `09-gerenciar-baralho.png` | Gerenciar baralho | A distinção entre arquivar e apagar, explicada sob cada opção. |
| `10-editor-card.png` | Escrever card | Contadores de 120/240 e a prévia serifada "Como fica no aparelho". |
| `11-configuracoes.png` | Configurações | Meta de retenção com a consequência escrita; hora de virada do dia. |
| `12-gerar-por-topico.png` | Gerar por IA | A cota disponível no topo, antes de qualquer campo. |
| `13-capturar-material.png` | Foto ou PDF | Três origens e a promessa de que o arquivo é apagado. |

## Estados que não estão nos prints

Valem para o desenho e não aparecem porque exigem dados que a conta de teste
não tem:

- **Hoje sem cards vencendo**, com cards existindo: cartão verde-sálvia,
  "Nada vencendo agora / Sua memória segue trabalhando sozinha".
- **Hoje sem card nenhum**: "Seu primeiro card", com botão de criar. É outro
  estado, não o mesmo.
- **Editor acima do limite**: contador em terracota, borda vermelha, frase
  "N caracteres acima do limite. O card precisa caber na tela do aparelho", e
  os dois botões de salvar desabilitados.
- **Fila de aprovação da geração**: lista de cards com Descartar / Aprovar,
  contador "7 de 24", "Desfazer" em cada decisão tomada, e "Aprovar restantes"
  no rodapé.
- **Paywall**: aparece quando a geração grátis acabou. Diz primeiro o que
  continua livre — escrever cards à mão e estudar, sempre.
- **Sem conexão**: um selo discreto na barra, "3 mudanças para enviar". Nunca
  um modal, nunca vermelho.
