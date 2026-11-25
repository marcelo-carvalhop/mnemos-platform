import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { PendingGenerations } from '../../core/open-generations';

/**
 * O caminho de volta para uma geração deixada no meio (§7.8).
 *
 * A tela de progresso promete que dá para sair e voltar. Este componente é o
 * que torna a promessa verdadeira: o servidor sabe o que está pendente, e a
 * web pergunta em vez de guardar um `jobId` que some ao fechar a aba.
 *
 * Dois estados, porque são duas esperas diferentes: o servidor ainda
 * escrevendo, e os cards já escritos esperando um sim ou não. Só o segundo é
 * uma cobrança — o primeiro é informação, e é dito sem botão.
 */
@Component({
  selector: 'app-open-generations',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  styles: `
    :host {
      display: block;
    }
    a {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 16px 18px;
      border-radius: var(--mn-radius-lg);
      text-decoration: none;
      margin-bottom: 18px;
    }
    .waiting {
      background: var(--mn-ai);
      color: var(--mn-text-on-hero);
    }
    .running {
      background: color-mix(in srgb, var(--mn-line) 45%, transparent);
      color: var(--mn-text);
    }
    .failed {
      background: var(--mn-again-bg);
      color: var(--mn-again);
    }
    strong {
      display: block;
      font-size: 14.5px;
    }
    span {
      font-size: 12.5px;
      opacity: 0.78;
    }
  `,
  template: `
    @for (job of failed(); track job.id) {
      <a class="failed" [routerLink]="['/gerar', job.id]">
        <span>
          <strong>Não deu para gerar os cards</strong>
          <span>{{ job.topic ?? sourceLabel(job.source_type) }} · ver o motivo</span>
        </span>
        <span aria-hidden="true">→</span>
      </a>
    }
    @for (job of jobs(); track job.id) {
      @if (job.pending > 0) {
        <a class="waiting" [routerLink]="['/aprovar', job.id]">
          <span>
            <strong>
              {{ job.pending }} {{ job.pending === 1 ? 'card espera' : 'cards esperam' }} sua
              aprovação
            </strong>
            <span>{{ job.topic ?? job.stage }}</span>
          </span>
          <span aria-hidden="true">→</span>
        </a>
      } @else {
        <a class="running" [routerLink]="['/gerar', job.id]">
          <span>
            <strong>Gerando seus cards</strong>
            <span>{{ job.topic ?? job.stage }}</span>
          </span>
          <span aria-hidden="true">→</span>
        </a>
      }
    }
  `,
})
export class OpenGenerations {
  private readonly open = inject(PendingGenerations);

  /** O mesmo estado do atalho do cabeçalho e da barra lateral. */
  protected readonly jobs = this.open.jobs;
  protected readonly failed = this.open.failed;

  protected sourceLabel(source: string): string {
    if (source === 'pdf') return 'Do seu PDF';
    if (source === 'photo') return 'Da sua foto';
    if (source === 'text') return 'Do seu texto';
    return 'Sua geração';
  }

  constructor() {
    void this.open.refresh();
  }
}
