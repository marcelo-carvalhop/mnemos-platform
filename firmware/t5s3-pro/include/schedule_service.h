#pragma once

#include <Arduino.h>
#include <cstddef>

class TimeService;
struct CardState;

struct ScheduleOverview {
    uint16_t dueNow = 0;       // revisoes ja agendadas e vencidas
    uint16_t newCards = 0;     // cards nunca introduzidos (dueAt == 0)
    uint16_t laterToday = 0;
    uint16_t tomorrow = 0;
    uint16_t next7Days = 0;
    uint32_t nextReviewAt = 0;
};

class ScheduleService {
public:
    ScheduleService(TimeService& clock,
                    CardState* states,
                    size_t& cardCount);

    ScheduleOverview snapshot() const;
    String humanize(uint32_t targetEpoch) const;

private:
    TimeService& clock_;
    CardState* states_;
    size_t& cardCount_;

    uint32_t localDayStartUtc(uint32_t epoch) const;
    String localClock(uint32_t epoch) const;
    String weekdayName(uint32_t epoch) const;
};
