#include "bq27220.h"
#include "bq27220_data_memory.h"

#define BQ27220_ID (0x0220u)

/** Delay between 2 writes into Subclass/MAC area. Fails at ~120us. */
#define BQ27220_MAC_WRITE_DELAY_US (250u)

/** Delay between we ask chip to load data to MAC and it become valid. Fails at ~500us. */
#define BQ27220_SELECT_DELAY_US (15000u)

/** Delay between 2 control operations(like unseal or full access). Fails at ~2500us.*/
#define BQ27220_MAGIC_DELAY_US (5000u)

/** Delay before freshly written configuration can be read. Fails at ? */
#define BQ27220_CONFIG_DELAY_US (10000u)

/** Config apply delay. Must wait, or DM read returns garbage. */
#define BQ27220_CONFIG_APPLY_US (2000000u)

/** Timeout for common operations. */
#define BQ27220_TIMEOUT_COMMON_US (2000000u)

/** Timeout for reset operation. Normally reset takes ~2s. */
#define BQ27220_TIMEOUT_RESET_US (4000000u)

/** Timeout cycle interval  */
#define BQ27220_TIMEOUT_CYCLE_INTERVAL_US (1000u)

/** Timeout cycles count helper */
#define BQ27220_TIMEOUT(timeout_us) ((timeout_us) / (BQ27220_TIMEOUT_CYCLE_INTERVAL_US))

static uint8_t bq27220_get_checksum(uint8_t* data, uint16_t len) {
    uint8_t ret = 0;
    for(uint16_t i = 0; i < len; i++) {
        ret += data[i];
    }
    return 0xFF - ret;
}

bool BQ27220::parameterCheck(uint16_t address, uint32_t value, size_t size, bool update)
{
    if(!(size == 1 || size == 2 || size == 4)) {
        Serial.printf("(%d) Parameter size error\n", __LINE__);
        return false;
    }

    bool ret = false;
    uint8_t buffer[6] = {0};
    uint8_t old_data[4] = {0};

    do {
        buffer[0] = address & 0xFF;
        buffer[1] = (address >> 8) & 0xFF;

        for(size_t i = 0; i < size; i++) {
            buffer[1 + size - i] = (value >> (i * 8)) & 0xFF;
        }

        if(update) {
            if(!i2cWriteBytes(CommandSelectSubclass, buffer, size + 2)) {
                Serial.printf("(%d) DM write failed\n", __LINE__);
                break;
            }
            // We must wait, otherwise write will fail
            delayMicroseconds(BQ27220_MAC_WRITE_DELAY_US);

            // Calculate the check sum: 0xFF - (sum of address and data) OR 0xFF
            uint8_t checksum = bq27220_get_checksum(buffer, size + 2);
            // Write the check sum to 0x60 and the total length of (address + parameter data + check sum + length) to 0x61
            buffer[0] = checksum;
            // 2 bytes address, `size` bytes data, 1 byte check sum, 1 byte length
            buffer[1] = 2 + size + 1 + 1;
            if(!i2cWriteBytes(CommandMACDataSum, buffer, 2)) {
                Serial.printf("(%d) CRC write failed\n", __LINE__);
                break;
            }
            // We must wait, otherwise write will fail
            delayMicroseconds(BQ27220_CONFIG_DELAY_US);
            ret = true;
        } else {
            if(!i2cWriteBytes(CommandSelectSubclass, buffer, 2)) {
                Serial.printf("(%d) DM SelectSubclass for read failed\n", __LINE__);
                break;
            }
            // bqstudio uses 15ms wait delay here
            delayMicroseconds(BQ27220_SELECT_DELAY_US);

            if(!i2cReadBytes(CommandMACData, old_data, size)) {
                Serial.printf("(%d) DM read failed\n", __LINE__);
                break;
            }
            // bqstudio uses burst reads with continue(CommandSelectSubclass without argument) and ~5ms between burst
            delayMicroseconds(BQ27220_SELECT_DELAY_US);

            if(*(uint32_t*)&(old_data[0]) != *(uint32_t*)&(buffer[2])) {
                Serial.printf(
                    "(%d) Data at 0x%04x(%zu): 0x%08lx!=0x%08lx\n", __LINE__,
                    address,
                    size,
                    *(uint32_t*)&(old_data[0]),
                    *(uint32_t*)&(buffer[2]));
            } else {
                ret = true;
            }
        }
    } while(0);

    return ret;
}

