import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { TOPIC_MAX_CHARS } from '../../core/contract.g';
import { failureForError } from '../../core/error-copy';
import { Generation } from '../../core/generation';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';

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
 */
@Component({
  selector: 'app-create',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  styleUrl: './create.css',
  template: `
    <p class="quota mn-mono">{{ quotaLine() }}</p>

    <h1>O que você quer aprender?</h1>
    <p class="hint">Descreva o assunto. Quanto mais estreito o recorte, melhores os cards.</p>

    <textarea
      [(ngModel)]="subject"
      [maxLength]="topicMax"
      rows="3"
      autofocus
      placeholder="Ex.: Revolução Gloriosa e o parlamentarismo inglês"
      aria-label="Assunto"
    ></textarea>

    <!-- Exemplos concretos, não categorias: "História" é vago e produz cards
         vagos. Mostrar recortes ensina mais que qualquer texto de ajuda. -->
    <ul class="examples">
      @for (example of examples; track example) {
        <li>
          <button type="button" (click)="subject.set(example)">{{ example }}</button>
        </li>
      }
    </ul>

    @if (ready()) {
      <div class="refine">
        <fieldset>
          <legend>Nível</legend>
          @for (option of levels; track option.value) {
            <label [class.on]="level() === option.value">
              <input
                type="radio"
                name="level"
                [value]="option.value"
                [checked]="level() === option.value"
                (change)="level.set(option.value)"
              />
              {{ option.label }}
            </label>
          }
        </fieldset>

        <label class="count">
          <span>Quantos cards</span>
          <input type="range" min="5" max="30" step="1" [(ngModel)]="count" />
          <output class="mn-mono">{{ count() }}</output>
        </label>
      </div>
    }

    @if (problem(); as message) {
      <p class="problem" role="status">{{ message }}</p>
    }

    @if (spent()) {
      <a class="primary" routerLink="/configuracoes">Assinar para gerar</a>
    } @else {
      <button class="primary" type="button" [disabled]="!ready() || busy()" (click)="generate()">
        {{ busy() ? 'Criando…' : 'Criar com IA' }}
      </button>
    }

    <!-- O caminho grátis nunca some. Escrever à mão é livre, sempre, e uma tela
         que esconde isso quando o dinheiro entra em jogo está mentindo. -->
    <div class="alternatives">
      <button type="button" (click)="writeByHand()">Escrever eu mesmo</button>
    </div>

    <p class="foot">Nada vira card sem você aprovar, um por vez.</p>
  `,
})
export class Create {
  private readonly generation = inject(Generation);
  private readonly store = inject(Store);
  private readonly sync = inject(Sync);
  private readonly router = inject(Router);

  protected readonly topicMax = TOPIC_MAX_CHARS;

  protected readonly subject = signal('');
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

  protected readonly ready = computed(() => this.subject().trim().length > 0);
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

  protected async generate(): Promise<void> {
    const subject = this.subject().trim();
    if (subject.length === 0 || this.busy()) return;

    this.busy.set(true);
    this.problem.set(null);

    const deckId = this.store.createDeck(deckNameFrom(subject));

    // O servidor recusa gerar dentro de um baralho que não conhece (§7.3), e
    // este acabou de nascer neste navegador. Empurrar faz parte da mesma ação:
    // sem isso a pessoa vê "algo deu errado" por um detalhe de sincronização
    // que não é dela.
    await this.sync.syncNow();

    try {
      const job = await this.generation.create({
        sourceType: 'topic',
        targetDeckId: deckId,
        topic: subject,
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
          ? `${failure.title}. O baralho "${deckNameFrom(subject)}" foi criado — você pode escrever os cards à mão.`
          : `${failure.title}. ${failure.detail}`,
      );
      if (failure.showsPaywall) this.remaining.set(0);
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
