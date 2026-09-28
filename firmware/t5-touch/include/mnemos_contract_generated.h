// GENERATED FROM shared/contract.yaml — DO NOT EDIT.
// Regenerate with: python shared/generate.py
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace MnemosContract {

constexpr uint32_t CONTRACT_VERSION = 2U;

constexpr size_t FRONT_MAX_GRAPHEMES = 120U;
constexpr size_t BACK_MAX_GRAPHEMES = 240U;

constexpr uint32_t MATURE_INTERVAL_DAYS = 21U;
constexpr double DESIRED_RETENTION = 0.9;
constexpr uint8_t DEFAULT_DAY_CUTOFF_HOUR = 4U;

constexpr uint32_t LEARNING_STEPS_SECONDS[] = {60U, 600U};
constexpr size_t LEARNING_STEP_COUNT =
    sizeof(LEARNING_STEPS_SECONDS) / sizeof(LEARNING_STEPS_SECONDS[0]);

constexpr uint32_t RELEARNING_STEPS_SECONDS[] = {600U};
constexpr size_t RELEARNING_STEP_COUNT =
    sizeof(RELEARNING_STEPS_SECONDS) / sizeof(RELEARNING_STEPS_SECONDS[0]);

constexpr uint32_t MAXIMUM_INTERVAL_DAYS =
    36500U;

constexpr bool ENABLE_FSRS_FUZZ =
    false;

constexpr uint32_t GRADUATION_MILESTONE_DAYS[] = {180, 365};
constexpr size_t GRADUATION_MILESTONE_COUNT =
    sizeof(GRADUATION_MILESTONE_DAYS) /
    sizeof(GRADUATION_MILESTONE_DAYS[0]);

constexpr double FSRS_WEIGHTS[] = {0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57, 2.0966, 0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127, 2.2934, 0.2191, 3.0004, 0.7536, 0.3332, 0.1437, 0.2};
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
