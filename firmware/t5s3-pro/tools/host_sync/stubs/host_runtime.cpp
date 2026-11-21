#include "Arduino.h"
#include "LittleFS.h"
#include "ESPmDNS.h"
#include "HTTPClient.h"
#include <chrono>
#include <thread>
#include <random>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#include <iostream>

HostSerial Serial;
EspClass ESP;
LittleFSHost LittleFS;
MDNSHost MDNS;
int HTTPClient::requests = 0;
int HTTPClient::reuseCalls = 0;
std::vector<std::string> HTTPClient::log;
uint32_t g_millisOffset = 0;

static auto t0 = std::chrono::steady_clock::now();
uint32_t millis() { return (uint32_t)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count() + g_millisOffset; }
uint32_t micros() { return millis() * 1000; }
void delay(uint32_t ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms > 50 ? 50 : ms)); g_millisOffset += ms > 50 ? ms - 50 : 0; }
void yield() {}
uint32_t esp_random() { static std::mt19937 r(std::random_device{}()); return r(); }

size_t HostSerial::write(uint8_t c) { if (!quiet) fputc(c, stdout); return 1; }
size_t HostSerial::write(const uint8_t* b, size_t n) { if (!quiet) fwrite(b, 1, n, stdout); return n; }
int HostSerial::available() { return (int)(input.size() - pos); }
int HostSerial::read() { return pos < input.size() ? (unsigned char)input[pos++] : -1; }

String HTTPClient::header(const char* k) { std::string key(k); for (auto& c : key) c = tolower(c); auto it = respHeaders_.find(key); return it == respHeaders_.end() ? String() : String(it->second); }

int HTTPClient::perform(const char* method, const std::string& body) {
    ++requests;
    respHeaders_.clear();
    if (https_) return -1;
    std::string url = url_.s.substr(7);
    std::string hostport = url.substr(0, url.find('/'));
    std::string path = url.find('/') == std::string::npos ? "/" : url.substr(url.find('/'));
    std::string host = hostport, port = "80";
    if (hostport.find(':') != std::string::npos) { host = hostport.substr(0, hostport.find(':')); port = hostport.substr(hostport.find(':') + 1); }
    log.push_back(std::string(method) + " " + path);
    addrinfo hints{}, *res = nullptr; hints.ai_family = AF_INET; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host.c_str(), port.c_str(), &hints, &res) != 0) return -1;
    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0 || connect(fd, res->ai_addr, res->ai_addrlen) != 0) { freeaddrinfo(res); if (fd >= 0) close(fd); return -1; }
    freeaddrinfo(res);
    std::string req = std::string(method) + " " + path + " HTTP/1.1\r\nHost: " + hostport + "\r\nConnection: close\r\nUser-Agent: " + ua_.s + "\r\n";
    for (auto& h : headers_) req += h.first + ": " + h.second + "\r\n";
    if (std::string(method) == "POST") req += "Content-Length: " + std::to_string(body.size()) + "\r\n";
    req += "\r\n" + body;
    send(fd, req.data(), req.size(), 0);
    std::string resp; char buf[8192]; ssize_t n;
    while ((n = recv(fd, buf, sizeof buf, 0)) > 0) resp.append(buf, n);
    close(fd);
    size_t he = resp.find("\r\n\r\n"); if (he == std::string::npos) return -1;
    std::string head = resp.substr(0, he); body_ = resp.substr(he + 4);
    int status = atoi(head.substr(9, 3).c_str());
    size_t pos = head.find("\r\n");
    bool chunked = false;
    while (pos != std::string::npos && pos < head.size()) {
        size_t next = head.find("\r\n", pos + 2); std::string line = head.substr(pos + 2, next == std::string::npos ? std::string::npos : next - pos - 2);
        size_t c = line.find(':'); if (c != std::string::npos) { std::string k = line.substr(0, c); for (auto& ch : k) ch = tolower(ch); std::string v = line.substr(c + 1); while (!v.empty() && v[0] == ' ') v.erase(0, 1); respHeaders_[k] = v; if (k == "transfer-encoding" && v.find("chunked") != std::string::npos) chunked = true; }
        pos = next;
    }
    if (chunked) { std::string out; size_t i = 0; while (i < body_.size()) { size_t e = body_.find("\r\n", i); size_t len = strtoul(body_.substr(i, e - i).c_str(), nullptr, 16); if (!len) break; out += body_.substr(e + 2, len); i = e + 2 + len + 2; } body_ = out; }
    return status;
}