bool BQ27220::dateMemoryCheck(
    const BQ27220DMData *data_memory,
    bool update)
{
    if (update) {
        /*
         * TI BQ27220 TRM: ENTER_CFG_UPDATE is a Control()
         * subcommand (0x0090). Do not send it to 0x3E.
         *
         * Device must already be UNSEALED/FULL ACCESS.
         */
        if (
            !controlSubCmd(
                Control_ENTER_CFG_UPDATE)
        ) {
            Serial.println(
                "[bq27220] ENTER_CFG_UPDATE write failed");
            return false;
        }

        /*
         * TI allows up to ~1 s to enter CFGUPDATE.
         * Poll for up to 2 s with a small initial settling delay.
         */
        delay(20);

        uint32_t timeout =
            BQ27220_TIMEOUT(
                BQ27220_TIMEOUT_COMMON_US);

        BQ27220OperationStatus operation_status = {};

        while (--timeout > 0) {
            if (
                getOperationStatus(
                    &operation_status)
                &&
                operation_status.reg.CFGUPDATE
            ) {
                break;
            }

            delayMicroseconds(
                BQ27220_TIMEOUT_CYCLE_INTERVAL_US);
        }

        if (timeout == 0) {
            Serial.printf(
                "[bq27220] ENTER_CFG_UPDATE timeout "
                "CFG=%u SEC=%u\n",
                operation_status.reg.CFGUPDATE,
                operation_status.reg.SEC);
            return false;
        }

        Serial.printf(
            "[bq27220] CFGUPDATE entered SEC=%u\n",
            operation_status.reg.SEC);
    }

    bool result = true;

    while (
        data_memory->type !=
        BQ27220DMTypeEnd
    ) {
        bool itemResult = true;

        if (
            data_memory->type ==
            BQ27220DMTypeWait
        ) {
            delayMicroseconds(
                data_memory->value.u32);
        } else if (
            data_memory->type ==
            BQ27220DMTypeU8
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    data_memory->value.u8,
                    1,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypeU16
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    data_memory->value.u16,
                    2,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypeU32
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    data_memory->value.u32,
                    4,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypeI8
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    static_cast<uint32_t>(
                        data_memory->value.i8),
                    1,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypeI16
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    static_cast<uint32_t>(
                        static_cast<uint16_t>(
                            data_memory->value.i16)),
                    2,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypeI32
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    static_cast<uint32_t>(
                        data_memory->value.i32),
                    4,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypeF32
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    data_memory->value.u32,
                    4,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypePtr8
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    *reinterpret_cast<uint8_t *>(
                        data_memory->value.u32),
                    1,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypePtr16
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    *reinterpret_cast<uint16_t *>(
                        data_memory->value.u32),
                    2,
                    update);
        } else if (
            data_memory->type ==
            BQ27220DMTypePtr32
        ) {
            itemResult =
                parameterCheck(
                    data_memory->address,
                    *reinterpret_cast<uint32_t *>(
                        data_memory->value.u32),
                    4,
                    update);
        } else {
            Serial.println(
                "[bq27220] invalid Data Memory type");
            itemResult = false;
        }

        result =
            result &&
            itemResult;

        data_memory++;
    }

    if (update) {
        /*
         * Even if one item failed, leave CFGUPDATE cleanly.
         */
        if (
            !controlSubCmd(
                Control_EXIT_CFG_UPDATE_REINIT)
        ) {
            Serial.println(
                "[bq27220] EXIT_CFG_UPDATE_REINIT "
                "write failed");
            return false;
        }

        delayMicroseconds(
            BQ27220_CONFIG_APPLY_US);

        uint32_t timeout =
            BQ27220_TIMEOUT(
                BQ27220_TIMEOUT_COMMON_US);

        BQ27220OperationStatus operation_status = {};

        while (--timeout > 0) {
            if (
                getOperationStatus(
                    &operation_status)
                &&
                !operation_status.reg.CFGUPDATE
                &&
                operation_status.reg.INITCOMP
            ) {
                break;
            }

            delayMicroseconds(
                BQ27220_TIMEOUT_CYCLE_INTERVAL_US);
        }

        if (timeout == 0) {
            Serial.printf(
                "[bq27220] exit CFGUPDATE timeout "
                "INITCOMP=%u CFG=%u SEC=%u\n",
                operation_status.reg.INITCOMP,
                operation_status.reg.CFGUPDATE,
                operation_status.reg.SEC);
            return false;
        }

        Serial.printf(
            "[bq27220] CFGUPDATE exited "
            "INITCOMP=%u SEC=%u\n",
            operation_status.reg.INITCOMP,
            operation_status.reg.SEC);
    }

    return result;
}

