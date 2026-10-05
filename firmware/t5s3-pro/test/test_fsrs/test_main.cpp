#include <unity.h>

#include "fsrs_engine.h"

namespace {

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

constexpr uint64_t START_MS = 1767258000000ULL;
constexpr uint64_t DAY_MS = 86400000ULL;
constexpr double TOLERANCE = 1e-10;

constexpr uint8_t ALL_GOOD[] = {3, 3, 3, 3};
constexpr uint8_t ALL_EASY[] = {4, 4, 4};
constexpr uint8_t ALL_AGAIN[] = {1, 1, 1};
constexpr uint8_t LAPSE_AFTER_GRADUATION[] = {3, 3, 4, 1, 3};
constexpr uint8_t HARD_IN_THE_MIDDLE[] = {3, 2, 3, 2, 4};
constexpr uint8_t SINGLE_GOOD[] = {3};
constexpr uint8_t AGAIN_FIRST[] = {1, 3, 3};
constexpr uint8_t ALTERNATING[] = {1, 4, 1, 4};

// Valores de referência do FSRS para uma revisão por dia a partir de START_MS.
const FixtureCase CASES[] = {
    {"tudo bom", ALL_GOOD, 4,
     12.481400121197694, 4.835248553486574, 1768554000000ULL,
     4, 0, FsrsPhase::Review, -1},
    {"sempre facil", ALL_EASY, 3,
     41.3016854395998, 1.0, 1770973200000ULL,
     3, 0, FsrsPhase::Review, -1},
    {"sempre errei", ALL_AGAIN, 3,
     0.12951890215029835, 9.079839127100223, 1767430860000ULL,
     3, 0, FsrsPhase::Learning, 0},
    {"recaida depois de graduar", LAPSE_AFTER_GRADUATION, 5,
     4.574476102153924, 6.559340121764769, 1768035600000ULL,
     5, 1, FsrsPhase::Review, -1},
    {"dificil no meio", HARD_IN_THE_MIDDLE, 5,
     13.127553499744009, 6.178766779134129, 1768726800000ULL,
     5, 0, FsrsPhase::Review, -1},
    {"um so", SINGLE_GOOD, 1,
     3.2602, 4.884631634813845, 1767258600000ULL,
     1, 0, FsrsPhase::Learning, 1},
    {"errei primeiro", AGAIN_FIRST, 3,
     3.6385529324112986, 6.949115955464738, 1767776400000ULL,
     3, 0, FsrsPhase::Review, -1},
    {"alternando", ALTERNATING, 4,
     5.613852942530018, 7.474332732857223, 1768035600000ULL,
     4, 1, FsrsPhase::Review, -1},
};

void checkFixture(const FixtureCase& fixture) {
    FsrsState state = FsrsEngine::fresh(START_MS);

    for (size_t i = 0; i < fixture.gradeCount; ++i) {
        state = FsrsEngine::apply(
            state,
            fixture.grades[i],
            START_MS + i * DAY_MS);
    }

    TEST_ASSERT_DOUBLE_WITHIN_MESSAGE(
        TOLERANCE, fixture.stability, state.stability, fixture.name);
    TEST_ASSERT_DOUBLE_WITHIN_MESSAGE(
        TOLERANCE, fixture.difficulty, state.difficulty, fixture.name);
    TEST_ASSERT_EQUAL_UINT64_MESSAGE(
        fixture.dueAtMs, state.dueAtMs, fixture.name);
    TEST_ASSERT_EQUAL_UINT32_MESSAGE(
        fixture.reps, state.reps, fixture.name);
    TEST_ASSERT_EQUAL_UINT32_MESSAGE(
        fixture.lapses, state.lapses, fixture.name);
    TEST_ASSERT_EQUAL_INT_MESSAGE(
        static_cast<int>(fixture.phase),
        static_cast<int>(state.phase),
        fixture.name);
    TEST_ASSERT_EQUAL_INT8_MESSAGE(
        fixture.step, state.step, fixture.name);
}

}  // namespace

void setUp() {}
void tearDown() {}

void test_all_good() { checkFixture(CASES[0]); }
void test_all_easy() { checkFixture(CASES[1]); }
void test_all_again() { checkFixture(CASES[2]); }
void test_lapse_after_graduation() { checkFixture(CASES[3]); }
void test_hard_in_the_middle() { checkFixture(CASES[4]); }
void test_single_good() { checkFixture(CASES[5]); }
void test_again_first() { checkFixture(CASES[6]); }
void test_alternating() { checkFixture(CASES[7]); }

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_all_good);
    RUN_TEST(test_all_easy);
    RUN_TEST(test_all_again);
    RUN_TEST(test_lapse_after_graduation);
    RUN_TEST(test_hard_in_the_middle);
    RUN_TEST(test_single_good);
    RUN_TEST(test_again_first);
    RUN_TEST(test_alternating);
    return UNITY_END();
}
