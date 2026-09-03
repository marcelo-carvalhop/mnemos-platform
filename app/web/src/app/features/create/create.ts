import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { TOPIC_MAX_CHARS } from '../../core/contract.g';
import { failureForCode, failureForError } from '../../core/error-copy';
import { Generation } from '../../core/generation';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';

/** De onde os cards podem vir. Os mesmos quatro do aplicativo. */
export type CreateSource = 'topic' | 'text' | 'pdf' | 'photo';

/** §7.2 — o teto do servidor. Descobrir depois de subir 40 MB é a pior hora. */
const MAX_UPLOAD_BYTES = 25 * 1024 * 1024;

/** §7.2 — o que `presign_upload` assina. Qualquer outro tipo volta 415. */
const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

/**
 * Criar conteúdo, começando pela IA.
 *
 * A ordem é a tese: descrever o que se quer aprender é a primeira coisa que a
 * tela pede, e escrever à mão é o caminho ao lado. Antes de o aplicativo mudar,
 * criar um baralho era um campo "Nome" — o que produzia um baralho vazio e
 * transferia todo o trabalho para a pessoa. Um nome não é conteúdo.
 *
 * **O baralho e os cards nascem juntos.** Não se escolhe um destino porque
 * ainda não existe destino: o que a pessoa descreve vira o nome do baralho e o
 * assunto da geração na mesma ação.
 *
 * A cota aparece **antes** de qualquer campo. O plano grátis é uma geração para
 * a vida da conta (§7.7.1), e uma interface que só conta isso depois de gasto
 * tirou algo que a pessoa não sabia que tinha.
 *
 * As quatro origens são as mesmas do aplicativo, e a razão é §1: as superfícies
 * são várias, mas o produto é um. Uma pessoa que mandou um PDF pelo celular e
 * abre o navegador não deve encontrar um lugar que só aceita digitar.
 */
