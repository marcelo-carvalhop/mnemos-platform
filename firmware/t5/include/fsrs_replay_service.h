#pragma once

#include <cstddef>

#include "models.h"

class Storage;

class FsrsReplayService {
public:
    static bool rebuild(
        Storage& storage,
        CardState* states,
        size_t count);

};
