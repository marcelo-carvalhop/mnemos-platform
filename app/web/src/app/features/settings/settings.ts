import { HttpClient } from '@angular/common/http';
import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { API_BASE_URL } from '../../core/config';
import { DESIRED_RETENTION } from '../../core/contract.g';
import { Generation } from '../../core/generation';
import { Session } from '../../core/session';
import { Store } from '../../core/store';
import { Sync } from '../../core/sync';

/**
 * Configurações, assinatura e os dados da pessoa (§5.4, §5.15).
 *
 * A retenção desejada mora em `user_settings` e não no navegador porque é
 * **entrada da fórmula de intervalo** (§3.1): local, ela faria dois aparelhos
 * calcularem vencimentos diferentes do mesmo histórico.
 *
 * Exportar e apagar ficam aqui, juntos e sem cerimônia. Um produto que guarda
 * anos de estudo de alguém deve a essa pessoa uma porta de saída que não passe
 * por suporte.
 */
@Component({
  selector: 'app-settings',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './settings.css',
  template: `
    <h1>Configurações</h1>

    <section>
      <h2>Assinatura</h2>
      <p class="quiet">{{ planLine() }}</p>
      <p class="note">
        Estudar, escrever cards à mão e sincronizar são livres, sempre. A assinatura cobre a geração
        por IA, que custa por uso.
      </p>
    </section>

    <section>
      <h2>Agendamento</h2>
      <label class="field">
        <span>Retenção desejada</span>
        <input
          type="range"
          min="0.80"
          max="0.97"
          step="0.01"
          [value]="retention()"
          (input)="onRetention($event)"
        />
        <output class="mn-mono">{{ (retention() * 100).toFixed(0) }}%</output>
      </label>
      <!-- Um número que muda o cronograma inteiro merece dizer o que faz. -->
      <p class="note">
        A probabilidade de você lembrar de um card no momento em que ele vence. Mais alto significa
        revisar mais vezes e esquecer menos; mais baixo, o contrário. O padrão é
        {{ (defaultRetention * 100).toFixed(0) }}%.
      </p>
    </section>

    <!-- O aplicativo expõe também cards novos por dia, revisões por dia, a
         hora em que o dia vira, o fuso e os lembretes. Quem configurou pelo
         celular e não acha aqui precisa saber que o ajuste existe e onde ele
         mora — silêncio faria a pessoa procurar um botão que não está aqui. -->
    <section>
      <h2>No aplicativo</h2>
      <p class="note">
        O limite de cards novos e de revisões por dia, a hora em que o dia vira, o fuso horário e o
        lembrete diário ficam no aplicativo. São ajustes de rotina, e a rotina acontece no telefone
        — o navegador respeita os que você definiu lá.
      </p>
    </section>

    <section>
      <h2>Seus dados</h2>
      <div class="row">
        <button type="button" (click)="exportData()">Exportar tudo</button>
        <button class="danger" type="button" (click)="deleteAccount()">Apagar a conta</button>
      </div>
      <p class="note">
        A exportação traz baralhos, cards e o histórico completo de revisões em JSON. Apagar é
        imediato e não tem volta.
      </p>
      @if (message(); as text) {
        <p class="status" role="status">{{ text }}</p>
      }
    </section>
  `,
})
export class Settings {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = inject(API_BASE_URL);
  private readonly store = inject(Store);
  private readonly sync = inject(Sync);
  private readonly session = inject(Session);
  private readonly generation = inject(Generation);
  private readonly router = inject(Router);

  protected readonly defaultRetention = DESIRED_RETENTION;
  protected readonly message = signal<string | null>(null);
  protected readonly plan = signal<string | null>(null);
  protected readonly remaining = signal<number | null>(null);

  protected readonly retention = computed(() => this.store.fsrsParams().desiredRetention);

  protected readonly planLine = computed(() => {
    const plan = this.plan();
    if (plan === null) return 'Verificando…';
    if (plan !== 'free') return `Plano ${plan}. Gerações liberadas.`;
    const left = this.remaining() ?? 0;
    return left > 0
      ? `Plano grátis · ${left} ${left === 1 ? 'geração disponível' : 'gerações disponíveis'}`
      : 'Plano grátis · sua geração já foi usada';
  });

  constructor() {
    void this.loadQuota();
  }

  private async loadQuota(): Promise<void> {
    try {
      const quota = await this.generation.quota();
      this.plan.set(quota.plan);
      this.remaining.set(quota.remaining);
    } catch {
      this.plan.set(null);
    }
  }

  protected onRetention(event: Event): void {
    const value = Number((event.target as HTMLInputElement).value);
    if (!Number.isFinite(value)) return;
    this.store.setSetting('desired_retention', String(value));
    void this.sync.syncNow();
  }

  protected async exportData(): Promise<void> {
    this.message.set('Preparando a exportação…');
    try {
      const body = await firstValueFrom(
        this.http.get(`${this.baseUrl}/v1/account/export`, { responseType: 'blob' }),
      );
      const url = URL.createObjectURL(body);
      const link = document.createElement('a');
      link.href = url;
      link.download = `mnemos-${new Date().toISOString().slice(0, 10)}.json`;
      link.click();
      URL.revokeObjectURL(url);
      this.message.set('Exportação baixada.');
    } catch {
      this.message.set('Não consegui exportar agora. Tente de novo.');
    }
  }

  protected async deleteAccount(): Promise<void> {
    // Duas confirmações e a segunda pede o e-mail digitado: apagar anos de
    // estudo não pode ser um clique acidental.
    if (!confirm('Apagar a conta apaga baralhos, cards e todo o histórico. Isso não tem volta.')) {
      return;
    }
    if (prompt('Digite APAGAR para confirmar.') !== 'APAGAR') return;

    try {
      await firstValueFrom(this.http.post(`${this.baseUrl}/v1/account/delete`, {}));
      this.session.signOut();
      this.store.clear();
      await this.router.navigate(['/']);
    } catch {
      this.message.set('Não consegui apagar agora. Nada foi removido.');
    }
  }
}