@Component({
  selector: 'app-create',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  styleUrl: './create.css',
  template: `
    <div class="split">
      <div class="form">
        <h1>{{ heading() }}</h1>
        <p class="hint">{{ hint() }}</p>

        <!-- As origens vêm antes do campo: qual é o material decide o que a
             tela pede em seguida, e descobrir isso depois de digitar um
             parágrafo é descobrir tarde. -->
        <div class="sources" role="tablist" aria-label="De onde vêm os cards">
          @for (option of sources; track option.value) {
            <button
              type="button"
              role="tab"
              [attr.aria-selected]="source() === option.value"
              [class.on]="source() === option.value"
              (click)="choose(option.value)"
            >
              <!-- Ícone acima do rótulo, como os quatro azulejos do
                   aplicativo. Eram pílulas só de texto aqui e azulejos com
                   glifo lá: mesmo passo, mesmo produto, duas linguagens. -->
              <svg viewBox="0 0 24 24" aria-hidden="true"><path [attr.d]="option.icon" /></svg>
              <span>{{ option.label }}</span>
            </button>
          }
        </div>

        @switch (source()) {
          @case ('topic') {
            <textarea
              [(ngModel)]="subject"
              [maxLength]="topicMax"
              rows="3"
              autofocus
              placeholder="Ex.: Revolução Gloriosa e o parlamentarismo inglês"
              aria-label="Assunto"
            ></textarea>

            <!-- Exemplos concretos, não categorias: "História" é vago e produz
                 cards vagos. Mostrar recortes ensina mais que qualquer texto de
                 ajuda. -->
            <ul class="examples">
              @for (example of examples; track example) {
                <li>
                  <button type="button" (click)="subject.set(example)">{{ example }}</button>
                </li>
              }
            </ul>
          }

          @case ('text') {
            <textarea
              [(ngModel)]="material"
              [maxLength]="topicMax"
              rows="10"
              autofocus
              placeholder="Cole aqui o trecho da apostila, o resumo da aula ou as suas anotações. O Mnemos extrai os cards do que está escrito, sem inventar o que não está."
              aria-label="Texto colado"
            ></textarea>
            @if (charsLeft() !== null) {
              <p class="counter" [class.over]="charsLeft()! < 0">{{ counterLine() }}</p>
            }
          }

          @default {
            <!-- Soltar o arquivo na página é o gesto nativo do navegador, e o
                 botão continua ali para quem prefere o seletor. Um só dos dois
                 deixaria metade das pessoas sem o caminho que conhece. -->
            <label
              class="drop"
              [class.over]="dragging()"
              (dragover)="onDragOver($event)"
              (dragleave)="dragging.set(false)"
              (drop)="onDrop($event)"
            >
              <input
                type="file"
                [accept]="accept()"
                (change)="onPick($event)"
                [attr.aria-label]="source() === 'pdf' ? 'Escolher PDF' : 'Escolher foto'"
              />
              @if (file(); as chosen) {
                <span class="name">{{ chosen.name }}</span>
                <span class="size mn-mono">{{ sizeLabel(chosen.size) }}</span>
              } @else {
                <span class="name">{{
                  source() === 'pdf' ? 'Escolha um PDF' : 'Escolha uma foto do seu material'
                }}</span>
                <span class="size">
                  {{
                    source() === 'pdf'
                      ? 'Arraste o arquivo aqui, ou clique para procurar. Até 25 MB.'
                      : 'JPEG, PNG ou WebP. Arraste aqui, ou clique para procurar.'
                  }}
                </span>
              }
            </label>
          }
        }

        <div class="refine">
          <div>
            <p class="eyebrow mn-mono">Quantos cards</p>
            <div class="counts">
              @for (option of countOptions; track option) {
                <button
                  type="button"
                  [class.on]="count() === option"
                  (click)="count.set(option)"
                >
                  {{ option }}
                </button>
              }
            </div>
          </div>
          <div>
            <p class="eyebrow mn-mono">Nível</p>
            <div class="counts">
              @for (option of levels; track option.value) {
                <button
                  type="button"
                  [class.on]="level() === option.value"
                  (click)="level.set(option.value)"
                >
                  {{ option.label }}
                </button>
              }
            </div>
          </div>
        </div>

        @if (problem(); as message) {
          <p class="problem" role="status">{{ message }}</p>
        }

        <div class="actions">
          @if (spent()) {
            <a class="primary" routerLink="/configuracoes">Assinar para gerar</a>
          } @else {
            <button class="primary" type="button" [disabled]="!ready() || busy()" (click)="generate()">
              {{ busyLabel() }}
            </button>
          }
          <!-- O caminho grátis nunca some. Escrever à mão é livre, sempre, e uma
               tela que esconde isso quando o dinheiro entra em jogo está
               mentindo. -->
          <button class="secondary" type="button" (click)="writeByHand()">Escrever eu mesmo</button>
        </div>
        <p class="foot">{{ ready() ? 'Nada vira card sem você aprovar, um por vez.' : missing() }}</p>
      </div>

      <!-- A coluna da direita mostra o formato antes de gastar a geração:
           saber o que vai sair é o que faz alguém escrever um recorte melhor. -->
      <aside class="preview">
        <p class="eyebrow mn-mono">Prévia do que vai sair</p>
        <p class="quota mn-mono">{{ quotaLine() }}</p>
        <ul>
          @for (sample of samples; track sample.front) {
            <li>
              <p class="front">{{ sample.front }}</p>
              <p class="back">{{ sample.back }}</p>
            </li>
          }
        </ul>
        <p class="note">
          Exemplo do formato. Os cards reais aparecem aqui para você aprovar um por um.
        </p>
      </aside>
    </div>
  `,
})
export class Create {
  /** As quantidades do canvas — quatro escolhas em vez de um slider. */
  protected readonly countOptions = [5, 8, 12, 20];

