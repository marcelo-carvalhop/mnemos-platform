#include "backend_sync_service.h"

#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <LittleFS.h>
#include <WiFi.h>
#include <WiFiClient.h>
#include <WiFiClientSecure.h>

#include <algorithm>
#include <functional>
#include <set>
#include <string>
#include <vector>

#include "backend_ca_bundle.h"
#include "config.h"
#include "network_service.h"
#include "platform_sync_config.h"
#include "storage.h"
#include "sync_codec.h"
#include "terminal_identity.h"
#include "text_sanitizer.h"
#include "time_service.h"

namespace {

constexpr uint32_t PENDING_SYNC_MAX_WAIT_MS = 120000U;
constexpr uint32_t MIN_VALID_EPOCH = 1700000000U;

bool isSuccess(int status) {
    return status >= 200 && status < 300;
}

String fingerprint(const String& value) {
    uint32_t hash = 2166136261UL;
    for (size_t i = 0; i < value.length(); ++i) {
        hash ^= static_cast<uint8_t>(value[i]);
        hash *= 16777619UL;
    }
    char out[9];
    snprintf(out, sizeof(out), "%08lx", static_cast<unsigned long>(hash));
    return String(out);
}

// "detail" de um erro FastAPI, como texto curto.
String errorDetail(const String& body) {
    JsonDocument doc;
    if (deserializeJson(doc, body)) return TextSanitizer::truncateUtf8(body, 120);
    JsonVariantConst detail = doc["detail"];
    if (detail.is<const char*>()) return TextSanitizer::truncateUtf8(String(detail.as<const char*>()), 160);
    String compact;
    serializeJson(detail, compact);
    return TextSanitizer::truncateUtf8(compact, 160);
}

// Ids citados entre aspas simples no detail do 403 do backend:
// "reviews reference cards outside terminal scope: ['id1', 'id2']".
std::set<std::string> quotedTokens(const String& text) {
    std::set<std::string> tokens;
    int start = text.indexOf('\'');
    while (start >= 0) {
        const int end = text.indexOf('\'', start + 1);
        if (end < 0) break;
        if (end > start + 1) tokens.insert(std::string(text.substring(start + 1, end).c_str()));
        start = text.indexOf('\'', end + 1);
    }
    return tokens;
}

// Days-from-civil (Howard Hinnant), para converter o cabeçalho Date.
int64_t daysFromCivil(int y, unsigned m, unsigned d) {
    y -= m <= 2;
    const int era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = static_cast<unsigned>(y - era * 400);
    const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return static_cast<int64_t>(era) * 146097 + static_cast<int64_t>(doe) - 719468;
}

uint32_t parseHttpDate(const String& value) {
    // RFC 7231: "Sun, 06 Nov 1994 08:49:37 GMT"
    char month[4] = {0};
    int day = 0;
    int year = 0;
    int hour = 0;
    int minute = 0;
    int second = 0;
    const int parsed = sscanf(value.c_str(), "%*3s, %d %3s %d %d:%d:%d", &day, month, &year, &hour, &minute, &second);
    if (parsed != 6) return 0;
    static const char* MONTHS[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
    unsigned monthIndex = 0;
    for (unsigned i = 0; i < 12; ++i) {
        if (strncmp(month, MONTHS[i], 3) == 0) {
            monthIndex = i + 1;
            break;
        }
    }
    if (monthIndex == 0 || day < 1 || day > 31 || year < 2023 || year > 2100) return 0;
    const int64_t days = daysFromCivil(year, monthIndex, static_cast<unsigned>(day));
    const int64_t epoch = days * 86400LL + hour * 3600LL + minute * 60LL + second;
    return epoch > 0 && epoch < 0xFFFFFFFFLL ? static_cast<uint32_t>(epoch) : 0;
}

String hostOf(const String& url) {
    const int scheme = url.indexOf("://");
    if (scheme < 0) return String();
    const int start = scheme + 3;
    int end = url.length();
    for (int i = start; i < static_cast<int>(url.length()); ++i) {
        const char c = url[i];
        if (c == ':' || c == '/' || c == '?') {
            end = i;
            break;
        }
    }
    return url.substring(start, end);
}

}  // namespace

struct BackendSyncService::Session {
    HTTPClient http;
    WiFiClient plain;
    WiFiClientSecure secure;
    String roots;  // setCACert guarda o ponteiro: precisa viver com a sessão
    bool rootsLoaded = false;
    uint16_t requests = 0;

