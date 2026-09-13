import {
  ChangeDetectionStrategy,
  Component,
  inject,
  input,
  signal,
  type OnDestroy,
  type OnInit,
} from '@angular/core';
import { Router, RouterLink } from '@angular/router';
import { Offline } from '../../core/api';
import { failureForCode, failureForError, type GenerationFailure } from '../../core/error-copy';
import { Generation } from '../../core/generation';

/**
 * A espera (§5.5).
 *
 * O spike mediu de 10 a 24 segundos, então esta tela existe tempo suficiente
 * para importar. Duas decisões vêm daí:
 *
 * * **Nomeia o estágio** em vez de animar uma barra que não sabe onde está. O
 *   servidor manda o nome ("lendo o material", "escrevendo os cards"); o
 *   cliente não inventa.
 * * **Diz que dá para sair.** Uma tela de progresso que prende alguém é o que
 *   faz vinte segundos parecerem um minuto. O trabalho continua no servidor, e
 *   Hoje traz o caminho de volta.
 */
@Component({
  selector: 'app-generating',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  styleUrl: './generating.css',
  template: `
    @if (failure(); as problem) {
      <section class="failed">
        <h1>{{ problem.title }}</h1>
        <p>{{ problem.detail }}</p>
        <a class="primary" routerLink="/criar">{{
          problem.canRetry ? 'Tentar de novo' : 'Voltar'
        }}</a>
      </section>
    } @else {
      <section class="waiting" aria-live="polite">
        <span class="pulse" aria-hidden="true"></span>
        <h1>{{ stage() }}</h1>
        <p class="hint">Costuma levar de 10 a 30 segundos.</p>

        <ol class="steps">
          @for (step of steps; track step.key; let i = $index) {
            <li [class.done]="reached() > i + 1" [class.on]="reached() === i + 1">
              <span class="dot" aria-hidden="true"></span>
              {{ step.label }}
            </li>
          }
        </ol>

        <p class="leave">
          Pode sair desta tela — o trabalho continua no servidor e os cards esperam sua aprovação.
        </p>
        <a class="secondary" routerLink="/hoje">Continuar em segundo plano</a>
      </section>
    }
  `,
})
export class Generating implements OnInit, OnDestroy {
  private readonly generation = inject(Generation);
  private readonly router = inject(Router);

  readonly jobId = input.required<string>();

  protected readonly stage = signal('na fila');
  protected readonly reached = signal(1);
  protected readonly failure = signal<GenerationFailure | null>(null);

  protected readonly steps = [
    { key: 'reading', label: 'Lendo' },
    { key: 'generating', label: 'Escrevendo' },
    { key: 'ready', label: 'Pronto' },
  ];

  private readonly order = ['queued', 'reading', 'generating', 'ready'];
  private timer: ReturnType<typeof setInterval> | null = null;
  private attempts = 0;

  /** Ver `Approval`: um input obrigatório não existe no construtor. */
  ngOnInit(): void {
    this.timer = setInterval(() => void this.tick(), 2000);
    void this.tick();
  }

  private async tick(): Promise<void> {
    this.attempts += 1;
    try {
      const job = await this.generation.get(this.jobId());
      this.stage.set(job.stage);
      this.reached.set(Math.max(1, this.order.indexOf(job.status)));

      if (job.status === 'ready') {
        this.stop();
        await this.router.navigate(['/aprovar', job.id]);
      } else if (job.status === 'failed') {
        this.stop();
        this.failure.set(failureForCode(job.error_code));
      }
    } catch (e) {
      if (e instanceof Offline) {
        // O trabalho roda no servidor, com ou sem esta aba olhando. Perder a
        // rede aqui não perde nada, então não vira erro antes de insistir.
        if (this.attempts > 15) {
          this.stop();
          this.failure.set(failureForCode('network_unavailable'));
        }
        return;
      }
      this.stop();
      this.failure.set(failureForError(e));
    }
  }

  private stop(): void {
    if (this.timer !== null) clearInterval(this.timer);
    this.timer = null;
  }

  ngOnDestroy(): void {
    this.stop();
  }
}
