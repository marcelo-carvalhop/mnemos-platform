import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

/**
 * Política de privacidade e termos de uso.
 *
 * O texto descreve o que o sistema faz de verdade — o que o backend guarda,
 * por quanto tempo, e para quem cada dado vai. Mudou o sistema (um operador
 * novo, um dado novo), muda a política junto.
 *
 * Os campos em destaque (`.fill`) são entradas de negócio — quem é o
 * controlador, o contato — e não podem ser inventados aqui.
 */
@Component({
  selector: 'app-privacy',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  styleUrl: './legal.css',
  templateUrl: './privacy.html',
})
export class Privacy {}

@Component({
  selector: 'app-terms',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink],
  styleUrl: './legal.css',
  templateUrl: './terms.html',
})
export class Terms {}
