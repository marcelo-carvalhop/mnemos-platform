#pragma once

#include <Arduino.h>

#include "models.h"

class NetworkService;
class Storage;

class BackendSyncService {
public:
    BackendSyncService(NetworkService& network,
                       Storage& storage,
                       CardDefinition* cards,
                       CardState* states,
                       size_t maxCards,
                       size_t& cardCount);

    void begin();
    void loop();
    bool syncNow();
    bool consumeLibraryUpdated();

private:
    NetworkService& network_;
    Storage& storage_;
    CardDefinition* cards_;
    CardState* states_;
    size_t maxCards_;
    size_t& cardCount_;
    uint32_t lastSyncMs_ = 0;
    bool libraryUpdated_ = false;

    bool pushReviews();
    bool pullSnapshot();
    bool pullReviews();
    bool reportStatus(bool synced);
    bool request(const String& method, const String& path, const String& body, int& status, String& response);
};