  /**
   * As quatro origens, com o mesmo glifo que o aplicativo usa em cada uma.
   *
   * Os caminhos são traçados aqui em vez de virem de uma biblioteca de ícones:
   * são quatro, e uma dependência inteira para quatro formas é peso que a
   * página carrega em toda visita.
   */
  protected readonly sources: { value: CreateSource; label: string; icon: string }[] = [
    {
      value: 'topic',
      label: 'Tópico',
      icon: 'M12 3l1.8 4.7L18.5 9.5 13.8 11.3 12 16l-1.8-4.7L5.5 9.5l4.7-1.8L12 3zm6 10l.9 2.3 2.3.9-2.3.9-.9 2.3-.9-2.3-2.3-.9 2.3-.9.9-2.3z',
    },
    {
      value: 'text',
      label: 'Texto colado',
      icon: 'M4 6h16M4 11h16M4 16h10',
    },
    {
      value: 'pdf',
      label: 'PDF',
      icon: 'M7 3h7l5 5v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm7 0v6h5M9 13h6M9 17h4',
    },
    {
      value: 'photo',
      label: 'Foto',
      icon: 'M4 8h3l1.5-2h7L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1zm8 3.2a3.3 3.3 0 1 0 0 6.6 3.3 3.3 0 0 0 0-6.6z',
    },
  ];

  /** O formato, não o conteúdo: cards curtos, uma ideia cada. */
  protected readonly samples = [
    {
      front: 'O que o controle de congestionamento do TCP tenta evitar?',
      back: 'Que o emissor injete mais tráfego do que a rede consegue escoar.',
    },
    {
      front: 'Quando UDP é preferível a TCP?',
      back: 'Quando latência importa mais que entrega garantida.',
    },
    {
      front: 'Para que serve o handshake de três vias?',
      back: 'Sincronizar números de sequência antes da transferência.',
    },
  ];

  private readonly generation = inject(Generation);
  private readonly store = inject(Store);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  protected readonly topicMax = TOPIC_MAX_CHARS;

  protected readonly source = signal<CreateSource>('topic');
  protected readonly subject = signal('');
  protected readonly material = signal('');
  protected readonly file = signal<{ name: string; blob: File; contentType: string; size: number } | null>(
    null,
  );
  protected readonly dragging = signal(false);
  protected readonly level = signal('intermediario');
  protected readonly count = signal(12);
  protected readonly busy = signal(false);
  protected readonly problem = signal<string | null>(null);
  protected readonly remaining = signal<number | null>(null);

  protected readonly levels = [
    { value: 'basico', label: 'Básico' },
    { value: 'intermediario', label: 'Médio' },
    { value: 'avancado', label: 'Avançado' },
  ];

  protected readonly examples = [
    'Revolução Gloriosa de 1688',
    'Ciclo de Krebs',
    'Controle de constitucionalidade',
    'Present perfect em inglês',
    'Farmacologia dos beta-bloqueadores',
    'Teorema de Bayes',
  ];

  /**
   * O título muda com a origem porque a pergunta muda.
   *
   * "O que você quer aprender?" sobre um PDF já escolhido não faz sentido: o
   * assunto é o arquivo, e o que resta decidir é o formato.
   */
  protected readonly heading = computed(() =>
    ({
      topic: 'O que você quer aprender?',
      text: 'Cole o seu material',
      pdf: 'Mande o seu PDF',
      photo: 'Fotografe o seu material',
    })[this.source()],
  );

  protected readonly hint = computed(() =>
    ({
      topic: 'Descreva o assunto. Quanto mais estreito o recorte, melhores os cards.',
      text: 'Os cards saem do que está escrito aqui — o Mnemos extrai, não inventa.',
      pdf: 'Uma apostila, um artigo, um capítulo. Os cards saem do conteúdo do arquivo.',
      photo: 'Uma página do caderno ou do livro. Texto nítido e página plana lêem melhor.',
    })[this.source()],
  );

  protected readonly accept = computed(() =>
    this.source() === 'pdf' ? 'application/pdf' : PHOTO_TYPES.join(','),
  );

  protected readonly ready = computed(() => {
    switch (this.source()) {
      case 'topic':
        return this.subject().trim().length > 0;
      case 'text':
        return this.material().trim().length > 0 && this.material().length <= this.topicMax;
      default:
        return this.file() !== null;
    }
  });

  /** O que ainda falta para o botão acender — dito no lugar da frase genérica. */
  protected readonly missing = computed(() =>
    ({
      topic: 'Escreva o assunto para continuar.',
      text: 'Cole o texto para continuar.',
      pdf: 'Escolha um PDF para continuar.',
      photo: 'Escolha uma foto para continuar.',
    })[this.source()],
  );

