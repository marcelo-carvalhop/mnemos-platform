#pragma once

#include <Arduino.h>

// Identidade do terminal perante a plataforma.
//
// O id vem do MAC ("T5S3-ABCDEF"). O backend vincula um id de terminal a uma
// única conta para sempre, então trocar de conta exige um id novo: a geração
// ("T5S3-ABCDEF-2") é incrementada pelo comando serial "unpair" com
// "newIdentity":true ou pela ferramenta tools/mnemos_demo.py.
namespace TerminalIdentity {

String macSuffix();
uint16_t generation();
String deviceId();
uint16_t rotate();

// UUIDv7 (RFC 9562), o formato de id que app e web geram (§5.7).
String uuidV7(uint64_t epochMs);

}  // namespace TerminalIdentity
