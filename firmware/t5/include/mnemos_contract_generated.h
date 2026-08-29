// GENERATED FROM shared/contract.yaml — DO NOT EDIT.
// Regenerate with: python shared/generate.py
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace MnemosContract {

constexpr uint32_t CONTRACT_VERSION = 1U;

constexpr size_t FRONT_MAX_GRAPHEMES = 120U;
constexpr size_t BACK_MAX_GRAPHEMES = 240U;

constexpr uint32_t MATURE_INTERVAL_DAYS = 21U;
constexpr float DESIRED_RETENTION = 0.9f;
constexpr uint8_t DEFAULT_DAY_CUTOFF_HOUR = 4U;

constexpr uint32_t GRADUATION_MILESTONE_DAYS[] = {180, 365};
constexpr size_t GRADUATION_MILESTONE_COUNT =
    sizeof(GRADUATION_MILESTONE_DAYS) /
    sizeof(GRADUATION_MILESTONE_DAYS[0]);

constexpr float FSRS_WEIGHTS[] = {0.2172f, 1.1771f, 3.2602f, 16.1507f, 7.0114f, 0.57f, 2.0966f, 0.0069f, 1.5261f, 0.112f, 1.0178f, 1.849f, 0.1133f, 0.3127f, 2.2934f, 0.2191f, 3.0004f, 0.7536f, 0.3332f, 0.1437f, 0.2f};
constexpr size_t FSRS_WEIGHT_COUNT =
    sizeof(FSRS_WEIGHTS) / sizeof(FSRS_WEIGHTS[0]);

static_assert(FSRS_WEIGHT_COUNT == 21U,
              "Mnemos currently requires the 21-weight FSRS contract");

constexpr uint8_t GRADE_AGAIN = 1U;
constexpr uint8_t GRADE_HARD = 2U;
constexpr uint8_t GRADE_GOOD = 3U;
constexpr uint8_t GRADE_EASY = 4U;

constexpr const char REVIEW_SOURCE_STANDARD[] = "standard";
constexpr const char REVIEW_SOURCE_MULTIPLE_CHOICE[] = "multiple_choice";

constexpr const char CARD_STATUS_ACTIVE[] = "active";
constexpr const char CARD_STATUS_SUSPENDED[] = "suspended";
constexpr const char CARD_STATUS_BURIED[] = "buried";

constexpr uint8_t MULTIPLE_CHOICE_OPTIONS =
    4U;
constexpr uint32_t MULTIPLE_CHOICE_FAST_ANSWER_MS =
    10000U;
constexpr uint16_t LEECH_MIN_LAPSES =
    4U;
constexpr uint16_t SIMULADO_DEFAULT_QUESTIONS =
    20U;
constexpr uint16_t SIMULADO_DEFAULT_MINUTES =
    20U;
constexpr uint32_t TTS_ANSWER_PAUSE_MS =
    3000U;

constexpr uint32_t FREE_GENERATIONS_LIFETIME =
    1U;
constexpr uint32_t MAX_JOBS_IN_FLIGHT =
    2U;
constexpr uint32_t TOPIC_MAX_CHARS =
    20000U;

constexpr const char ERROR_QUOTA_EXHAUSTED[] = "quota_exhausted";
constexpr const char ERROR_TOPIC_TOO_VAGUE[] = "topic_too_vague";
constexpr const char ERROR_MATERIAL_INSUFFICIENT[] = "material_insufficient";
constexpr const char ERROR_FILE_TOO_LARGE[] = "file_too_large";
constexpr const char ERROR_PAGE_LIMIT_EXCEEDED[] = "page_limit_exceeded";
constexpr const char ERROR_PHOTO_UNREADABLE[] = "photo_unreadable";
constexpr const char ERROR_MODEL_REFUSED[] = "model_refused";
constexpr const char ERROR_NETWORK_UNAVAILABLE[] = "network_unavailable";
constexpr const char ERROR_RESYNC_REQUIRED[] = "resync_required";

}  // namespace MnemosContract