  protected readonly busyLabel = computed(() => {
    if (!this.busy()) return `Gerar ${this.count()} cards`;
    return this.source() === 'pdf' || this.source() === 'photo' ? 'Enviando…' : 'Criando…';
  });

  /**
   * Quanto ainda cabe — só perto do teto.
   *
   * Um contador permanente sobre um limite de vinte mil é ruído: ninguém cola
   * um parágrafo e se preocupa com ele. Perto da régua o número passa a ser a
   * única informação que evita um erro do servidor.
   */
  protected readonly charsLeft = computed(() => {
    const left = this.topicMax - this.material().length;
    return left <= 2000 ? left : null;
  });

  protected readonly counterLine = computed(() => {
    const left = this.charsLeft() ?? 0;
    if (left < 0) {
      return `Passou do limite em ${-left} caracteres. Divida o material em duas gerações.`;
    }
    return `${left} caracteres restantes.`;
  });

  protected readonly spent = computed(() => this.remaining() === 0);

  protected readonly quotaLine = computed(() => {
    const left = this.remaining();
    // Offline a resposta honesta é "não sei", e o app não pode chutar a favor
    // nem contra a pessoa.
    if (left === null || left < 0) return 'Verificando sua cota…';
    if (left === 0) return 'Sua geração grátis já foi usada';
    return left === 1 ? '1 geração grátis disponível' : `${left} gerações disponíveis`;
  });

  constructor() {
    void this.loadQuota();
  }

  private async loadQuota(): Promise<void> {
    try {
      this.remaining.set((await this.generation.quota()).remaining);
    } catch {
      this.remaining.set(-1);
    }
  }

  protected choose(source: CreateSource): void {
    if (source === this.source()) return;
    this.source.set(source);
    this.problem.set(null);
    // O arquivo escolhido não sobrevive à troca de origem: um PDF pendurado
    // enquanto a tela mostra "Foto" é a mesma contradição de sempre — a tela
    // dizendo uma coisa e o botão fazendo outra.
    this.file.set(null);
  }

  protected onDragOver(event: DragEvent): void {
    event.preventDefault();
    this.dragging.set(true);
  }

  protected onDrop(event: DragEvent): void {
    event.preventDefault();
    this.dragging.set(false);
    const dropped = event.dataTransfer?.files?.[0];
    if (dropped) this.accept_(dropped);
  }

  protected onPick(event: Event): void {
    const picked = (event.target as HTMLInputElement).files?.[0];
    if (picked) this.accept_(picked);
  }

  /**
   * Aceita o arquivo, ou explica por que não.
   *
   * As duas recusas acontecem aqui e não no servidor de propósito: tamanho e
   * tipo são verificáveis no navegador, e subir 40 MB para ouvir "grande
   * demais" gasta o tempo de quem mandou.
   */
  private accept_(file: File): void {
    const wanted = this.source() === 'pdf' ? ['application/pdf'] : PHOTO_TYPES;
    // Alguns sistemas entregam um PDF sem `type`; o sufixo decide então.
    const type = file.type || (file.name.toLowerCase().endsWith('.pdf') ? 'application/pdf' : '');

    if (!wanted.includes(type)) {
      this.file.set(null);
      this.problem.set(
        this.source() === 'pdf'
          ? 'Esse arquivo não é um PDF. Escolha um .pdf, ou use a origem Foto.'
          : 'Formato de imagem não aceito. Use JPEG, PNG ou WebP.',
      );
      return;
    }

    if (file.size > MAX_UPLOAD_BYTES) {
      const failure = failureForCode('file_too_large');
      this.file.set(null);
      this.problem.set(`${failure.title}. ${failure.detail}`);
      return;
    }

    this.problem.set(null);
    this.file.set({ name: file.name, blob: file, contentType: type, size: file.size });
  }

