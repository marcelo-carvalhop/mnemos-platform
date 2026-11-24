import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  afterRenderEffect,
  computed,
  effect,
  inject,
  input,
  model,
  signal,
  untracked,
  viewChild,
} from '@angular/core';
import {
  CHAT_MAX_CHARS,
  Chat,
  chatFailure,
  threadKey,
  type ChatContext,
  type ChatFailure,
  type ChatMessage,
} from '../../core/chat';

/**
 * Tirar dúvidas com a IA — de Hoje, ou sobre o card na tela.
 *
 * O componente traz o próprio botão: onde ele é posto é onde a entrada
 * aparece, e o painel em si vive na camada de cima (`<dialog>` modal), longe
 * da barra de abas. Na largura de mesa é uma gaveta à direita; no celular,
 * uma folha que sobe até quase o topo.
 *
 * O gradiente da IA marca só a entrada e a identidade do painel (§design 4).
 * Dentro, a conversa é texto: a resposta é para ler, não para enfeitar.
 */
@Component({
  selector: 'app-chat-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  styleUrl: './chat-panel.css',
  template: `
    <button class="trigger" type="button" (click)="open.set(true)" aria-haspopup="dialog">
      <span class="mark" aria-hidden="true"
        ><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
          <path
            d="M12 2c.6 4.8 3.2 7.4 8 8-4.8.6-7.4 3.2-8 8-.6-4.8-3.2-7.4-8-8 4.8-.6 7.4-3.2 8-8z"
          /></svg
      ></span>
      {{ label() }}
    </button>

    <dialog
      #dialog
      class="panel"
      aria-labelledby="chat-title"
      (close)="open.set(false)"
      (keydown.escape)="dismiss($event)"
      (click)="onBackdrop($event)"
    >
      <!-- O foco entra no corpo, não no primeiro botão: o "Fechar" abria com
           o anel de foco, como se tivesse sido escolhido. -->
      <div class="body" tabindex="-1" autofocus>
        <header class="head">
          <span class="mark big" aria-hidden="true"
            ><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
              <path
                d="M12 2c.6 4.8 3.2 7.4 8 8-4.8.6-7.4 3.2-8 8-.6-4.8-3.2-7.4-8-8 4.8-.6 7.4-3.2 8-8z"
              /></svg
          ></span>
          <div class="titles">
            <h2 id="chat-title">Pergunte à IA</h2>
            <p class="sub">{{ subtitle() }}</p>
          </div>
          <button class="close" type="button" (click)="open.set(false)" aria-label="Fechar">
            <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none">
              <path
                d="M6 6l12 12M18 6L6 18"
                stroke="currentColor"
                stroke-width="1.8"
                stroke-linecap="round"
              />
            </svg>
          </button>
        </header>

        <div class="log" #log aria-live="polite">
          @if (thread().length === 0) {
            <p class="intro">{{ intro() }}</p>
          }
          @for (message of thread(); track $index) {
            <p class="msg" [class.mine]="message.role === 'user'">{{ message.content }}</p>
          }
          @if (pending()) {
            <p class="msg typing" role="status">
              <span></span><span></span><span></span>
              <span class="sr">A IA está escrevendo</span>
            </p>
          }
          @if (failure(); as f) {
            <div class="problem" role="alert">
              <p>{{ f.message }}</p>
              @if (f.canRetry) {
                <button type="button" (click)="retry()">Tentar de novo</button>
              }
            </div>
          }
        </div>

        <div class="chips" role="group" aria-label="Sugestões">
          @for (chip of visibleChips(); track chip) {
            <button type="button" (click)="send(chip)" [disabled]="pending()">{{ chip }}</button>
          }
        </div>

        <form class="composer" (submit)="submit($event)">
          <textarea
            #field
            rows="1"
            [maxLength]="maxChars"
            [value]="draft()"
            (input)="draft.set(field.value)"
            (keydown)="onComposerKey($event)"
            placeholder="Escreva sua dúvida"
            aria-label="Sua pergunta"
          ></textarea>
          <button class="send" type="submit" [disabled]="!canSend()" aria-label="Enviar">
            <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none">
              <path
                d="M12 19V5M6 11l6-6 6 6"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </button>
        </form>
        <p class="disclaimer">A IA pode errar. Confira o que for importante.</p>
      </div>
    </dialog>
  `,
})
export class ChatPanel {
  private readonly chat = inject(Chat);

  readonly context = input.required<ChatContext>();
  readonly label = input('Tirar dúvidas com IA');
  readonly open = model(false);

  protected readonly maxChars = CHAT_MAX_CHARS;
  protected readonly draft = signal('');
  protected readonly pending = signal(false);
  protected readonly failure = signal<ChatFailure | null>(null);

  private readonly dialog = viewChild.required<ElementRef<HTMLDialogElement>>('dialog');
  private readonly log = viewChild.required<ElementRef<HTMLElement>>('log');
  private readonly field = viewChild.required<ElementRef<HTMLTextAreaElement>>('field');

  /** A conversa deste contexto. Um card novo é uma conversa nova. */
  protected readonly thread = computed(() => this.chat.thread(threadKey(this.context()))());

