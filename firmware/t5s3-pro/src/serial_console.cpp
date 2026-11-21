#include "serial_console.h"

#include "platform_sync_config.h"

void SerialConsole::begin() {
    buffer_.reserve(256);
}

bool SerialConsole::parseLine(const String& raw, JsonDocument& command) {
    String line = raw;
    line.trim();
    if (line.length() == 0) return false;

    command.clear();

    if (line.startsWith("{")) {
        const DeserializationError error = deserializeJson(command, line);
        if (error || !command["cmd"].is<const char*>()) {
            replyError("?", String("invalid_json: ") + error.c_str());
            command.clear();
            return false;
        }
        return true;
    }

    if (line.startsWith("mnemos ")) {
        String word = line.substring(7);
        word.trim();
        if (word.length() == 0) return false;
        command["cmd"] = word;
        return true;
    }

    // Qualquer outra entrada é ignorada: o console divide a porta com o log.
    return false;
}

bool SerialConsole::poll(JsonDocument& command) {
    if (!PlatformSync::SERIAL_CONSOLE_ENABLED) return false;

    while (Serial.available() > 0) {
        const int value = Serial.read();
        if (value < 0) break;
        const char c = static_cast<char>(value);

        if (c == '\n' || c == '\r') {
            if (overflow_) {
                overflow_ = false;
                buffer_ = "";
                replyError("?", "line_too_long");
                continue;
            }
            if (buffer_.length() == 0) continue;
            const String line = buffer_;
            buffer_ = "";
            if (parseLine(line, command)) return true;
            continue;
        }

        if (overflow_) continue;
        if (buffer_.length() >= PlatformSync::SERIAL_CONSOLE_MAX_LINE) {
            overflow_ = true;
            continue;
        }
        buffer_ += c;
    }
    return false;
}

void SerialConsole::reply(JsonDocument& response) {
    String line;
    serializeJson(response, line);
    Serial.print("@mnemos ");
    Serial.println(line);
}

void SerialConsole::replyError(const String& cmd, const String& error) {
    JsonDocument response;
    response["cmd"] = cmd;
    response["ok"] = false;
    response["error"] = error;
    reply(response);
}
