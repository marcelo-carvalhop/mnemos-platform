import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  input,
  output,
  signal,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import type { Briefing } from '../../core/generation';

/** Teto de páginas de uma geração — o mesmo de `pdf.MAX_GENERATION_PAGES`. */
export const MAX_GENERATION_PAGES = 100;

/** O que a conversa decidiu até agora; a tela Criar gera a partir disto. */
export interface BriefingChoice {
  /** A instrução final: o foco da IA, as respostas e a observação. */
  focus: string;
  /** Páginas escolhidas (1 a N, inclusivas). Vazio é o arquivo inteiro. */
  ranges: [number, number][];
  /** Respostas às perguntas, para a segunda rodada. */
  answers: { question: string; answer: string }[];
  note: string;
  /** Mais páginas do que uma geração lê: o botão de gerar espera. */
  tooManyPages: boolean;
}

/**
 * A conversa antes de gerar a partir de um PDF ou de uma foto.
 *
 * Um campo "o que é importante?" solto embaixo do arquivo pede que a pessoa
 * adivinhe o que dizer. Aqui a IA fala primeiro: diz o que o material é,
 * mostra as partes do PDF para tocar e faz até três perguntas com respostas
 * prontas. O que sai disso é uma instrução legível, "o que vou gerar", que a
 * pessoa confere e pode editar antes de gastar a geração.
 *
 * O componente só conversa; quem sobe o arquivo, pede o briefing e gera é a
 * tela Criar (`create.ts`).
 */
@Component({
  selector: 'app-briefing',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule],
  styleUrl: './briefing.css',
  template: `
    <section class="talk" [class.thinking]="thinking()" aria-live="polite">
      <div class="msg">
        <span class="avatar" aria-hidden="true"></span>
        <div class="bubble">
          <p class="who mn-mono">Mnemos IA</p>
          <p>{{ brief().summary }}</p>
        </div>
      </div>

      @if (brief().sections.length > 0) {
        <div class="ask">
          <p>
            Quais partes entram?
            <span class="aside">Sem marcar nada, uso {{ wholeLabel() }}.</span>
          </p>
          <div class="chips" role="group" aria-label="Partes do PDF">
            @for (section of brief().sections; track section.title; let i = $index) {
              <button
                type="button"
                class="chip"
                [class.on]="picked().has(i)"
                [attr.aria-pressed]="picked().has(i)"
                (click)="toggleSection(i)"
              >
                {{ section.title }}
                <span class="pages mn-mono">{{ pagesOf(section.from_page, section.to_page) }}</span>
              </button>
            }
          </div>
        </div>
      }

      @for (question of brief().questions; track question.id) {
        <div class="ask">
          <p>{{ question.text }}</p>
          <div class="chips" role="group" [attr.aria-label]="question.text">
            @for (option of question.options; track option) {
              <button
                type="button"
                class="chip"
                [class.on]="isChosen(question.id, option)"
                [attr.aria-pressed]="isChosen(question.id, option)"
                (click)="choose(question.id, option, question.multiple)"
              >
                {{ option }}
              </button>
            }
            <button
              type="button"
              class="chip other"
              [class.on]="otherOpen().has(question.id)"
              (click)="toggleOther(question.id)"
            >
              Outra coisa…
            </button>
          </div>
          @if (otherOpen().has(question.id)) {
            <input
              class="other-input"
              type="text"
              maxlength="300"
              placeholder="Escreva com as suas palavras"
              [attr.aria-label]="question.text"
              [ngModel]="others()[question.id] ?? ''"
              (ngModelChange)="setOther(question.id, $event)"
            />
          }
        </div>
      }

      <label class="note">
        <span>Quer acrescentar algo? <span class="aside">Opcional.</span></span>
        <textarea
          rows="2"
          maxlength="1000"
          [placeholder]="notePlaceholder()"
          [ngModel]="note()"
          (ngModelChange)="note.set($event)"
        ></textarea>
      </label>

      <div class="plan">
        <div class="plan-head">
          <p class="eyebrow mn-mono">O que vou gerar</p>
          <button type="button" class="link" (click)="toggleEdit()">
            {{ editing() ? 'Usar o texto sugerido' : 'Editar' }}
          </button>
        </div>
        @if (editing()) {
          <textarea
            class="plan-edit"
            rows="5"
            maxlength="2000"
            aria-label="Instrução para gerar os cards"
            [ngModel]="custom()"
            (ngModelChange)="custom.set($event)"
          ></textarea>
        } @else {
          <p class="plan-text">{{ composed() }}</p>
        }
        @if (brief().page_count; as total) {
          <p class="scope mn-mono" [class.warn]="tooManyPages()">{{ scopeLine() }}</p>
        }
      </div>

      @if (canRefine()) {
        <button
          type="button"
          class="refine"
          [disabled]="thinking() || !answered()"
          (click)="askAgain()"
        >
          {{ thinking() ? 'Ajustando…' : 'Responder e ajustar' }}
        </button>
      }
    </section>
  `,
})
export class BriefingTalk {
  readonly brief = input.required<Briefing>();
  /** Rodada atual: na 2ª não há mais "ajustar". */
  readonly round = input(1);
  /** A IA está relendo (segunda rodada). */
  readonly thinking = input(false);
  readonly source = input<'pdf' | 'photo'>('pdf');

  readonly changed = output<BriefingChoice>();
  readonly refine = output<BriefingChoice>();

  protected readonly picked = signal<Set<number>>(new Set());
  protected readonly chosen = signal<Record<string, string[]>>({});
  protected readonly others = signal<Record<string, string>>({});
  protected readonly otherOpen = signal<Set<string>>(new Set());
  protected readonly note = signal('');
  protected readonly editing = signal(false);
  protected readonly custom = signal('');