bool BQ27220::init(
    const BQ27220DMData *data_memory)
{
    const uint16_t deviceNumber =
        getDeviceNumber();

    if (
        deviceNumber !=
        BQ27220_ID
    ) {
        Serial.printf(
            "[bq27220] invalid device 0x%04X "
            "expected=0x0220\n",
            deviceNumber);
        return false;
    }

    /*
     * RESET is intentionally NOT part of profile provisioning.
     *
     * The TI Data Memory update procedure is:
     * UNSEAL -> FULL ACCESS -> ENTER_CFG_UPDATE ->
     * write/verify DM -> EXIT_CFG_UPDATE_REINIT -> SEAL.
     *
     * Resetting here can change the security state between
     * validation and provisioning and is unnecessary.
     */
    BQ27220OperationStatus operationStatus = {};

    if (
        !getOperationStatus(
            &operationStatus)
    ) {
        Serial.println(
            "[bq27220] operation status unavailable");
        return false;
    }

    if (
        !operationStatus.reg.INITCOMP ||
        operationStatus.reg.CFGUPDATE
    ) {
        Serial.printf(
            "[bq27220] unsafe initial state "
            "INITCOMP=%u CFG=%u SEC=%u\n",
            operationStatus.reg.INITCOMP,
            operationStatus.reg.CFGUPDATE,
            operationStatus.reg.SEC);
        return false;
    }

    if (!unsealAccess()) {
        Serial.println(
            "[bq27220] unseal failed");
        return false;
    }

    BQ27220ControlStatus controlStatus = {};

    if (
        !getControlStatus(
            &controlStatus)
    ) {
        Serial.println(
            "[bq27220] control status unavailable");
        sealAccess();
        return false;
    }

    if (
        controlStatus.reg.BATT_ID !=
        0
    ) {
        Serial.printf(
            "[bq27220] unexpected CEDV profile "
            "BATT_ID=%u\n",
            controlStatus.reg.BATT_ID);
        sealAccess();
        return false;
    }

    Serial.println(
        "[bq27220] validating Data Memory");

    if (
        dateMemoryCheck(
            data_memory,
            false)
    ) {
        const bool sealed =
            sealAccess();

        Serial.printf(
            "[bq27220] profile already valid "
            "seal=%d\n",
            sealed ? 1 : 0);

        return sealed;
    }

    Serial.println(
        "[bq27220] profile mismatch; "
        "provisioning Data Memory");

    if (!fullAccess()) {
        Serial.println(
            "[bq27220] full access failed");
        sealAccess();
        return false;
    }

    if (
        !dateMemoryCheck(
            data_memory,
            true)
    ) {
        Serial.println(
            "[bq27220] Data Memory write failed");
        sealAccess();
        return false;
    }

    Serial.println(
        "[bq27220] verifying Data Memory");

    if (
        !dateMemoryCheck(
            data_memory,
            false)
    ) {
        Serial.println(
            "[bq27220] Data Memory verify failed");
        sealAccess();
        return false;
    }

    const bool sealed =
        sealAccess();

    Serial.printf(
        "[bq27220] profile provisioned "
        "seal=%d\n",
        sealed ? 1 : 0);

    return sealed;
}

