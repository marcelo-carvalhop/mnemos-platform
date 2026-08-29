import { defineConfig } from 'vitest/config';

/**
 * Configuração do runner, passada pelo builder do Angular via `runnerConfig`.
 *
 * `pool: 'threads'` e não o padrão `forks`: o pool de forks abre um processo
 * por arquivo e espera o IPC responder, e nesta máquina os workers estouram o
 * tempo sem nunca subir. Threads usam `worker_threads`, sem processo novo — e
 * como os testes aqui são puros (escalonador, store, componentes em jsdom),
 * não há nada que exija o isolamento mais forte de um processo separado.
 */
export default defineConfig({
  test: {
    pool: 'threads',
    maxWorkers: 1,
    minWorkers: 1,
  },
});
