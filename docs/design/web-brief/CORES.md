# Cores do Mnemos

A paleta vem do aplicativo (`app/mobile/lib/theme.dart`) e é a mesma que o
firmware usa no que consegue reproduzir. Este documento é a fonte para a
interface web.

Cada cor traz o contraste medido — calculado, não estimado — porque uma paleta
calma erra com facilidade justamente onde ninguém olha: o texto secundário.

---

## As sete cores

| Nome | Hex | O que é | Onde aparece |
|---|---|---|---|
| **Marfim Calmo** | `#F4F1E8` | O fundo de tudo. Papel, não branco. | Fundo de telas, cartões, campos |
| **Grafite Profundo** | `#1F1F1F` | O texto que se lê. | Títulos, corpo, ícones ativos |
| **Azul Petróleo** | `#365462` | A cor da ação. | Botões primários, links, seleção, gráficos |
| **Sálvia Analógica** | `#7A8B72` | O texto de apoio e o "acertei". | Legendas, rótulos, estado bom |
| **Terracota Contida** | `#B56E52` | O erro e o perigo. | "Errei", apagar, falha |
| **Latão Fosco** | `#B8A27A` | O intermediário. | "Difícil", "treino extra" |
| **Cinza Névoa** | `#D9D5CC` | A linha e a separação. | Bordas, divisórias, trilhos, fundos de selo |

Não há preto puro nem branco puro. É deliberado: o produto tem um terminal de
tinta eletrônica, e a interface na tela combina com o objeto na mesa.

---

## Contraste — três correções obrigatórias para a web

Medido em WCAG 2.1. O app usa hoje os valores de origem; **a web deve usar as
variantes corrigidas** para texto, e reservar as originais para superfícies
grandes onde contraste de texto não se aplica.

| Uso | Cor de origem | Contraste | Situação | Usar na web |
|---|---|---|---|---|
| Texto principal sobre marfim | `#1F1F1F` | **14,59:1** | AAA | manter |
| Ação sobre marfim | `#365462` | **7,15:1** | AAA | manter |
| Marfim sobre ação | `#F4F1E8` | **7,15:1** | AAA | manter |
| Texto secundário sobre marfim | `#7A8B72` | 3,23:1 | **reprova AA** | **`#535F4E`** → 5,97:1 |
| Texto secundário sobre névoa | `#7A8B72` | 2,49:1 | **reprova AA** | **`#535F4E`** → 4,60:1 |
| Selo "treino extra" | `#B8A27A` | 2,19:1 | **reprova AA** | **`#806B44`** → 4,53:1 |
| Erro em texto | `#B56E52` | 3,50:1 | AA só em texto grande | **`#9E5D44`** → 4,53:1 |
| Bordas e trilhos | `#D9D5CC` | 1,30:1 | correto — não é texto | manter |

As três variantes escurecidas foram derivadas por luminosidade, mantendo matiz
e saturação: são a mesma cor, não uma cor nova. Lado a lado com as originais
elas leem como a mesma família.

**Regra prática:** `#7A8B72`, `#B8A27A` e `#B56E52` podem preencher áreas —
fundos de selo, ícones grandes, barras. Assim que virarem texto abaixo de 18px,
troque pela variante escura.

---

## Tokens sugeridos para a web

```css
:root {
  /* Superfícies */
  --mn-surface:        #F4F1E8;  /* fundo geral */
  --mn-surface-sunken: #EDE9DE;  /* cartão sobre fundo, 4% mais escuro */
  --mn-surface-raised: #FBFAF6;  /* prévia de card, quase branco */
  --mn-line:           #D9D5CC;  /* bordas, divisórias */

  /* Texto */
  --mn-text:           #1F1F1F;
  --mn-text-muted:     #535F4E;  /* sálvia escurecida — AA */
  --mn-text-on-accent: #F4F1E8;

  /* Ação */
  --mn-accent:         #365462;
  --mn-accent-hover:   #2B4450;
  --mn-accent-soft:    #E4E8E6;  /* fundo de estado selecionado */

  /* Semântica de revisão — a mesma ordem dos quatro botões */
  --mn-again:          #9E5D44;  /* errei */
  --mn-again-bg:       #F3E7E2;
  --mn-hard:           #806B44;  /* difícil */
  --mn-hard-bg:        #F1EBDE;
  --mn-good:           #535F4E;  /* bom */
  --mn-good-bg:        #E7EAE4;
  --mn-easy:           #365462;  /* fácil */
  --mn-easy-bg:        #E2E8EB;
}
```

Os fundos `-bg` são versões a ~92% de luminosidade da cor correspondente. No
app eles são todos `mist`, o que funciona num telefone mas achata a leitura numa
tela grande, onde os quatro botões aparecem lado a lado com folga.

---

## Modo escuro

O app não tem, e a web também não precisa ter no primeiro momento. Se for
feito, inverta as superfícies e **mantenha as matizes**: petróleo e sálvia
sobre grafite continuam legíveis; terracota e latão precisam clarear.

Sugestão de partida, não verificada em uso real:

```css
--mn-surface: #1A1A1A;  --mn-surface-sunken: #232323;
--mn-line: #383838;     --mn-text: #EDEAE1;
--mn-text-muted: #9DAA96;  --mn-accent: #6C93A5;
```

---

## Tipografia

O app usa a fonte do sistema. Para a web, uma serifada humanista para o texto
dos cards e uma sem serifa para a interface — o card é conteúdo para ler, a
interface é controle para operar, e a distinção ajuda mais que qualquer
ornamento.

A prévia "Como fica no aparelho", no editor de cards, já usa serifada por esse
motivo: ela imita o terminal de tinta eletrônica.

---

## O que a cor precisa comunicar

Duas distinções carregam significado e não podem ser decorativas:

1. **Os quatro graus de revisão** têm ordem: errei → difícil → bom → fácil.
   Terracota, latão, sálvia, petróleo. A ordem é sempre a mesma, em qualquer
   superfície, e nunca é alfabética nem por frequência.

2. **"Conta para o agendamento" contra "treino extra".** Verde-sálvia para o
   que entra no cronograma, latão para o que não entra. Aparece em todos os
   modos alternativos. Sem isso, alguém treina achando que adiantou trabalho e
   distorce o próprio cronograma.

Nenhuma das duas pode depender só de cor: ambas vêm acompanhadas de rótulo em
texto no app, e devem vir na web também.
