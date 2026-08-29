#include "schedule_service.h"

#include <algorithm>
#include <ctime>
#include <cstdio>

#include "config.h"
#include "models.h"
#include "time_service.h"

ScheduleService::ScheduleService(TimeService& clock,
                                 CardState* states,
                                 size_t& cardCount)
    : clock_(clock), states_(states), cardCount_(cardCount) {}

uint32_t ScheduleService::localDayStartUtc(uint32_t epoch) const {
    // O dia acadêmico do Mnemos começa às 04:00 locais, conforme o
    // contrato compartilhado. Assim, por exemplo, 02:30 pertence ao
    // dia acadêmico anterior.
    const int64_t local =
        static_cast<int64_t>(epoch) +
        static_cast<int64_t>(Config::GMT_OFFSET_SECONDS) +
        static_cast<int64_t>(Config::DAYLIGHT_OFFSET_SECONDS);

    const int64_t cutoffSeconds =
        static_cast<int64_t>(Config::DAY_CUTOFF_HOUR) * 3600LL;

    const int64_t shifted = local - cutoffSeconds;
    const int64_t dayStartLocal =
        (shifted / 86400LL) * 86400LL + cutoffSeconds;

    const int64_t utc =
        dayStartLocal -
        static_cast<int64_t>(Config::GMT_OFFSET_SECONDS) -
        static_cast<int64_t>(Config::DAYLIGHT_OFFSET_SECONDS);

    return utc > 0 ? static_cast<uint32_t>(utc) : 0U;
}

ScheduleOverview ScheduleService::snapshot() const {
    ScheduleOverview result;
    const uint32_t nowEpoch = clock_.now();
    const uint32_t todayStart = localDayStartUtc(nowEpoch);
    const uint32_t tomorrowStart = todayStart + 86400U;
    const uint32_t dayAfterTomorrowStart = tomorrowStart + 86400U;
    const uint32_t sevenDaysEnd = todayStart + 7U * 86400U;

    for (size_t i = 0; i < cardCount_; ++i) {
        const CardState& state = states_[i];
        if (state.dueAt == 0) {
            ++result.newCards;
            continue;
        }
        if (state.dueAt <= nowEpoch) {
            ++result.dueNow;
            continue;
        }

        if (result.nextReviewAt == 0 || state.dueAt < result.nextReviewAt) {
            result.nextReviewAt = state.dueAt;
        }
        if (state.dueAt < tomorrowStart) ++result.laterToday;
        if (state.dueAt >= tomorrowStart && state.dueAt < dayAfterTomorrowStart) ++result.tomorrow;
        if (state.dueAt < sevenDaysEnd) ++result.next7Days;
    }
    return result;
}

String ScheduleService::localClock(uint32_t epoch) const {
    time_t shifted = static_cast<time_t>(epoch) + Config::GMT_OFFSET_SECONDS + Config::DAYLIGHT_OFFSET_SECONDS;
    tm value{};
    gmtime_r(&shifted, &value);
    char buffer[8];
    std::snprintf(buffer, sizeof(buffer), "%02d:%02d", value.tm_hour, value.tm_min);
    return String(buffer);
}

String ScheduleService::weekdayName(uint32_t epoch) const {
    static const char* NAMES[] = {
        "domingo", "segunda", "terca", "quarta", "quinta", "sexta", "sabado"
    };
    time_t shifted = static_cast<time_t>(epoch) + Config::GMT_OFFSET_SECONDS + Config::DAYLIGHT_OFFSET_SECONDS;
    tm value{};
    gmtime_r(&shifted, &value);
    if (value.tm_wday < 0 || value.tm_wday > 6) return "";
    return String(NAMES[value.tm_wday]);
}

String ScheduleService::humanize(uint32_t targetEpoch) const {
    if (targetEpoch == 0) return "Sem revisao agendada";

    const uint32_t nowEpoch = clock_.now();
    if (targetEpoch <= nowEpoch) return "agora";

    const uint32_t diff = targetEpoch - nowEpoch;
    if (diff < 120U) return "em " + String(diff) + " s";
    if (diff < 3600U) return "em " + String((diff + 30U) / 60U) + " min";

    const uint32_t todayStart = localDayStartUtc(nowEpoch);
    const uint32_t targetStart = localDayStartUtc(targetEpoch);
    const uint32_t dayDelta = targetStart >= todayStart ? (targetStart - todayStart) / 86400U : 0U;

    if (dayDelta == 0U) return "hoje as " + localClock(targetEpoch);
    if (dayDelta == 1U) return "amanha as " + localClock(targetEpoch);
    if (dayDelta < 7U) return weekdayName(targetEpoch) + " as " + localClock(targetEpoch);

    time_t shifted = static_cast<time_t>(targetEpoch) + Config::GMT_OFFSET_SECONDS + Config::DAYLIGHT_OFFSET_SECONDS;
    tm value{};
    gmtime_r(&shifted, &value);
    char buffer[20];
    std::snprintf(buffer, sizeof(buffer), "%02d/%02d as %02d:%02d",
                  value.tm_mday, value.tm_mon + 1, value.tm_hour, value.tm_min);
    return String(buffer);
}