bool BQ27220::reset(void)
{
    bool result = false;
    do{
        controlSubCmd(Control_RESET);
        // delay(10);

        uint32_t timeout = BQ27220_TIMEOUT(BQ27220_TIMEOUT_RESET_US);
        BQ27220OperationStatus operat = {0};
        while (--timeout > 0)
        {
            if(!getOperationStatus(&operat)){
                Serial.printf("Failed to get operation status, retries left %lu\n", timeout);
            }else if(operat.reg.INITCOMP == true){
                break;
            }
            delayMicroseconds(BQ27220_TIMEOUT_CYCLE_INTERVAL_US); // delay(2);
        }
        if(timeout == 0) {
            Serial.println("INITCOMP timeout after reset");
            break;
        }
        Serial.printf("(%d) Cycles left: %lu\n", __LINE__, timeout);
        result = true;
    } while(0);
    return result;
}

// Sealed Access
bool BQ27220::sealAccess(void)
{
    bool result = false;
    BQ27220OperationStatus operat = {0};
    do{
        if(!getOperationStatus(&operat)) {
            Serial.println("Seal: status query failed");
            break;
        }
        if(operat.reg.SEC == Bq27220OperationStatusSecSealed)
        {
            result = true;
            break;
        }

        controlSubCmd(Control_SEALED);
        // delay(10);
        delayMicroseconds(BQ27220_SELECT_DELAY_US);

        if(!getOperationStatus(&operat)) {
            Serial.println("Seal: status query failed");
            break;
        }
        if(operat.reg.SEC != Bq27220OperationStatusSecSealed)
        {
            Serial.printf("Seal failed %u\n", operat.reg.SEC);
            break;
        }
        result = true;
    } while(0);

    return result;
}

bool BQ27220::unsealAccess(void)
{
    bool result = false;
    BQ27220OperationStatus operat = {0};
    do{
        if(!getOperationStatus(&operat)) {
            Serial.println("Unseal: status query failed");
            break;
        }
        if(operat.reg.SEC != Bq27220OperationStatusSecSealed)
        {
            result = true;
            break;
        }

        controlSubCmd(UnsealKey1);
        delayMicroseconds(BQ27220_MAGIC_DELAY_US); // delay(10);
        controlSubCmd(UnsealKey2);
        delayMicroseconds(BQ27220_MAGIC_DELAY_US);  // delay(10);

        if(!getOperationStatus(&operat)) {
            Serial.println("Unseal: status query failed");
            break;
        }
        if(operat.reg.SEC != Bq27220OperationStatusSecUnsealed)
        {
            Serial.printf("Unseal failed %u\n", operat.reg.SEC);
            break;
        }
        result = true;
    } while (0);

    return result;
}

bool BQ27220::fullAccess(void)
{
    bool result = false;
    BQ27220OperationStatus operat = {0};

    do{
        uint32_t timeout = BQ27220_TIMEOUT(BQ27220_TIMEOUT_COMMON_US);
        while (--timeout > 0)
        {
            if(!getOperationStatus(&operat)){
                Serial.printf("Failed to get operation status, retries left %lu\n", timeout);
            }else {
                break;
            }
            delayMicroseconds(BQ27220_TIMEOUT_CYCLE_INTERVAL_US);
        }
        if(timeout == 0) {
            Serial.println("Failed to get operation status");
            break;
        }
        // Serial.printf("Cycles left: %lu\n", timeout);

        // Already full access
        if(operat.reg.SEC == Bq27220OperationStatusSecFull){
            result = true;
            break;
        }
        // Must be unsealed to get full access
        if(operat.reg.SEC != Bq27220OperationStatusSecUnsealed){
            Serial.printf("(%d) Not in unsealed state\n", __LINE__);
            break;
        }

        controlSubCmd(FullAccessKey);
        delayMicroseconds(BQ27220_MAGIC_DELAY_US); //delay(10);
        controlSubCmd(FullAccessKey);
        delayMicroseconds(BQ27220_MAGIC_DELAY_US); //delay(10);

        if(!getOperationStatus(&operat)){
            Serial.println("Status query failed");
            break;
        }
        if(operat.reg.SEC != Bq27220OperationStatusSecFull){
            Serial.printf("Full access failed %u\n", operat.reg.SEC);
            break;
        }
        result = true;
    } while (0);
    return result;
}