    void drop() {
        http.end();
        plain.stop();
        secure.stop();
    }
};

BackendSyncService::BackendSyncService(NetworkService& network,
                                       Storage& storage,
                                       TimeService& clock,
                                       CardDefinition* cards,
                                       CardState* states,
                                       size_t maxCards,
                                       size_t& cardCount)
    : network_(network),
      storage_(storage),
      clock_(clock),
      cards_(cards),
      states_(states),
      maxCards_(maxCards),
      cardCount_(cardCount) {}

BackendSyncService::~BackendSyncService() = default;

void BackendSyncService::begin() {
    lastSyncMs_ = millis();
}

bool BackendSyncService::paired() const {
    return network_.backendUrl().length() > 0 && network_.deviceToken().length() > 0;
}

bool BackendSyncService::consumeLibraryUpdated() {
    const bool value = libraryUpdated_;
    libraryUpdated_ = false;
    return value;
}

void BackendSyncService::requestSync(SyncTrigger trigger, uint32_t delayMs) {
    if (!paired()) return;
    const uint32_t now = millis();
    const uint32_t due = now + delayMs;
    if (!pending_) {
        pending_ = true;
        pendingTrigger_ = trigger;
        pendingDueMs_ = due;
        pendingSinceMs_ = now;
    } else if (static_cast<int32_t>(due - pendingDueMs_) < 0) {
        pendingDueMs_ = due;
    }
    Serial.printf("[backend] sync agendada trigger=%s em %lums\n",
                  triggerName(trigger), static_cast<unsigned long>(delayMs));
}

void BackendSyncService::loop() {
    if (!paired()) {
        pending_ = false;
        return;
    }

    const uint32_t now = millis();

    if (pending_) {
        if (network_.connected()) {
            if (static_cast<int32_t>(now - pendingDueMs_) >= 0) syncNow(pendingTrigger_);
        } else if (now - pendingSinceMs_ > PENDING_SYNC_MAX_WAIT_MS) {
            Serial.printf("[backend] sync %s descartada: Wi-Fi não conectou\n",
                          triggerName(pendingTrigger_));
            pending_ = false;
        }
        return;
    }

    if (!network_.connected() || authRejected_) return;

    if (lastFailureMs_ != 0 && now - lastFailureMs_ < PlatformSync::BACKGROUND_RETRY_BACKOFF_MS) return;

    uint32_t intervalS = network_.syncIntervalSeconds();
    if (intervalS == 0 || intervalS > PlatformSync::PERIODIC_SYNC_MAX_INTERVAL_S) {
        intervalS = PlatformSync::PERIODIC_SYNC_MAX_INTERVAL_S;
    }
    if (now - lastSyncMs_ >= intervalS * 1000UL) syncNow(SyncTrigger::Periodic);
}

String BackendSyncService::rootCertificates() {
    String roots = Config::BACKEND_ROOT_CA;
    if (roots.length() > 0) return roots;

    if (LittleFS.exists(Config::BACKEND_CA_FILE)) {
        File file = LittleFS.open(Config::BACKEND_CA_FILE, "r");
        if (file) {
            roots = file.readString();
            file.close();
        }
        if (roots.indexOf("BEGIN CERTIFICATE") >= 0) return roots;
    }

    return String(MnemosCa::DEFAULT_BACKEND_ROOTS);
}

String BackendSyncService::resolveUrl(const String& url) {
    // Demonstração local: "http://notebook.local:8000" funciona mesmo que o
    // IP do notebook mude entre o ensaio e a apresentação.
    if (!url.startsWith("http://")) return url;
    const String host = hostOf(url);
    if (!host.endsWith(".local")) return url;

    const uint32_t now = millis();
    if (host == mdnsHost_ && mdnsIp_.length() > 0 && now - mdnsResolvedMs_ < PlatformSync::MDNS_CACHE_MS) {
        String resolved = url;
        resolved.replace("://" + host, "://" + mdnsIp_);
        return resolved;
    }

    static bool mdnsStarted = false;
    if (!mdnsStarted) {
        String name = "mnemos-" + TerminalIdentity::macSuffix();
        name.toLowerCase();
        mdnsStarted = MDNS.begin(name.c_str());
    }

    const String bare = host.substring(0, host.length() - 6);
    const IPAddress ip = MDNS.queryHost(bare.c_str(), PlatformSync::MDNS_QUERY_TIMEOUT_MS);
    if (ip == IPAddress(0, 0, 0, 0)) {
        Serial.printf("[backend] mDNS: %s não respondeu\n", host.c_str());
        return url;
    }

    mdnsHost_ = host;
    mdnsIp_ = ip.toString();
    mdnsResolvedMs_ = now;
    Serial.printf("[backend] mDNS: %s -> %s\n", host.c_str(), mdnsIp_.c_str());

    String resolved = url;
    resolved.replace("://" + host, "://" + mdnsIp_);
    return resolved;
}

void BackendSyncService::adjustClockFromDate(const String& dateHeader) {
    if (dateHeader.length() == 0 || report_.clockAdjusted) return;
    const uint32_t serverEpoch = parseHttpDate(dateHeader);
    if (serverEpoch < MIN_VALID_EPOCH) return;

    const uint32_t local = clock_.now();
    const int64_t diff = static_cast<int64_t>(serverEpoch) - static_cast<int64_t>(local);
    const bool farOff = diff > 300 || diff < -300;

    // Sem internet (demo local) não há NTP: o relógio do servidor é a melhor
    // referência disponível e evita revisões com data errada.
    if (!clock_.trusted() || (!clock_.ntpSynchronized() && farOff)) {
        clock_.setFromEpoch(serverEpoch);
        report_.clockAdjusted = true;
        Serial.printf("[backend] relógio ajustado pelo servidor (diferença %llds)\n",
                      static_cast<long long>(diff));
    }
}

bool BackendSyncService::request(const char* method,
                                 const String& path,
                                 const String& body,
                                 HttpResult& out) {
    out = HttpResult{};

    String base = network_.backendUrl();
    base.trim();
    while (base.endsWith("/")) base.remove(base.length() - 1);
    const String url = resolveUrl(base) + path;
    const bool https = url.startsWith("https://");

    if (!https && !url.startsWith("http://")) {
        out.error = "invalid_backend_url";
        return false;
    }

    // Fora de syncNow (raro) usa uma sessão de uma requisição só.
    std::unique_ptr<Session> temporary;
    if (!session_) temporary.reset(new Session());
    Session& session = session_ ? *session_ : *temporary;

    for (uint8_t attempt = 0; attempt < 2; ++attempt) {
        if (attempt > 0) {
            // Conexão reaproveitada pode ter sido fechada pelo servidor
            // (keep-alive expirado): tenta uma vez com conexão nova.
            session.drop();
            out = HttpResult{};
        }

        bool begun = false;
        if (https) {
            if (!session.rootsLoaded) {
                session.roots = rootCertificates();
                session.rootsLoaded = true;
                session.secure.setCACert(session.roots.c_str());
                session.secure.setHandshakeTimeout((PlatformSync::HTTP_CONNECT_TIMEOUT_MS / 1000U) + 4U);
            }
            begun = session.http.begin(session.secure, url);
        } else {
            begun = session.http.begin(session.plain, url);
        }

        if (!begun) {
            out.error = "http_begin_failed";
            return false;
        }

        session.http.setReuse(session_ != nullptr);
        session.http.setConnectTimeout(static_cast<int32_t>(PlatformSync::HTTP_CONNECT_TIMEOUT_MS));
        session.http.setTimeout(static_cast<uint16_t>(PlatformSync::HTTP_RESPONSE_TIMEOUT_MS));
        session.http.setUserAgent(String("Mnemos-T5S3/") + Config::APP_VERSION);
        session.http.addHeader("Authorization", "Bearer " + network_.deviceToken());
        session.http.addHeader("Content-Type", "application/json");
        session.http.addHeader("Accept", "application/json");
        const char* headerKeys[] = {"Date"};
        session.http.collectHeaders(headerKeys, 1);

        const int status = strcmp(method, "GET") == 0 ? session.http.GET() : session.http.POST(body);
        if (status <= 0) {
            out.status = status;
            out.error = HTTPClient::errorToString(status);
            if (https) {
                char tlsError[96] = {0};
                if (session.secure.lastError(tlsError, sizeof(tlsError)) != 0 && tlsError[0] != '\0') {
                    out.error = String("tls: ") + tlsError;
                }
            }
            const bool retry = attempt == 0 && session.requests > 0;
            session.drop();
            if (retry) continue;
            return false;
        }

        out.status = status;
        out.transportOk = true;

        const int size = session.http.getSize();
        if (size > 0 && static_cast<size_t>(size) > PlatformSync::SNAPSHOT_MAX_BYTES) {
            out.error = "response_too_large";
            session.drop();
            return false;
        }

        out.body = session.http.getString();
        adjustClockFromDate(session.http.header("Date"));
        session.http.end();  // com reuse, mantém o socket aberto
        ++session.requests;
        return true;
    }

    return false;
}

void BackendSyncService::noteHttpFailure(const char* step, const HttpResult& result) {
    if (report_.failedStep.length() == 0) {
        report_.failedStep = step;
        report_.httpStatus = result.status;
        report_.detail = result.transportOk ? errorDetail(result.body) : result.error;
    }

    SyncOutcome outcome = SyncOutcome::ServerError;
    if (!result.transportOk) {
        outcome = result.error.startsWith("tls") ? SyncOutcome::TlsFailed : SyncOutcome::Unreachable;
    } else if (result.status == 401) {
        authRejected_ = true;
        outcome = SyncOutcome::AuthRejected;
    }

    if (report_.outcome == SyncOutcome::NeverRan || report_.outcome == SyncOutcome::Partial) {
        report_.outcome = outcome;
    }

    Serial.printf("[backend] %s falhou: HTTP %d %s\n", step, result.status,
                  result.transportOk ? errorDetail(result.body).c_str() : result.error.c_str());
}

void BackendSyncService::resetCursorsIfCredentialChanged() {
    const String current = fingerprint(network_.backendUrl() + "\n" + network_.deviceToken());
    const String stored = storage_.syncMetaString("credential");
    if (stored == current) return;

    // Outra conta (ou outro servidor) tem outra sequência server_seq. Começar
    // do zero é seguro: eventos já conhecidos são deduplicados por id.
    storage_.resetSyncCursors();
    storage_.saveSyncMetaString("credential", current);
    Serial.println("[backend] credencial nova: cursores reiniciados");
}

bool BackendSyncService::pushReviews() {
    std::vector<String> lines;
    storage_.loadReviewOutboxLines(lines);
    if (lines.empty()) return true;

    struct Item {
        String line;
        String id;
        String cardId;
    };

    std::vector<Item> pushable;
    std::vector<String> rejected;
    std::set<std::string> seenIds;
    String rejectReason;
    uint16_t dropped = 0;

    for (const String& line : lines) {
        JsonDocument scratch;
        JsonObject remote = scratch.to<JsonObject>();
        String id;
        String cardId;
        String reason;
        switch (SyncCodec::convertOutboxLine(line, remote, id, cardId, reason)) {
            case SyncCodec::OutboxLineKind::Push:
                if (seenIds.insert(std::string(id.c_str())).second) {
                    pushable.push_back(Item{line, id, cardId});
                } else {
                    ++dropped;  // linha duplicada (migração antiga)
                }
                break;
            case SyncCodec::OutboxLineKind::DropNotScheduled:
                ++dropped;
                break;
            case SyncCodec::OutboxLineKind::Reject:
                rejected.push_back(line);
                if (rejectReason.length() == 0) rejectReason = reason;
                break;
        }
    }

    if (!rejected.empty()) {
        storage_.quarantineReviewLines(rejected, "local:" + rejectReason);
        report_.reviewsQuarantined += rejected.size();
        Serial.printf("[backend] %u revisões locais inválidas em quarentena (%s)\n",
                      static_cast<unsigned>(rejected.size()), rejectReason.c_str());
    }
    report_.reviewsDropped += dropped;

    std::set<std::string> done;
    bool ok = true;

    auto bodyFor = [&](const std::vector<size_t>& indexes) {
        JsonDocument batch;
        batch["schema"] = "mnemos.review-batch/v2";
        JsonArray reviews = batch["reviews"].to<JsonArray>();
        for (size_t index : indexes) {
            JsonObject remote = reviews.add<JsonObject>();
            String id;
            String cardId;
            String reason;
            SyncCodec::convertOutboxLine(pushable[index].line, remote, id, cardId, reason);
        }
        String body;
        serializeJson(batch, body);
        return body;
    };

    auto quarantine = [&](const std::vector<size_t>& indexes, const String& reason) {
        std::vector<String> rows;
        for (size_t index : indexes) {
            rows.push_back(pushable[index].line);
            done.insert(std::string(pushable[index].id.c_str()));
        }
        storage_.quarantineReviewLines(rows, reason);
        report_.reviewsQuarantined += rows.size();
        Serial.printf("[backend] %u revisões recusadas pelo servidor: %s\n",
                      static_cast<unsigned>(rows.size()), reason.c_str());
    };

    auto markPushed = [&](const std::vector<size_t>& indexes) {
        for (size_t index : indexes) done.insert(std::string(pushable[index].id.c_str()));
        report_.reviewsPushed += indexes.size();
    };

    // Envia um conjunto; devolve false em falha transitória (fila preservada).
    std::function<bool(std::vector<size_t>, bool)> send =
        [&](std::vector<size_t> indexes, bool allowSplit) -> bool {
        for (uint8_t attempt = 0; attempt < 4 && !indexes.empty(); ++attempt) {
            HttpResult result;
            if (!request("POST", "/v1/terminal/reviews", bodyFor(indexes), result)) {
                noteHttpFailure("reviews", result);
                return false;
            }

            if (isSuccess(result.status)) {
                markPushed(indexes);
                return true;
            }

            if (result.status == 401) {
                noteHttpFailure("reviews", result);
                return false;
            }

            if (result.status == 403) {
                // Cartões apagados no app/web ou de outra conta.
                const std::set<std::string> cardIds = quotedTokens(errorDetail(result.body));
                std::vector<size_t> refused;
                std::vector<size_t> remaining;
                for (size_t index : indexes) {
                    if (cardIds.count(std::string(pushable[index].cardId.c_str()))) refused.push_back(index);
                    else remaining.push_back(index);
                }
                if (refused.empty()) {
                    noteHttpFailure("reviews", result);
                    return false;
                }
                quarantine(refused, "server:outside_terminal_scope");
                indexes = remaining;
                continue;
            }

            if (result.status == 422) {
                if (indexes.size() == 1) {
                    quarantine(indexes, "server:" + errorDetail(result.body));
                    return true;
                }
                if (!allowSplit) {
                    noteHttpFailure("reviews", result);
                    return false;
                }
                // Isola a revisão problemática enviando uma a uma.
                for (size_t index : indexes) {
                    if (!send(std::vector<size_t>{index}, false)) return false;
                }
                return true;
            }

            noteHttpFailure("reviews", result);
            return false;
        }
        return indexes.empty();
    };

    for (size_t start = 0; start < pushable.size() && ok; start += PlatformSync::REVIEW_PUSH_CHUNK) {
        std::vector<size_t> chunk;
        const size_t end = std::min(pushable.size(), start + PlatformSync::REVIEW_PUSH_CHUNK);
        for (size_t i = start; i < end; ++i) chunk.push_back(i);
        ok = send(chunk, true);
    }

    std::vector<String> remaining;
    for (const Item& item : pushable) {
        if (!done.count(std::string(item.id.c_str()))) remaining.push_back(item.line);
    }
    if (remaining.size() != lines.size()) {
        if (!storage_.rewriteReviewOutbox(remaining)) {
            report_.outcome = SyncOutcome::StorageError;
            if (report_.failedStep.length() == 0) report_.failedStep = "outbox";
            return false;
        }
    }
    report_.reviewsPending = remaining.size();
    return ok;
}

bool BackendSyncService::pullSnapshot(bool& capacityExceeded) {
    capacityExceeded = false;

    HttpResult result;
    const String path = "/v1/terminal/snapshot?limit=" + String(maxCards_) + "&schema=mnemos.sync%2Fv2";
    if (!request("GET", path, "", result)) {
        noteHttpFailure("snapshot", result);
        return false;
    }

    if (result.status == 409) {
        capacityExceeded = true;
        if (report_.failedStep.length() == 0) {
            report_.failedStep = "snapshot";
            report_.httpStatus = 409;
            report_.detail = errorDetail(result.body);
        }
        Serial.printf("[backend] snapshot recusado: %s\n", errorDetail(result.body).c_str());
        return false;
    }

    if (!isSuccess(result.status)) {
        noteHttpFailure("snapshot", result);
        return false;
    }

    JsonDocument filter;
    SyncCodec::buildSnapshotFilter(filter);
    JsonDocument doc;
    const DeserializationError parseError =
        deserializeJson(doc, result.body, DeserializationOption::Filter(filter));
    result.body = String();  // libera a PSRAM antes de montar a biblioteca

    if (parseError) {
        HttpResult invalid;
        invalid.transportOk = true;
        invalid.status = 200;
        invalid.body = String("{\"detail\":\"snapshot_json: ") + parseError.c_str() + "\"}";
        noteHttpFailure("snapshot", invalid);
        return false;
    }

    SyncCodec::SnapshotApplyResult applied;
    String error;
    if (!SyncCodec::applySnapshotDocument(doc, cards_, states_, maxCards_, cardCount_, storage_, true,
                                          applied, error)) {
        report_.outcome = error == "storage_failed" ? SyncOutcome::StorageError : SyncOutcome::ServerError;
        if (report_.failedStep.length() == 0) {
            report_.failedStep = "snapshot";
            report_.detail = error;
        }
        Serial.printf("[backend] snapshot rejeitado: %s\n", error.c_str());
        return false;
    }

    report_.cards = applied.cards;
    report_.cardsSkipped = applied.skipped;
    report_.libraryChanged = applied.changed;
    report_.keptLocalLibrary = applied.keptLocalLibrary;

    if (applied.skipped > 0) {
        Serial.printf("[backend] snapshot: %u cartões ignorados (%s)\n",
                      static_cast<unsigned>(applied.skipped), applied.firstSkipReason.c_str());
    }

    if (applied.changed) {
        libraryUpdated_ = true;
        Serial.printf("[backend] biblioteca atualizada: %u cartões\n", static_cast<unsigned>(applied.cards));
    }

    return true;
}

bool BackendSyncService::pullReviews() {
    uint64_t cursor = storage_.reviewCursor();

    for (uint8_t page = 0; page < PlatformSync::PULL_MAX_PAGES; ++page) {
        char path[96];
        snprintf(path, sizeof(path), "/v1/terminal/reviews?since=%llu&limit=%u",
                 static_cast<unsigned long long>(cursor), PlatformSync::PULL_PAGE_LIMIT);

        HttpResult result;
        if (!request("GET", path, "", result)) {
            noteHttpFailure("reviews_pull", result);
            return false;
        }

        if (result.status == 410 && cursor != 0) {
            Serial.println("[backend] cursor de reviews expirado; reiniciando em 0");
            if (!storage_.saveReviewCursor(0)) return false;
            cursor = 0;
            continue;
        }

        if (!isSuccess(result.status)) {
            noteHttpFailure("reviews_pull", result);
            return false;
        }

        SyncCodec::ReviewDeltaApplyResult delta;
        String error;
        if (!SyncCodec::applyReviewDeltaV2(result.body, storage_, delta, error)) {
            report_.outcome = SyncOutcome::StorageError;
            if (report_.failedStep.length() == 0) {
                report_.failedStep = "reviews_pull";
                report_.detail = error;
            }
            Serial.printf("[backend] delta de reviews rejeitado: %s\n", error.c_str());
            return false;
        }

        if (delta.appended > 0) {
            libraryUpdated_ = true;  // estado FSRS mudou: replay necessário
            report_.remoteReviews += delta.appended;
        }

        if (!delta.hasMore) return true;
        if (delta.cursor <= cursor) {
            Serial.println("[backend] cursor de reviews não avançou");
            return false;
        }
        cursor = delta.cursor;
    }

    // Histórico muito longo: continua na próxima rodada a partir do cursor salvo.
    Serial.println("[backend] limite de páginas de reviews; continua na próxima sincronização");
    return true;
}

bool BackendSyncService::pullProgressResets() {
    uint64_t cursor = storage_.progressResetCursor();

    for (uint8_t page = 0; page < PlatformSync::PULL_MAX_PAGES; ++page) {
        char path[104];
        snprintf(path, sizeof(path), "/v1/terminal/progress-resets?since=%llu&limit=%u",
                 static_cast<unsigned long long>(cursor), PlatformSync::PULL_PAGE_LIMIT);

        HttpResult result;
        if (!request("GET", path, "", result)) {
            noteHttpFailure("resets_pull", result);
            return false;
        }

        if (result.status == 410 && cursor != 0) {
            Serial.println("[backend] cursor de resets expirado; reiniciando em 0");
            if (!storage_.saveProgressResetCursor(0)) return false;
            cursor = 0;
            continue;
        }

        if (!isSuccess(result.status)) {
            noteHttpFailure("resets_pull", result);
            return false;
        }

        SyncCodec::ProgressResetDeltaApplyResult delta;
        String error;
        if (!SyncCodec::applyProgressResetDeltaV2(result.body, storage_, delta, error)) {
            report_.outcome = SyncOutcome::StorageError;
            if (report_.failedStep.length() == 0) {
                report_.failedStep = "resets_pull";
                report_.detail = error;
            }
            Serial.printf("[backend] delta de resets rejeitado: %s\n", error.c_str());
            return false;
        }

        if (delta.appended > 0) {
            libraryUpdated_ = true;
            report_.remoteResets += delta.appended;
        }

        if (!delta.hasMore) return true;
        if (delta.cursor <= cursor) {
            Serial.println("[backend] cursor de resets não avançou");
            return false;
        }
        cursor = delta.cursor;
    }

    Serial.println("[backend] limite de páginas de resets; continua na próxima sincronização");
    return true;
}

bool BackendSyncService::pullSettings() {
    uint64_t cursor = storage_.settingsCursor();

    for (uint8_t page = 0; page < PlatformSync::PULL_MAX_PAGES; ++page) {
        char path[96];
        snprintf(path, sizeof(path), "/v1/terminal/settings?since=%llu&limit=%u",
                 static_cast<unsigned long long>(cursor), PlatformSync::PULL_PAGE_LIMIT);

        HttpResult result;
        if (!request("GET", path, "", result)) {
            noteHttpFailure("settings_pull", result);
            return false;
        }

        if (result.status == 410 && cursor != 0) {
            Serial.println("[backend] cursor de settings expirado; reiniciando em 0");
            if (!storage_.saveSettingsCursor(0)) return false;
            cursor = 0;
            continue;
        }

        if (!isSuccess(result.status)) {
            noteHttpFailure("settings_pull", result);
            return false;
        }

        SyncCodec::UserSettingDeltaApplyResult delta;
        String error;
        if (!SyncCodec::applyUserSettingDeltaV2(result.body, storage_, delta, error)) {
            report_.outcome = SyncOutcome::StorageError;
            if (report_.failedStep.length() == 0) {
                report_.failedStep = "settings_pull";
                report_.detail = error;
            }
            Serial.printf("[backend] delta de settings rejeitado: %s\n", error.c_str());
            return false;
        }

        if (delta.applied > 0) {
            libraryUpdated_ = true;  // retenção nova exige replay integral
            report_.settingsApplied += delta.applied;
            Serial.printf("[backend] retenção desejada agora %.4f\n", storage_.desiredRetention());
        }

        if (!delta.hasMore) return true;
        if (delta.cursor <= cursor) {
            Serial.println("[backend] cursor de settings não avançou");
            return false;
        }
        cursor = delta.cursor;
    }

    Serial.println("[backend] limite de páginas de settings; continua na próxima sincronização");
    return true;
}

bool BackendSyncService::reportStatus(bool synced) {
    const bool fromBackend = storage_.libraryFromBackend();

    auto build = [&](bool includeDecks) {
        JsonDocument doc;
        JsonArray deckIds = doc["reported_deck_ids"].to<JsonArray>();
        uint64_t revision = 0;
        std::set<std::string> seen;
        for (size_t i = 0; i < cardCount_; ++i) {
            if (cards_[i].revision > revision) revision = cards_[i].revision;
            if (!includeDecks || cards_[i].deckId.length() == 0) continue;
            if (deckIds.size() >= PlatformSync::STATUS_MAX_DECKS) continue;
            if (seen.insert(std::string(cards_[i].deckId.c_str())).second) deckIds.add(cards_[i].deckId);
        }

        doc["card_count"] = cardCount_;
        doc["max_cards"] = maxCards_;
        doc["connectivity"] = network_.connected() ? "wifi" : "offline";
        const String ssid = TextSanitizer::truncateUtf8(network_.ssid(), PlatformSync::STATUS_MAX_SSID_CHARS);
        if (ssid.length() > 0) doc["wifi_ssid"] = ssid;
        doc["library_revision"] = revision;
        doc["synced"] = synced;

        // Campos extras são ignorados pelo backend atual e documentam o
        // terminal para versões futuras.
        doc["firmware"] = Config::APP_VERSION;
        doc["protocol"] = Config::DEVICE_PROTOCOL_VERSION;
        doc["pending_reviews"] = storage_.pendingReviewCount();
        doc["library_source"] = fromBackend ? "backend" : "local";
        doc["capabilities"]["directWifiSync"] = true;
        doc["capabilities"]["bleSync"] = false;
        doc["capabilities"]["keyboard"] = false;
        doc["capabilities"]["touch"] = Config::TOUCH_ENABLED;
        doc["capabilities"]["typedRecall"] = false;
        doc["capabilities"]["display"] = "epaper-960x540";
        doc["capabilities"]["microSD"] = true;
        doc["capabilities"]["sdFirstLibrary"] = true;
        doc["capabilities"]["lazyCardContent"] = true;

        String body;
        serializeJson(doc, body);
        return body;
    };

    // Só baralhos vindos do backend são reportados: o backend responde 500
    // quando recebe um id de baralho que não pertence à conta.
    HttpResult result;
    if (!request("POST", "/v1/terminal/status", build(fromBackend), result)) {
        noteHttpFailure("status", result);
        return false;
    }

    if (result.status >= 500 && fromBackend) {
        Serial.println("[backend] status recusado com baralhos; reenviando sem a lista");
        if (!request("POST", "/v1/terminal/status", build(false), result)) {
            noteHttpFailure("status", result);
            return false;
        }
    }

    if (!isSuccess(result.status)) {
        noteHttpFailure("status", result);
        return false;
    }
    return true;
}

bool BackendSyncService::syncNow(SyncTrigger trigger) {
    const uint32_t started = millis();
    report_ = BackendSyncReport{};
    report_.trigger = trigger;
    pending_ = false;

    auto finish = [&](bool ok) {
        if (session_) {
            session_->drop();
            session_.reset();
        }
        report_.finishedAtMs = millis();
        report_.durationMs = report_.finishedAtMs - started;
        if (report_.reviewsPending == 0) report_.reviewsPending = storage_.pendingReviewCount();
        if (report_.cards == 0) report_.cards = cardCount_;
        if (ok) {
            lastFailureMs_ = 0;
        } else {
            lastFailureMs_ = millis();
        }
        Serial.printf(
            "[backend] sync trigger=%s outcome=%s step=%s http=%d push=%u drop=%u quar=%u pend=%u "
            "cards=%u changed=%d remote=%u resets=%u settings=%u clock=%d %lums\n",
            triggerName(trigger), outcomeName(report_.outcome), report_.failedStep.c_str(), report_.httpStatus,
            report_.reviewsPushed, report_.reviewsDropped, report_.reviewsQuarantined, report_.reviewsPending,
            static_cast<unsigned>(report_.cards), report_.libraryChanged ? 1 : 0, report_.remoteReviews,
            report_.remoteResets, report_.settingsApplied, report_.clockAdjusted ? 1 : 0,
            static_cast<unsigned long>(report_.durationMs));
        return ok;
    };

    if (!paired()) {
        report_.outcome = SyncOutcome::NotPaired;
        return finish(false);
    }

    if (!network_.connected()) {
        report_.outcome = SyncOutcome::Offline;
        return finish(false);
    }

    lastSyncMs_ = millis();
    resetCursorsIfCredentialChanged();
    session_.reset(new Session());

    const bool pushOk = pushReviews();
    if (authRejected_) {
        report_.outcome = SyncOutcome::AuthRejected;
        return finish(false);
    }

    bool capacityExceeded = false;
    const bool snapshotOk = pullSnapshot(capacityExceeded);
    if (authRejected_) {
        report_.outcome = SyncOutcome::AuthRejected;
        return finish(false);
    }

    // Com 409 a biblioteca anterior continua válida: os eventos de estudo
    // ainda podem ser trazidos.
    const bool pullsAllowed = snapshotOk || capacityExceeded;
    const bool reviewsOk = pullsAllowed && pullReviews();
    const bool resetsOk = pullsAllowed && reviewsOk && pullProgressResets();
    const bool settingsOk = pullsAllowed && resetsOk && pullSettings();

    const bool synced = pushOk && snapshotOk && reviewsOk && resetsOk && settingsOk;
    const bool statusOk = !authRejected_ && reportStatus(synced);

    if (authRejected_) {
        report_.outcome = SyncOutcome::AuthRejected;
    } else if (synced) {
        report_.outcome = SyncOutcome::Ok;
        everSynced_ = true;
        authRejected_ = false;
    } else if (capacityExceeded) {
        report_.outcome = SyncOutcome::CapacityExceeded;
    } else if (report_.outcome == SyncOutcome::NeverRan) {
        report_.outcome = SyncOutcome::Partial;
    }

    (void)statusOk;
    return finish(synced);
}

const char* BackendSyncService::triggerName(SyncTrigger trigger) {
    switch (trigger) {
        case SyncTrigger::Manual: return "manual";
        case SyncTrigger::Boot: return "boot";
        case SyncTrigger::WifiConnected: return "wifi";
        case SyncTrigger::SessionEnd: return "session";
        case SyncTrigger::Periodic: return "periodic";
        case SyncTrigger::Provisioned: return "provisioned";
        case SyncTrigger::Serial: return "serial";
    }
    return "?";
}

const char* BackendSyncService::outcomeName(SyncOutcome outcome) {
    switch (outcome) {
        case SyncOutcome::NeverRan: return "never";
        case SyncOutcome::Ok: return "ok";
        case SyncOutcome::Partial: return "partial";
        case SyncOutcome::Offline: return "offline";
        case SyncOutcome::NotPaired: return "not_paired";
        case SyncOutcome::AuthRejected: return "auth_rejected";
        case SyncOutcome::Unreachable: return "unreachable";
        case SyncOutcome::TlsFailed: return "tls_failed";
        case SyncOutcome::CapacityExceeded: return "capacity_exceeded";
        case SyncOutcome::ServerError: return "server_error";
        case SyncOutcome::StorageError: return "storage_error";
    }
    return "?";
}

String BackendSyncService::outcomeTitle(const BackendSyncReport& report) {
    switch (report.outcome) {
        case SyncOutcome::Ok: return "Sincronizado";
        case SyncOutcome::Partial: return "Sincronização parcial";
        case SyncOutcome::Offline: return "Sem rede";
        case SyncOutcome::NotPaired: return "Terminal sem conta";
        case SyncOutcome::AuthRejected: return "Credencial recusada";
        case SyncOutcome::Unreachable: return "Servidor inacessível";
        case SyncOutcome::TlsFailed: return "Falha de HTTPS";
        case SyncOutcome::CapacityExceeded: return "Biblioteca grande demais";
        case SyncOutcome::ServerError: return "Erro no servidor";
        case SyncOutcome::StorageError: return "Erro de armazenamento";
        case SyncOutcome::NeverRan: break;
    }
    return "Sincronização";
}

String BackendSyncService::outcomeMessage(const BackendSyncReport& report) {
    String text;
    switch (report.outcome) {
        case SyncOutcome::Ok:
            text = String(report.cards) + " cartões no terminal.\n";
            text += String(report.reviewsPushed) + " revisões enviadas, " + String(report.remoteReviews) +
                    " recebidas de outros aparelhos.";
            if (report.keptLocalLibrary) {
                text += "\nNenhum baralho escolhido para este terminal: escolha em Dispositivo, no app ou na web.";
            } else if (report.cards == 0) {
                text += "\nNenhum baralho escolhido: marque baralhos em Dispositivo, no app ou na web.";
            }
            if (report.cardsSkipped > 0) {
                text += "\n" + String(report.cardsSkipped) + " cartões ignorados (tipo não suportado).";
            }
            if (report.reviewsQuarantined > 0) {
                text += "\n" + String(report.reviewsQuarantined) + " revisões de cartões apagados ficaram só aqui.";
            }
            break;
        case SyncOutcome::Partial:
            text = "Parte da sincronização falhou (" + report.failedStep +
                   "). Nada foi perdido: o terminal tenta de novo sozinho.";
            break;
        case SyncOutcome::Offline:
            text = "O Wi-Fi não está conectado. Verifique a rede em Menu > Conexão e tente de novo.";
            break;
        case SyncOutcome::NotPaired:
            text = "No app: Dispositivo > Conectar um Mnemos e leia o QR de Menu > Conexão > "
                   "Configurar pelo celular. Também dá para parear pelo cabo USB (tools/mnemos_demo.py).";
            break;
        case SyncOutcome::AuthRejected:
            text = "O servidor recusou a credencial deste terminal (removido ou de outra conta). "
                   "Pareie de novo pelo app ou pelo cabo USB.";
            break;
        case SyncOutcome::Unreachable:
            text = "Sem resposta do servidor. Confira se ele está ligado e na mesma rede do terminal.";
            if (report.detail.length() > 0) text += "\n(" + report.detail + ")";
            break;
        case SyncOutcome::TlsFailed:
            text = "O certificado do servidor não foi aceito. Grave a CA raiz em /backend_ca.pem ou use HTTP na rede local.";
            break;
        case SyncOutcome::CapacityExceeded:
            text = "Os baralhos escolhidos passam da capacidade do terminal. Desmarque algum em Dispositivo. "
                   "O terminal continua com a biblioteca anterior.";
            break;
        case SyncOutcome::ServerError:
            text = "O servidor respondeu HTTP " + String(report.httpStatus) + " em " + report.failedStep + ".";
            if (report.detail.length() > 0) text += "\n" + report.detail;
            break;
        case SyncOutcome::StorageError:
            text = "Falha ao gravar na memória interna (" + report.failedStep + ").";
            break;
        case SyncOutcome::NeverRan:
            text = "Ainda não sincronizou.";
            break;
    }
    if (report.reviewsPending > 0 && report.outcome != SyncOutcome::Ok) {
        text += "\n" + String(report.reviewsPending) + " revisões aguardam envio.";
    }
    return text;
}
