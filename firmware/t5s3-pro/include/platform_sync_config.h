#pragma once

#include <Arduino.h>

#include "config.h"

// Parâmetros da integração terminal <-> backend/app/web.
//
// Ficam fora de config.h de propósito: config.h concentra hardware e HMI, e
// este arquivo pode evoluir junto com o contrato da plataforma sem disputar
// as mesmas linhas.
namespace PlatformSync {

// HTTP. O snapshot de 128 cartões passa de 100 kB; 12 s cobre Wi-Fi fraco.
constexpr uint32_t HTTP_CONNECT_TIMEOUT_MS = 6000U;
constexpr uint32_t HTTP_RESPONSE_TIMEOUT_MS = 12000U;

// O backend aceita até 500 revisões por lote. Lotes menores mantêm o JSON
// pequeno no ESP32 e limitam o retrabalho quando um lote é recusado.
constexpr size_t REVIEW_PUSH_CHUNK = 40U;

// Páginas incrementais (reviews, resets, settings).
constexpr uint16_t PULL_PAGE_LIMIT = 200U;
constexpr uint8_t PULL_MAX_PAGES = 40U;

// Guarda de memória para o corpo do snapshot (PSRAM).
constexpr size_t SNAPSHOT_MAX_BYTES = 600U * 1024U;

// O backend limita reported_deck_ids a 32 itens e wifi_ssid a 32 chars.
constexpr size_t STATUS_MAX_DECKS = 32U;
constexpr size_t STATUS_MAX_SSID_CHARS = 32U;

// Revisões com relógio claramente inválido (antes de 2023-11-14) não sobem:
// replays em outras plataformas ordenam pelo instante da revisão.
constexpr uint64_t MIN_VALID_REVIEW_EPOCH_MS = 1700000000000ULL;

// Sincronização automática.
// - logo depois que o Wi-Fi conecta (boot, provisionamento, retomada);
// - ao fim de uma sessão com revisões pendentes;
// - periodicamente enquanto o terminal está ocioso em telas que não são de
//   estudo. O intervalo efetivo é o menor entre este e o enviado pelo app.
constexpr uint32_t AUTO_SYNC_AFTER_CONNECT_DELAY_MS = 1500U;
constexpr uint32_t AUTO_SYNC_AFTER_SESSION_DELAY_MS = 1200U;
#if defined(MNEMOS_BENCH_BUILD)
constexpr uint32_t PERIODIC_SYNC_MAX_INTERVAL_S = 300U;
#else
constexpr uint32_t PERIODIC_SYNC_MAX_INTERVAL_S = 900U;
#endif

// Quanto uma sincronização pedida espera o Wi-Fi associar.
constexpr uint32_t SYNC_WAIT_FOR_WIFI_MS = 15000U;

// Depois de uma falha de transporte, espera antes de tentar de novo sozinho.
constexpr uint32_t BACKGROUND_RETRY_BACKOFF_MS = 60000U;

// Resolução de nomes .local (mDNS) para demonstrações em rede local.
constexpr uint32_t MDNS_QUERY_TIMEOUT_MS = 1500U;
constexpr uint32_t MDNS_CACHE_MS = 5U * 60U * 1000U;

// Console serial de provisionamento/diagnóstico (USB CDC).
constexpr bool SERIAL_CONSOLE_ENABLED = true;
constexpr size_t SERIAL_CONSOLE_MAX_LINE = 1024U;

// Arquivo de quarentena: revisões que o servidor recusou de forma definitiva.
constexpr size_t REJECTED_REVIEWS_MAX_BYTES = 96U * 1024U;

}  // namespace PlatformSync
