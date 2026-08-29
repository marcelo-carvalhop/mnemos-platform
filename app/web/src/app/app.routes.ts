import { inject } from '@angular/core';
import { Router, type CanMatchFn, type Routes } from '@angular/router';
import { Session } from './core/session';

/**
 * Quem não entrou vê a landing; quem entrou vê o aplicativo.
 *
 * `CanMatch` e não `CanActivate`: com `CanMatch` a rota simplesmente não casa e
 * o roteador segue para a próxima, o que deixa `''` servir duas telas
 * diferentes sem um redirecionamento visível piscando na frente da pessoa.
 */
const signedIn: CanMatchFn = () => inject(Session).signedIn();

const signedOut: CanMatchFn = () => {
  const session = inject(Session);
  if (session.signedIn()) return inject(Router).createUrlTree(['/hoje']);
  return true;
};

// Tudo em lazy: quem chega na landing não deve baixar a tela de estudo, e é o
// que mantém o primeiro carregamento pequeno.
export const routes: Routes = [
  {
    path: '',
    canMatch: [signedIn],
    loadComponent: () => import('./shell/shell').then((m) => m.Shell),
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'hoje' },
      { path: 'hoje', loadComponent: () => import('./features/today/today').then((m) => m.Today) },
      {
        path: 'estudar',
        loadComponent: () => import('./features/study/study').then((m) => m.Study),
      },
      {
        path: 'biblioteca',
        loadComponent: () => import('./features/library/library').then((m) => m.Library),
      },
      {
        path: 'biblioteca/:deckId',
        loadComponent: () => import('./features/library/deck').then((m) => m.Deck),
      },
      {
        path: 'criar',
        loadComponent: () => import('./features/create/create').then((m) => m.Create),
      },
      {
        path: 'gerar/:jobId',
        loadComponent: () => import('./features/create/generating').then((m) => m.Generating),
      },
      {
        path: 'aprovar/:jobId',
        loadComponent: () => import('./features/create/approval').then((m) => m.Approval),
      },
      {
        path: 'progresso',
        loadComponent: () => import('./features/progress/progress').then((m) => m.Progress),
      },
      {
        path: 'dispositivo',
        loadComponent: () => import('./features/device/device').then((m) => m.Device),
      },
      {
        path: 'configuracoes',
        loadComponent: () => import('./features/settings/settings').then((m) => m.Settings),
      },
    ],
  },
  {
    path: '',
    canMatch: [signedOut],
    loadComponent: () => import('./features/landing/landing').then((m) => m.Landing),
  },
  {
    path: 'entrar',
    loadComponent: () => import('./features/landing/sign-in').then((m) => m.SignIn),
  },
  // Uma URL desconhecida volta para a raiz, e a raiz já decide entre a landing
  // e o aplicativo pelos `canMatch` acima.
  //
  // `redirectTo` **não** pode vir com `canMatch` (NG04014): redirecionamento
  // acontece antes dos guardas, e o Angular recusa a configuração inteira em
  // vez de escolher um dos dois. O erro derruba o roteador inteiro — a tela
  // fica em branco, não só esta rota.
  { path: '**', redirectTo: '' },
];
