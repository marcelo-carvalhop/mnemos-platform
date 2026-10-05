#pragma once

// String do Arduino sobre std::string, só com a API usada pelos módulos
// testados e pelo ArduinoJson (ARDUINOJSON_ENABLE_ARDUINO_STRING).

#include <cstdlib>
#include <string>

class String {
public:
    String() = default;

    String(const char* text)
        : value_(text != nullptr ? text : "") {}

    String(const std::string& text)
        : value_(text) {}

    String& operator=(const char* text) {
        value_ = text != nullptr ? text : "";
        return *this;
    }

    bool concat(const char* text) {
        if (text != nullptr) {
            value_ += text;
        }
        return true;
    }

    String& operator+=(const char* text) {
        concat(text);
        return *this;
    }

    String& operator+=(const String& other) {
        value_ += other.value_;
        return *this;
    }

    const char* c_str() const {
        return value_.c_str();
    }

    unsigned int length() const {
        return static_cast<unsigned int>(value_.size());
    }

    bool reserve(unsigned int size) {
        value_.reserve(size);
        return true;
    }

    int indexOf(char c, unsigned int from = 0) const {
        const std::string::size_type found = value_.find(c, from);
        return found == std::string::npos ? -1 : static_cast<int>(found);
    }

    String substring(unsigned int begin, unsigned int end) const {
        if (begin > end) {
            const unsigned int swap = begin;
            begin = end;
            end = swap;
        }
        if (begin >= value_.size()) {
            return String();
        }
        return String(value_.substr(begin, end - begin));
    }

    String substring(unsigned int begin) const {
        return substring(begin, length());
    }

    bool startsWith(const char* prefix) const {
        return value_.rfind(prefix, 0) == 0;
    }

    double toDouble() const {
        return std::strtod(value_.c_str(), nullptr);
    }

    void toLowerCase() {
        for (char& c : value_) {
            if (c >= 'A' && c <= 'Z') {
                c = static_cast<char>(c - 'A' + 'a');
            }
        }
    }

    bool operator==(const String& other) const {
        return value_ == other.value_;
    }

    bool operator==(const char* text) const {
        return value_ == (text != nullptr ? text : "");
    }

    bool operator!=(const String& other) const {
        return !(*this == other);
    }

    bool operator!=(const char* text) const {
        return !(*this == text);
    }

    friend String operator+(const String& left, const String& right) {
        return String(left.value_ + right.value_);
    }

private:
    std::string value_;
};