  protected readonly revealed = computed(() => this.context().revealed === true);
  private readonly isCard = computed(() => this.context().kind === 'card');

  protected readonly subtitle = computed(() => {
    const ctx = this.context();
    if (ctx.kind !== 'card') return 'Dúvidas sobre o que você estuda';
    const where = ctx.deck ? `${ctx.deck} · ` : '';
    return where + (ctx.revealed ? 'sobre este card' : 'dicas, sem a resposta');
  });

  protected readonly intro = computed(() => {
    if (!this.isCard()) {
      return 'Pergunte sobre um tema que não ficou claro, peça um exemplo ou uma ajuda para organizar a revisão.';
    }
    return this.revealed()
      ? 'Pergunte por que a resposta é essa, peça um exemplo ou uma explicação mais simples.'
      : 'Peça uma dica sem estragar a resposta. Depois de ver a resposta, pergunte o porquê.';
  });

  protected readonly chips = computed(() => {
    if (!this.isCard()) {
      return ['Como memorizar melhor?', 'Explique um conceito', 'Monte uma rotina de estudo'];
    }
    return this.revealed()
      ? ['Por que essa é a resposta?', 'Explique de outro jeito', 'Dê um exemplo']
      : ['Me dê uma dica', 'Explique a pergunta'];
  });

  /**
   * As sugestões de Hoje servem para começar; depois disso ocupariam três
   * linhas da folha no celular. As do card continuam: "dê um exemplo" vale
   * em qualquer ponto da conversa.
   */
  protected readonly visibleChips = computed(() =>
    this.isCard() || this.thread().length === 0 ? this.chips() : [],
  );

  protected readonly canSend = computed(() => !this.pending() && this.draft().trim().length > 0);

  constructor() {
    // O sinal `open` manda; o `<dialog>` segue. `showModal` põe o painel na
    // camada de cima, prende o foco nele e tira o resto da página do alcance
    // do leitor de tela.
    effect(() => {
      const el = this.dialog().nativeElement;
      if (this.open()) {
        if (el.open) return;
        if (typeof el.showModal === 'function') el.showModal();
        else el.setAttribute('open', '');
        untracked(() => this.focusField());
      } else if (el.open) {
        if (typeof el.close === 'function') el.close();
        else el.removeAttribute('open');
      }
    });

    // Um contexto novo (outro card) não herda o erro do anterior.
    effect(() => {
      threadKey(this.context());
      untracked(() => this.failure.set(null));
    });

    // A última mensagem sempre à vista.
    afterRenderEffect(() => {
      this.thread();
      this.pending();
      this.failure();
      const el = this.log().nativeElement;
      el.scrollTop = el.scrollHeight;
    });
  }

  protected submit(event: Event): void {
    event.preventDefault();
    this.send(this.draft());
  }

  async send(text: string): Promise<void> {
    const content = text.trim().slice(0, CHAT_MAX_CHARS);
    if (!content || this.pending()) return;
    const thread = this.chat.thread(threadKey(this.context()));
    thread.update((messages) => [...messages, { role: 'user', content }]);
    this.draft.set('');
    // Direto no campo também: se o envio vier no mesmo instante da digitação,
    // a ligação `[value]` ainda não viu o texto e não teria o que limpar.
    this.field().nativeElement.value = '';
    await this.request(thread);
  }

  protected retry(): void {
    void this.request(this.chat.thread(threadKey(this.context())));
  }

  /**
   * A resposta vai para a conversa de onde a pergunta saiu, mesmo que a tela
   * tenha mudado de contexto no meio do caminho.
   */
  private async request(thread: ReturnType<Chat['thread']>): Promise<void> {
    const context = this.context();
    this.pending.set(true);
    this.failure.set(null);
    try {
      const answer = await this.chat.ask(thread(), context);
      const content = answer.truncated
        ? `${answer.reply}\n\n(A resposta foi cortada. Peça para continuar.)`
        : answer.reply;
      thread.update((messages) => [...messages, { role: 'assistant', content } as ChatMessage]);
    } catch (error) {
      this.failure.set(chatFailure(error));
    } finally {
      this.pending.set(false);
    }
  }

  /** Enter envia; Shift+Enter quebra a linha, como em qualquer chat. */
  protected onComposerKey(event: KeyboardEvent): void {
    if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
    event.preventDefault();
    this.send(this.draft());
  }

  /**
   * Esc fecha o chat — e só o chat. `preventDefault` avisa as telas que
   * escutam o documento (o estudo sai da sessão com Esc) que a tecla já foi
   * usada aqui.
   */
  protected dismiss(event: Event): void {
    event.preventDefault();
    this.open.set(false);
  }

  /** Um clique no fundo escurecido cai no próprio `<dialog>`, fora do corpo. */
  protected onBackdrop(event: MouseEvent): void {
    if (event.target === this.dialog().nativeElement) this.open.set(false);
  }

  /**
   * No teclado físico o foco vai direto para o campo. No celular não: o
   * teclado virtual subiria por cima das sugestões antes de a pessoa lê-las.
   */
  private focusField(): void {
    const wide = typeof matchMedia === 'function' && matchMedia('(min-width: 901px)').matches;
    if (wide) queueMicrotask(() => this.field().nativeElement.focus());
  }
}
