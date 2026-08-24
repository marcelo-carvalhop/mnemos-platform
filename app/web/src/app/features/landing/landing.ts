import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/**
 * A landing — uma tela que o aplicativo não tem.
 *
 * Quem chega aqui não sabe o que é repetição espaçada e não deveria precisar
 * saber para entender a promessa. Por isso o texto fala do resultado — o que
 * você aprendeu volta na hora certa — e não do algoritmo.
 */
@Component({
  selector: 'app-landing',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  styleUrl: './landing.css',
  template: `
    <header class="top">
      <span class="brand">
        <span class="mark" aria-hidden="true"></span>
        Mnemos
      </span>
      <a class="enter" routerLink="/entrar">Entrar</a>
    </header>

    <section class="hero">
      <h1>O que você aprendeu, de volta na hora certa.</h1>
      <p>
        O Mnemos guarda o que você estuda e traz cada ideia de volta pouco antes de você esquecer.
        Sem sequências para manter, sem notificação cobrando presença.
      </p>
      <a class="cta" routerLink="/entrar">Começar</a>
      <p class="fine">Grátis para estudar e escrever cards. A IA que escreve por você é paga.</p>
    </section>

    <section class="three">
      <article>
        <h2>Cards curtos, uma ideia cada</h2>
        <p>
          Escreva, cole um texto ou descreva um assunto e deixe a IA propor. Nada vira card sem você
          aprovar, um por um.
        </p>
      </article>
      <article>
        <h2>Três superfícies, um histórico</h2>
        <p>
          Navegador, celular e um terminal de tinta eletrônica. O que você respondeu num aparece nos
          outros, e o cronograma é o mesmo em qualquer um.
        </p>
      </article>
      <article>
        <h2>Uma métrica só: memória</h2>
        <p>
          Não contamos dias seguidos nem cards digitados. O número que importa é quanto tempo o que
          você sabe fica de pé sem precisar de revisão.
        </p>
      </article>
    </section>
  `,
})
export class Landing {}
