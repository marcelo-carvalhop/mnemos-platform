#include <unity.h>

#include <Wire.h>

#include "battery_service.h"

namespace {

bool externalPower = false;

bool externalPowerProbe() {
    return externalPower;
}

void useTrustedProfile() {
    test_support::gauge.designMah = Config::BATTERY_DESIGN_CAPACITY_MAH;
    test_support::gauge.fullMah = 1480;
    test_support::gauge.remainingMah = 900;
}

// Avança um intervalo de amostragem com a leitura informada.
void sample(
    BatteryService& battery,
    uint16_t millivolts,
    int16_t currentMa,
    bool vbus) {

    test_support::gauge.millivolts = millivolts;
    test_support::gauge.currentMa = currentMa;
    externalPower = vbus;
    test_support::millisValue += Config::BATTERY_SAMPLE_INTERVAL_MS;
    battery.update();
}

}  // namespace

void setUp() {
    test_support::gauge = test_support::GaugeSim{};
    test_support::millisValue = 1000;
    test_support::i2cAck = true;
    externalPower = false;
}

void tearDown() {}

void test_mismatched_profile_uses_voltage_estimate() {
    BatteryService battery;

    TEST_ASSERT_TRUE(battery.begin(externalPowerProbe));
    TEST_ASSERT_TRUE(battery.available());
    TEST_ASSERT_EQUAL(
        static_cast<int>(BatteryGaugeTrust::ProfileUntrusted),
        static_cast<int>(battery.trust()));

    // 3,85 V a -150 mA compensa para ~3,868 V: 60% na curva, não o SOC 22 do gauge.
    TEST_ASSERT_EQUAL_UINT8(60, battery.percent());
}

void test_voltage_recovery_does_not_raise_percent_on_battery() {
    BatteryService battery;
    battery.begin(externalPowerProbe);

    sample(battery, 3700, -400, false);
    const uint8_t afterPeak = battery.percent();
    TEST_ASSERT_LESS_THAN_UINT8(60, afterPeak);

    sample(battery, 3850, -150, false);
    sample(battery, 3850, -150, false);
    TEST_ASSERT_EQUAL_UINT8(afterPeak, battery.percent());
}

void test_charge_raises_percent_with_external_power() {
    BatteryService battery;
    battery.begin(externalPowerProbe);
    const uint8_t start = battery.percent();

    for (uint16_t mv = 3950; mv <= 4150; mv += 50) {
        sample(battery, mv, 900, true);
    }

    TEST_ASSERT_TRUE(battery.charging());
    TEST_ASSERT_GREATER_THAN_UINT8(start, battery.percent());
}

void test_single_low_sample_is_not_critical() {
    BatteryService battery;
    battery.begin(externalPowerProbe);

    sample(battery, 3420, -150, false);
    TEST_ASSERT_FALSE(battery.critical());

    sample(battery, 3800, -150, false);
    TEST_ASSERT_FALSE(battery.critical());
}

void test_consecutive_low_samples_are_critical_on_battery() {
    BatteryService battery;
    battery.begin(externalPowerProbe);

    sample(battery, 3400, -150, false);
    TEST_ASSERT_FALSE(battery.critical());

    sample(battery, 3400, -150, false);
    TEST_ASSERT_TRUE(battery.critical());
}

void test_external_power_is_never_critical() {
    BatteryService battery;
    battery.begin(externalPowerProbe);

    sample(battery, 3400, 0, true);
    sample(battery, 3400, 0, true);
    sample(battery, 3400, 0, true);
    TEST_ASSERT_FALSE(battery.critical());
}

void test_untrusted_soc_never_triggers_critical() {
    test_support::gauge.soc = 3;

    BatteryService battery;
    battery.begin(externalPowerProbe);

    sample(battery, 3950, -120, false);
    sample(battery, 3950, -120, false);
    TEST_ASSERT_FALSE(battery.critical());
}

void test_trusted_profile_uses_gauge_soc() {
    useTrustedProfile();
    test_support::gauge.soc = 61;

    BatteryService battery;
    battery.begin(externalPowerProbe);

    TEST_ASSERT_EQUAL(
        static_cast<int>(BatteryGaugeTrust::ProfileTrusted),
        static_cast<int>(battery.trust()));
    TEST_ASSERT_EQUAL_UINT8(60, battery.percent());
}

void test_trusted_low_soc_is_critical() {
    useTrustedProfile();
    test_support::gauge.soc = 61;

    BatteryService battery;
    battery.begin(externalPowerProbe);

    test_support::gauge.soc = 4;
    sample(battery, 3620, -100, false);
    sample(battery, 3620, -100, false);
    TEST_ASSERT_TRUE(battery.critical());
}

void test_gauge_lost_after_three_failures_is_identified_again() {
    BatteryService battery;
    battery.begin(externalPowerProbe);

    test_support::gauge.online = false;
    test_support::i2cAck = false;

    sample(battery, 0, 0, false);
    sample(battery, 0, 0, false);
    TEST_ASSERT_TRUE(battery.available());

    sample(battery, 0, 0, false);
    TEST_ASSERT_FALSE(battery.available());
    TEST_ASSERT_EQUAL(
        static_cast<int>(BatteryGaugeTrust::Absent),
        static_cast<int>(battery.trust()));

    test_support::gauge.online = true;
    test_support::i2cAck = true;

    sample(battery, 3900, -100, false);
    TEST_ASSERT_TRUE(battery.available());
    TEST_ASSERT_EQUAL(
        static_cast<int>(BatteryGaugeTrust::ProfileUntrusted),
        static_cast<int>(battery.trust()));
}

void test_absent_gauge_reports_unavailable() {
    test_support::gauge.online = false;
    test_support::i2cAck = false;

    BatteryService battery;

    TEST_ASSERT_FALSE(battery.begin(externalPowerProbe));
    TEST_ASSERT_FALSE(battery.available());
    TEST_ASSERT_FALSE(battery.critical());
    TEST_ASSERT_EQUAL(
        static_cast<int>(BatteryGaugeTrust::Absent),
        static_cast<int>(battery.trust()));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_mismatched_profile_uses_voltage_estimate);
    RUN_TEST(test_voltage_recovery_does_not_raise_percent_on_battery);
    RUN_TEST(test_charge_raises_percent_with_external_power);
    RUN_TEST(test_single_low_sample_is_not_critical);
    RUN_TEST(test_consecutive_low_samples_are_critical_on_battery);
    RUN_TEST(test_external_power_is_never_critical);
    RUN_TEST(test_untrusted_soc_never_triggers_critical);
    RUN_TEST(test_trusted_profile_uses_gauge_soc);
    RUN_TEST(test_trusted_low_soc_is_critical);
    RUN_TEST(test_gauge_lost_after_three_failures_is_identified_again);
    RUN_TEST(test_absent_gauge_reports_unavailable);
    return UNITY_END();
}
