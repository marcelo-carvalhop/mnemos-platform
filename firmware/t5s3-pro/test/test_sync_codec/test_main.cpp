#include <unity.h>

#include <cstring>

// Compila o codec real só nesta suíte; o Storage abaixo substitui o LittleFS.
#include "../../src/sync_codec.cpp"

namespace {

String outbox;

struct LocalReview {
    const char* id;
    const char* cardId;
    const char* cardType;
    uint32_t reviewedAt;
    uint32_t dueAfter;
    uint8_t schedulerRating;
    uint32_t responseTimeMs;
};

// Mesmo formato que Storage::appendReviewToPath() grava na outbox.
String outboxLine(const LocalReview& review) {
    JsonDocument doc;
    doc["schema"] = "mnemos.review/v2";
    doc["id"] = review.id;
    doc["cardId"] = review.cardId;
    doc["deckId"] = "deck-1";
    doc["cardType"] = review.cardType;
    doc["reviewedAt"] = review.reviewedAt;
    doc["responseTimeMs"] = review.responseTimeMs;
    doc["confidence"] = 80;
    doc["outcome"] = "correct";
    doc["effort"] = "normal";
    doc["schedulerRating"] = review.schedulerRating;
    doc["sessionMode"] = "review";
    doc["affectsSchedule"] = true;
    doc["automaticEvaluation"] = false;
    doc["difficultyBefore"] = 5.0;
    doc["difficultyAfter"] = 4.8;
    doc["stabilityBeforeDays"] = 3.2;
    doc["stabilityAfterDays"] = 9.1;
    doc["retrievabilityBefore"] = 0.9;
    doc["dueBefore"] = review.reviewedAt;
    doc["dueAfter"] = review.dueAfter;
    doc["source"] = "terminal";

    String line;
    serializeJson(doc, line);
    return line;
}

const LocalReview STANDARD = {
    "1759600000-123456-1a2b3c4d", "card-standard", "open_recall",
    1759600000U, 1759686400U, 3, 4200U};

const LocalReview MULTIPLE_CHOICE = {
    "1759600060-123516-ffffffff", "card-choice", "multiple_choice",
    1759600060U, 1759610000U, 4, 1500U};

JsonArrayConst reviewsOf(JsonDocument& batch) {
    const String body = SyncCodec::buildReviewBatchV2(Storage());
    TEST_ASSERT_FALSE(deserializeJson(batch, body));
    TEST_ASSERT_EQUAL_STRING("mnemos.review-batch/v2", batch["schema"] | "");
    return batch["reviews"].as<JsonArrayConst>();
}

// Regras de backend/app/terminal/service.py::_validate_terminal_review.
void assertAcceptedByBackend(
    JsonObjectConst review,
    const LocalReview& local,
    const char* expectedSource) {

    TEST_ASSERT_EQUAL_STRING("mnemos.review/v2", review["schema"] | "");

    const char* id = review["id"] | "";
    TEST_ASSERT_EQUAL_STRING(local.id, id);
    TEST_ASSERT_TRUE(std::strlen(id) >= 1 && std::strlen(id) <= 36);

    const char* cardId = review["cardId"] | "";
    TEST_ASSERT_EQUAL_STRING(local.cardId, cardId);
    TEST_ASSERT_TRUE(std::strlen(cardId) >= 1 && std::strlen(cardId) <= 36);

    TEST_ASSERT_TRUE(review["reviewedAtMs"].is<uint64_t>());
    TEST_ASSERT_EQUAL_UINT64(
        static_cast<uint64_t>(local.reviewedAt) * 1000ULL,
        review["reviewedAtMs"].as<uint64_t>());

    TEST_ASSERT_TRUE(review["schedulerRating"].is<int>());
    TEST_ASSERT_EQUAL_INT(local.schedulerRating, review["schedulerRating"].as<int>());

    TEST_ASSERT_TRUE(review["responseTimeMs"].is<uint32_t>());
    TEST_ASSERT_EQUAL_UINT32(local.responseTimeMs, review["responseTimeMs"].as<uint32_t>());

    TEST_ASSERT_EQUAL_STRING(expectedSource, review["source"] | "");

    TEST_ASSERT_EQUAL_UINT64(
        static_cast<uint64_t>(local.dueAfter) * 1000ULL,
        review["dueAfterMs"].as<uint64_t>());
}

}  // namespace

String Storage::reviewOutboxNdjson() const { return outbox; }
bool Storage::appendRemoteReviewJson(const String&, bool& inserted) {
    inserted = false;
    return true;
}
bool Storage::appendRemoteProgressResetJson(const String&, bool& inserted) {
    inserted = false;
    return true;
}
bool Storage::saveDesiredRetention(double) { return true; }
bool Storage::saveLibrary(const CardDefinition*, const CardState*, size_t) { return true; }
bool Storage::saveProgressResetCursor(uint64_t) { return true; }
bool Storage::saveReviewCursor(uint64_t) { return true; }
bool Storage::saveSettingsCursor(uint64_t) { return true; }
bool Storage::saveStates(const CardState*, size_t) { return true; }

void setUp() {
    outbox = String();
}

void tearDown() {}

void test_outbox_reviews_match_backend_contract() {
    outbox = outboxLine(STANDARD) + "\n" + outboxLine(MULTIPLE_CHOICE) + "\n";

    JsonDocument batch;
    JsonArrayConst reviews = reviewsOf(batch);

    TEST_ASSERT_EQUAL_UINT32(2, reviews.size());
    assertAcceptedByBackend(reviews[0], STANDARD, "standard");
    assertAcceptedByBackend(reviews[1], MULTIPLE_CHOICE, "multiple_choice");
}

void test_millisecond_timestamp_is_kept_when_present() {
    JsonDocument doc;
    deserializeJson(doc, outboxLine(STANDARD));
    doc["reviewedAtMs"] = 1759600000789ULL;

    String line;
    serializeJson(doc, line);
    outbox = line + "\n";

    JsonDocument batch;
    JsonArrayConst reviews = reviewsOf(batch);

    TEST_ASSERT_EQUAL_UINT32(1, reviews.size());
    TEST_ASSERT_EQUAL_UINT64(1759600000789ULL, reviews[0]["reviewedAtMs"].as<uint64_t>());
}

void test_corrupted_outbox_line_is_skipped() {
    outbox = outboxLine(STANDARD) + "\n{\"schema\":\"mnemos.rev\n" + outboxLine(MULTIPLE_CHOICE) + "\n";

    JsonDocument batch;
    JsonArrayConst reviews = reviewsOf(batch);

    TEST_ASSERT_EQUAL_UINT32(2, reviews.size());
    TEST_ASSERT_EQUAL_STRING(STANDARD.id, reviews[0]["id"] | "");
    TEST_ASSERT_EQUAL_STRING(MULTIPLE_CHOICE.id, reviews[1]["id"] | "");
}

void test_empty_outbox_yields_empty_batch() {
    JsonDocument batch;
    JsonArrayConst reviews = reviewsOf(batch);

    TEST_ASSERT_EQUAL_UINT32(0, reviews.size());
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_outbox_reviews_match_backend_contract);
    RUN_TEST(test_millisecond_timestamp_is_kept_when_present);
    RUN_TEST(test_corrupted_outbox_line_is_skipped);
    RUN_TEST(test_empty_outbox_yields_empty_batch);
    return UNITY_END();
}
