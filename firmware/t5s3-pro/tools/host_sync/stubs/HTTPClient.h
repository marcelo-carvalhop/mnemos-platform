#pragma once
#include "Arduino.h"
#include "WiFiClient.h"
#include "WiFiClientSecure.h"
#include <map>
#include <string>
#include <vector>
class HTTPClient {
public:
    bool begin(WiFiClient&, const String& url) { url_ = url; return url.startsWith("http://"); }
    bool begin(WiFiClientSecure&, const String& url) { url_ = url; https_ = true; return true; }
    void setReuse(bool r) { if (r) ++reuseCalls; }
    void setConnectTimeout(int32_t) {}
    void setTimeout(uint16_t) {}
    void setUserAgent(const String& ua) { ua_ = ua; }
    void addHeader(const String& k, const String& v) { headers_.push_back({k.s, v.s}); }
    void collectHeaders(const char* keys[], size_t n) { for (size_t i = 0; i < n; ++i) wanted_.push_back(keys[i]); }
    int GET() { return perform("GET", ""); }
    int POST(const String& body) { return perform("POST", body.s); }
    int getSize() { return (int)body_.size(); }
    String getString() { return String(body_); }
    String header(const char* k);
    void end() { headers_.clear(); wanted_.clear(); }
    static int reuseCalls;
    static String errorToString(int e) { return String("http_error_") + String(e); }
    static int requests;           // contador para os testes
    static std::vector<std::string> log;
private:
    int perform(const char* method, const std::string& body);
    String url_; String ua_; bool https_ = false;
    std::vector<std::pair<std::string, std::string>> headers_;
    std::vector<std::string> wanted_;
    std::map<std::string, std::string> respHeaders_;
    std::string body_;
};