  protected sizeLabel(bytes: number): string {
    const mb = bytes / (1024 * 1024);
    return mb >= 1 ? `${mb.toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
  }

  protected async generate(): Promise<void> {
    if (!this.ready() || this.busy()) return;

    this.busy.set(true);
    this.problem.set(null);

    const chosen = this.file();
    let uploadKey: string | undefined;

    // O arquivo sobe **antes** de o baralho nascer. Na ordem inversa, um 415 ou
    // uma queda no meio do upload deixaria para trás um baralho vazio que a
    // pessoa não pediu.
    if (chosen) {
      try {
        const target = await this.generation.createUpload(chosen.contentType);
        await this.generation.upload(target.url, chosen.blob, chosen.contentType);
        uploadKey = target.upload_key;
      } catch (e) {
        this.busy.set(false);
        const failure = failureForError(e);
        this.problem.set(`${failure.title}. ${failure.detail}`);
        return;
      }
    }

    const name = this.deckName();
    const deckId = this.store.createDeck(name);

    // O servidor recusa gerar dentro de um baralho que não conhece (§7.3), e
    // este acabou de nascer neste navegador. Empurrar faz parte da mesma ação:
    // sem isso a pessoa vê "algo deu errado" por um detalhe de sincronização
    // que não é dela.
    await this.sync.syncNow();

    try {
      const job = await this.generation.create({
        sourceType: this.source(),
        targetDeckId: deckId,
        // §7.3 — o material colado viaja no mesmo campo do assunto; o que muda
        // o comportamento do servidor é o `source_type`.
        topic: this.source() === 'text' ? this.material().trim() : this.textTopic(),
        uploadKey,
        requestedCount: this.count(),
        level: this.level(),
      });
      await this.router.navigate(['/gerar', job.id], { queryParams: { deck: deckId } });
    } catch (e) {
      this.busy.set(false);
      const failure = failureForError(e);
      // O baralho **fica**. Apagar o trabalho de alguém porque o servidor disse
      // 402 seria punir a pessoa por uma decisão comercial nossa, e escrever
      // cards à mão nele continua livre.
      this.problem.set(
        failure.showsPaywall
          ? `${failure.title}. O baralho "${name}" foi criado — você pode escrever os cards à mão.`
          : `${failure.title}. ${failure.detail}`,
      );
      if (failure.showsPaywall) this.remaining.set(0);
    }
  }

  /** Só as origens de texto mandam `topic`; PDF e foto mandam a chave do upload. */
  private textTopic(): string | undefined {
    return this.source() === 'topic' ? this.subject().trim() : undefined;
  }

  /**
   * O nome do baralho, sem perguntar duas vezes.
   *
   * Cada origem já disse do que trata: o assunto digitado, as primeiras
   * palavras do texto colado, o nome do arquivo. Um campo "Nome do baralho"
   * aqui seria pedir de novo o que a pessoa acabou de dar.
   */
  private deckName(): string {
    switch (this.source()) {
      case 'topic':
        return deckNameFrom(this.subject());
      case 'text':
        return deckNameFrom(this.material());
      default: {
        const name = this.file()?.name ?? '';
        const withoutExtension = name.replace(/\.[^.]+$/, '');
        return deckNameFrom(withoutExtension) || 'Novo baralho';
      }
    }
  }

  protected async writeByHand(): Promise<void> {
    const subject = this.subject().trim();
    const id = this.store.createDeck(subject.length > 0 ? deckNameFrom(subject) : 'Novo baralho');
    await this.sync.syncNow();
    await this.router.navigate(['/biblioteca', id]);
  }
}

/**
 * O nome do baralho sai do que a pessoa escreveu, sem perguntar duas vezes.
 *
 * Espaço em branco vira um espaço só: o campo aceita várias linhas, e um `\n`
 * no meio do nome quebraria a lista da biblioteca, que reserva uma linha por
 * baralho. O corte é em palavra, nunca no meio de uma.
 */
export function deckNameFrom(subject: string): string {
  const trimmed = subject.replace(/\s+/g, ' ').trim();
  if (trimmed.length <= 42) return trimmed;
  const cut = trimmed.slice(0, 42);
  const lastSpace = cut.lastIndexOf(' ');
  return `${lastSpace > 20 ? cut.slice(0, lastSpace) : cut}…`;
}
