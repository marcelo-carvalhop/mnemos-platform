#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

// Console de provisionamento e diagnóstico pela USB (115200).
//
// Uma linha por comando, em JSON:
//   {"cmd":"info"}
//   {"cmd":"provision","ssid":"Lab","password":"segredo123",
//    "backendUrl":"http://192.168.0.10:8000","deviceToken":"..."}
//   {"cmd":"wifi","ssid":"Lab","password":"segredo123"}
//   {"cmd":"backend","url":"http://notebook.local:8000","token":"..."}
//   {"cmd":"sync"}
//   {"cmd":"time","epoch":1763730000}
//   {"cmd":"unpair","newIdentity":true}
//   {"cmd":"reboot"}
// Atalhos de texto: "mnemos info", "mnemos sync", "mnemos help".
//
// Cada resposta é uma linha "@mnemos {...}", fácil de separar do log.
// A ferramenta tools/mnemos_demo.py usa este console para parear a placa
// sem o app (útil em demonstrações locais).
class SerialConsole {
public:
    void begin();
    bool poll(JsonDocument& command);

    static void reply(JsonDocument& response);
    static void replyError(const String& cmd, const String& error);

private:
    String buffer_;
    bool overflow_ = false;

    bool parseLine(const String& line, JsonDocument& command);
};
