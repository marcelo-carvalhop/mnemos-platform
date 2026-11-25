import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { Offline } from '../../core/api';
import { Session } from '../../core/session';

interface SampleCard {
  deck: string;
  front: string;
  back: string;
}

type Surface = 'phone' | 'web' | 'ink';

/**
 * A landing — uma tela que o aplicativo não tem.
 *
 * Quem chega aqui não sabe o que é repetição espaçada e não deveria precisar
 * saber para entender a promessa. Por isso o texto fala do resultado — o que
 * você aprendeu volta na hora certa — e não do algoritmo.
 *
 * O card do herói funciona de verdade (virar e responder), porque mostrar o
 * gesto ensina mais que qualquer frase sobre ele. Os textos dos botões seguem
 * o servidor: num servidor só para convidados eles falam de convite.
 */
@Component({
  selector: 'app-landing',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, RouterLink],
  styleUrl: './landing.css',
  templateUrl: './landing.html',
})
export class Landing {
  private readonly session = inject(Session);

  protected readonly cards: readonly SampleCard[] = [
    {
      deck: 'Direito Constitucional',
      front: 'Qual é o quórum para aprovar uma emenda à Constituição?',
      back: 'Três quintos dos votos, em dois turnos, em cada Casa do Congresso (art. 60, § 2º).',
    },
    {
      deck: 'Geografia',
      front: 'Por que existem as estações do ano?',
      back: 'Pela inclinação do eixo da Terra, que muda o ângulo com que o Sol chega a cada hemisfério.',
    },
    {
      deck: 'Bioquímica',
      front: 'Qual organela produz a maior parte do ATP da célula?',
      back: 'A mitocôndria, pela fosforilação oxidativa na membrana interna.',
    },
  ];

  protected readonly grades = [
    { label: 'Errei', interval: '10 min', tone: 'again' },
    { label: 'Difícil', interval: '2 d', tone: 'hard' },
    { label: 'Bom', interval: '5 d', tone: 'good' },
    { label: 'Fácil', interval: '12 d', tone: 'easy' },
  ] as const;

  private readonly index = signal(0);
  protected readonly shown = signal(false);
  protected readonly card = computed(() => this.cards[this.index() % this.cards.length]);
  protected readonly position = computed(() => (this.index() % this.cards.length) + 1);

  protected readonly surface = signal<Surface>('phone');

  /** Na dúvida, fala de convite: é o modo do beta. */
  protected readonly inviteOnly = signal(true);

  protected readonly ctaShort = computed(() =>
    this.inviteOnly() ? 'Tenho um convite' : 'Criar conta',
  );
  protected readonly ctaLong = computed(() =>
    this.inviteOnly() ? 'Entrar com meu convite' : 'Testar um mês grátis',
  );
  /** Quem chega pelo convite cai direto em criar conta, com o ingresso do beta. */
  protected readonly ctaQuery = computed(() => (this.inviteOnly() ? { convite: 1 } : {}));

  /** O plano com IA ainda não se compra: dá para pedir aviso. */
  protected readonly waitEmail = signal('');
  protected readonly waitState = signal<'idle' | 'busy' | 'done' | 'error'>('idle');
  protected readonly waitProblem = signal('');

  constructor() {
    this.session
      .options()
      .then((o) => this.inviteOnly.set(o.invite_required))
      .catch(() => undefined);
  }

  protected async notifyMe(event: Event): Promise<void> {
    event.preventDefault();
    const email = this.waitEmail().trim();
    if (!email.includes('@') || this.waitState() === 'busy') return;
    this.waitState.set('busy');
    try {
      await this.session.joinWaitlist(email);
      this.waitState.set('done');
    } catch (e) {
      this.waitProblem.set(
        e instanceof Offline
          ? 'Sem conexão com o servidor. Tente de novo.'
          : 'Confira o e-mail e tente de novo.',
      );
      this.waitState.set('error');
    }
  }

  protected reveal(): void {
    this.shown.set(true);
  }

  protected grade(): void {
    this.index.update((i) => i + 1);
    this.shown.set(false);
  }
}