  protected readonly canRefine = computed(
    () => this.round() < 2 && this.brief().questions.length > 0,
  );

  protected readonly answers = computed(() => {
    const chosen = this.chosen();
    const others = this.others();
    const out: { question: string; answer: string }[] = [];
    for (const question of this.brief().questions) {
      const parts = [...(chosen[question.id] ?? [])];
      const other = (others[question.id] ?? '').trim();
      if (other && this.otherOpen().has(question.id)) parts.push(other);
      if (parts.length) out.push({ question: question.text, answer: parts.join(', ') });
    }
    return out;
  });

  protected readonly answered = computed(
    () => this.answers().length > 0 || this.note().trim().length > 0,
  );

  protected readonly ranges = computed<[number, number][]>(() =>
    [...this.picked()]
      .sort((a, b) => a - b)
      .map((i) => this.brief().sections[i])
      .filter((s) => !!s)
      .map((s) => [s.from_page, s.to_page] as [number, number]),
  );

  /** Quantas páginas a geração vai ler, com as partes já fundidas. */
  protected readonly pagesToRead = computed(() => {
    const total = this.brief().page_count ?? 0;
    const ranges = this.ranges();
    if (!ranges.length) return total;
    const pages = new Set<number>();
    for (const [from, to] of ranges) for (let p = from; p <= to; p++) pages.add(p);
    return pages.size;
  });

  protected readonly tooManyPages = computed(() => this.pagesToRead() > MAX_GENERATION_PAGES);

  /**
   * A instrução final, legível: o foco que a IA propôs mais o que a pessoa
   * respondeu e acrescentou. Respostas ainda não "ajustadas" entram aqui
   * mesmo assim — gerar sem passar pela 2ª rodada não pode perdê-las.
   */
  protected readonly composed = computed(() => {
    const lines = [this.brief().focus.trim()];
    const parts = this.ranges();
    if (parts.length) {
      const titles = [...this.picked()]
        .sort((a, b) => a - b)
        .map((i) => this.brief().sections[i]?.title)
        .filter(Boolean);
      lines.push(`Partes escolhidas: ${titles.join('; ')}.`);
    }
    for (const item of this.answers()) lines.push(`${item.question} ${item.answer}.`);
    const note = this.note().trim();
    if (note) lines.push(note);
    return lines.filter(Boolean).join('\n');
  });

  protected readonly wholeLabel = computed(() => {
    const total = this.brief().page_count;
    return total ? `o arquivo inteiro (${total} páginas)` : 'o arquivo inteiro';
  });

  protected readonly scopeLine = computed(() => {
    const total = this.brief().page_count ?? 0;
    const reading = this.pagesToRead();
    if (this.tooManyPages()) {
      return `Escolha as partes: gero a partir de até ${MAX_GENERATION_PAGES} páginas por vez (agora: ${reading} de ${total}).`;
    }
    return this.ranges().length
      ? `Lendo ${reading} de ${total} páginas.`
      : `Lendo o arquivo inteiro: ${total} páginas.`;
  });

  protected readonly notePlaceholder = computed(() =>
    this.source() === 'pdf'
      ? 'Ex.: a prova é dia 12; o professor cobra muito os prazos.'
      : 'Ex.: é a matéria da última aula; foque nas fórmulas.',
  );

  constructor() {
    // Uma resposta nova da IA (2ª rodada) já incorporou as respostas: elas
    // saem da tela, e as partes marcadas ficam, pelo título.
    let previous: Briefing | null = null;
    effect(() => {
      const next = this.brief();
      if (previous && previous !== next) {
        const keep = new Set(
          [...this.picked()].map((i) => previous!.sections[i]?.title).filter(Boolean),
        );
        this.picked.set(
          new Set(next.sections.map((s, i) => (keep.has(s.title) ? i : -1)).filter((i) => i >= 0)),
        );
        this.chosen.set({});
        this.others.set({});
        this.otherOpen.set(new Set());
        this.note.set('');
        this.editing.set(false);
      }
      previous = next;
    });

    effect(() => this.changed.emit(this.choice()));
  }

  private choice(): BriefingChoice {
    return {
      focus: this.editing() ? this.custom().trim() : this.composed(),
      ranges: this.ranges(),
      answers: this.answers(),
      note: this.note().trim(),
      tooManyPages: this.tooManyPages(),
    };
  }

  protected pagesOf(from: number, to: number): string {
    return from === to ? `p. ${from}` : `p. ${from}–${to}`;
  }

  protected toggleSection(index: number): void {
    const next = new Set(this.picked());
    if (next.has(index)) next.delete(index);
    else next.add(index);
    this.picked.set(next);
  }

  protected isChosen(id: string, option: string): boolean {
    return (this.chosen()[id] ?? []).includes(option);
  }

  protected choose(id: string, option: string, multiple: boolean): void {
    const current = this.chosen()[id] ?? [];
    let next: string[];
    if (current.includes(option)) next = current.filter((o) => o !== option);
    else next = multiple ? [...current, option] : [option];
    this.chosen.set({ ...this.chosen(), [id]: next });
  }

  protected toggleOther(id: string): void {
    const next = new Set(this.otherOpen());
    if (next.has(id)) next.delete(id);
    else next.add(id);
    this.otherOpen.set(next);
  }

  protected setOther(id: string, value: string): void {
    this.others.set({ ...this.others(), [id]: value });
  }

  protected toggleEdit(): void {
    if (!this.editing()) this.custom.set(this.composed());
    this.editing.set(!this.editing());
  }

  protected askAgain(): void {
    this.refine.emit(this.choice());
  }
}