uint16_t BQ27220::getDeviceNumber(void)
{
    for (
        uint8_t attempt = 0;
        attempt < 3;
        ++attempt
    ) {
        if (
            !controlSubCmd(
                Control_DEVICE_NUMBER)
        ) {
            delay(5);
            continue;
        }

        delayMicroseconds(
            BQ27220_SELECT_DELAY_US);

        uint8_t response[4] = {
            0xFF,
            0xFF,
            0xFF,
            0xFF
        };

        if (
            !i2cReadBytes(
                CommandSelectSubclass,
                response,
                sizeof(response))
        ) {
            delay(5);
            continue;
        }

        const uint16_t echoedSubcommand =
            static_cast<uint16_t>(
                response[0]) |
            (
                static_cast<uint16_t>(
                    response[1])
                << 8
            );

        const uint16_t deviceNumber =
            static_cast<uint16_t>(
                response[2]) |
            (
                static_cast<uint16_t>(
                    response[3])
                << 8
            );

        if (
            echoedSubcommand ==
            Control_DEVICE_NUMBER
        ) {
            return deviceNumber;
        }

        delay(5);
    }

    return 0xFFFFU;
}

uint16_t BQ27220::getVoltage(void)
{
    return readRegU16(CommandVoltage);
}
int16_t BQ27220::getCurrent(void)
{
    return readRegU16(CommandCurrent);
}
bool BQ27220::getControlStatus(BQ27220ControlStatus *ctrl_sta)
{
    uint16_t value = 0;
    if(!readRegU16(CommandControl, value)) {
        return false;
    }
    (*ctrl_sta).full = value;
    return true;
}
bool BQ27220::getBatteryStatus(BQ27220BatteryStatus *batt_sta)
{
    uint16_t value = 0;
    if(!readRegU16(CommandBatteryStatus, value)) {
        return false;
    }
    (*batt_sta).full = value;
    return true;
}
bool BQ27220::getOperationStatus(BQ27220OperationStatus *oper_sta)
{
    uint16_t value = 0;
    if(!readRegU16(CommandOperationStatus, value)) {
        return false;
    }
    (*oper_sta).full = value;
    return true;
}
bool BQ27220::getGaugingStatus(BQ27220GaugingStatus *gauging_sta)
{
    // Request gauging data to be loaded to MAC
    if(!controlSubCmd(Control_GAUGING_STATUS)) {
        return false;
    }
    // Wait for data being loaded to MAC
    delayMicroseconds(BQ27220_SELECT_DELAY_US);
    // Read id data from MAC scratch space
    uint16_t value = 0;
    if(!readRegU16(CommandMACData, value)) {
        return false;
    }
    (*gauging_sta).full = value;
    return true;
}
uint16_t BQ27220::getTemperature(void)
{
    return readRegU16(CommandTemperature);
}
uint16_t BQ27220::getFullChargeCapacity(void)
{
    return readRegU16(CommandFullChargeCapacity);
}
uint16_t BQ27220::getDesignCapacity(void)
{
    return readRegU16(CommandDesignCapacity);
}
uint16_t BQ27220::getRemainingCapacity(void)
{
    return readRegU16(CommandRemainingCapacity);
}
uint16_t BQ27220::getStateOfCharge(void)
{
    return readRegU16(CommandStateOfCharge);
}
uint16_t BQ27220::getStateOfHealth(void)
{
    return readRegU16(CommandStateOfHealth);
}
uint16_t BQ27220::getChargeVoltageMax(void)
{
    return readRegU16(CommandChargeVoltage);
}
