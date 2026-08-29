import { Pipe, type PipeTransform } from '@angular/core';

/**
 * Um intervalo em português, na unidade que a pessoa usaria.
 *
 * "43200000ms" e "0,5 dias" dizem a mesma coisa e nenhuma das duas responde à
 * pergunta que o botão faz — *quando eu vejo isso de novo?*. A unidade muda com
 * a magnitude porque é assim que se fala: minutos abaixo de uma hora, dias até
 * um mês, meses até um ano.
 */
@Pipe({ name: 'interval' })
export class IntervalPipe implements PipeTransform {
  transform(ms: number | null | undefined): string {
    if (ms == null || !Number.isFinite(ms)) return '—';

    const minutes = Math.round(ms / 60_000);
    if (minutes < 1) return 'agora';
    if (minutes < 60) return `${minutes} min`;

    const hours = Math.round(minutes / 60);
    if (hours < 24) return `${hours} h`;

    const days = Math.round(ms / 86_400_000);
    if (days < 31) return days === 1 ? '1 dia' : `${days} dias`;

    const months = Math.round(days / 30.44);
    if (months < 12) return months === 1 ? '1 mês' : `${months} meses`;

    // Uma casa decimal até dois anos: "1,5 anos" carrega informação que "2
    // anos" jogaria fora, e depois disso a precisão deixa de importar.
    const years = days / 365.25;
    if (years < 2) return `${years.toFixed(1).replace('.', ',')} anos`;
    return `${Math.round(years)} anos`;
  }
}
