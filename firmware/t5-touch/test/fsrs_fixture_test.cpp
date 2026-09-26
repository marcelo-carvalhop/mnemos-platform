#include "fsrs_engine.h"

#include <cmath>
#include <iostream>

struct FixtureCase {
    const char* name;
    const uint8_t* grades;
    size_t gradeCount;

    double stability;
    double difficulty;

    uint64_t dueAtMs;

    uint32_t reps;
    uint32_t lapses;

    FsrsPhase phase;
    int8_t step;
};

bool near(
    double actual,
    double expected) {

    return std::abs(
        actual - expected) < 1e-10;
}

int main() {

    static const uint8_t c1[] =
        {3, 3, 3, 3};

    static const uint8_t c2[] =
        {4, 4, 4};

    static const uint8_t c3[] =
        {1, 1, 1};

    static const uint8_t c4[] =
        {3, 3, 4, 1, 3};

    static const uint8_t c5[] =
        {3, 2, 3, 2, 4};

    static const uint8_t c6[] =
        {3};

    static const uint8_t c7[] =
        {1, 3, 3};

    static const uint8_t c8[] =
        {1, 4, 1, 4};


    const FixtureCase cases[] = {

        {
            "tudo bom",
            c1, 4,
            12.481400121197694,
            4.835248553486574,
            1768554000000ULL,
            4, 0,
            FsrsPhase::Review,
            -1
        },

        {
            "sempre facil",
            c2, 3,
            41.3016854395998,
            1.0,
            1770973200000ULL,
            3, 0,
            FsrsPhase::Review,
            -1
        },

        {
            "sempre errei",
            c3, 3,
            0.12951890215029835,
            9.079839127100223,
            1767430860000ULL,
            3, 0,
            FsrsPhase::Learning,
            0
        },

        {
            "recaida depois de graduar",
            c4, 5,
            4.574476102153924,
            6.559340121764769,
            1768035600000ULL,
            5, 1,
            FsrsPhase::Review,
            -1
        },

        {
            "dificil no meio",
            c5, 5,
            13.127553499744009,
            6.178766779134129,
            1768726800000ULL,
            5, 0,
            FsrsPhase::Review,
            -1
        },

        {
            "um so",
            c6, 1,
            3.2602,
            4.884631634813845,
            1767258600000ULL,
            1, 0,
            FsrsPhase::Learning,
            1
        },

        {
            "errei primeiro",
            c7, 3,
            3.6385529324112986,
            6.949115955464738,
            1767776400000ULL,
            3, 0,
            FsrsPhase::Review,
            -1
        },

        {
            "alternando",
            c8, 4,
            5.613852942530018,
            7.474332732857223,
            1768035600000ULL,
            4, 1,
            FsrsPhase::Review,
            -1
        },
    };


    constexpr uint64_t START_MS =
        1767258000000ULL;

    constexpr uint64_t DAY_MS =
        86400000ULL;


    for (const FixtureCase& fixture : cases) {

        FsrsState state =
            FsrsEngine::fresh(START_MS);

        for (
            size_t i = 0;
            i < fixture.gradeCount;
            ++i
        ) {

            state =
                FsrsEngine::apply(
                    state,
                    fixture.grades[i],
                    START_MS +
                        i * DAY_MS);
        }


        const bool ok =
            near(
                state.stability,
                fixture.stability)
            &&
            near(
                state.difficulty,
                fixture.difficulty)
            &&
            state.dueAtMs ==
                fixture.dueAtMs
            &&
            state.reps ==
                fixture.reps
            &&
            state.lapses ==
                fixture.lapses
            &&
            state.phase ==
                fixture.phase
            &&
            state.step ==
                fixture.step;


        std::cout
            << (ok ? "PASS " : "FAIL ")
            << fixture.name
            << '\n';


        if (!ok) {

            std::cerr
                << "  stability: "
                << state.stability
                << '\n'
                << "  difficulty: "
                << state.difficulty
                << '\n'
                << "  dueAtMs: "
                << state.dueAtMs
                << '\n'
                << "  reps: "
                << state.reps
                << '\n'
                << "  lapses: "
                << state.lapses
                << '\n'
                << "  step: "
                << static_cast<int>(
                    state.step)
                << '\n';

            return 1;
        }
    }


    std::cout
        << "FSRS fixtures: all passed\n";

    return 0;
}
