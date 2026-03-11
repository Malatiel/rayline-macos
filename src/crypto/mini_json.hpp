#pragma once
// Minimal single-header JSON library compatible with nlohmann/json subset
// Supports: object, array, string, int, bool, null types
// No external dependencies

#include <string>
#include <vector>
#include <map>
#include <stdexcept>
#include <sstream>
#include <cstdint>
#include <cstring>
#include <cctype>

namespace json_ns {

// Forward declaration
class value;

enum class type_t {
    null_type,
    bool_type,
    int_type,
    string_type,
    array_type,
    object_type
};

class value {
public:
    type_t type_ = type_t::null_type;
    bool   bool_val_   = false;
    long long int_val_ = 0;
    std::string str_val_;
    std::vector<value> arr_val_;
    std::map<std::string, value> obj_val_;

    // ---- Constructors ----
    value() : type_(type_t::null_type) {}
    value(std::nullptr_t) : type_(type_t::null_type) {}                             // NOLINT
    value(bool b) : type_(type_t::bool_type), bool_val_(b) {}                       // NOLINT
    value(int v) : type_(type_t::int_type), int_val_(v) {}                          // NOLINT
    value(long v) : type_(type_t::int_type), int_val_(static_cast<long long>(v)) {} // NOLINT
    value(long long v) : type_(type_t::int_type), int_val_(v) {}                    // NOLINT
    value(unsigned int v) : type_(type_t::int_type), int_val_(static_cast<long long>(v)) {} // NOLINT
    value(const char* s) : type_(type_t::string_type), str_val_(s) {}               // NOLINT
    value(const std::string& s) : type_(type_t::string_type), str_val_(s) {}        // NOLINT
    value(std::string&& s) : type_(type_t::string_type), str_val_(std::move(s)) {}  // NOLINT

    // Construct array from vector
    value(std::vector<value> arr) : type_(type_t::array_type), arr_val_(std::move(arr)) {} // NOLINT

    // ---- Assignment ----
    value& operator=(bool b)              { type_ = type_t::bool_type;   bool_val_ = b;                              return *this; }
    value& operator=(int v)               { type_ = type_t::int_type;    int_val_ = v;                               return *this; }
    value& operator=(long long v)         { type_ = type_t::int_type;    int_val_ = v;                               return *this; }
    value& operator=(unsigned int v)      { type_ = type_t::int_type;    int_val_ = static_cast<long long>(v);       return *this; }
    value& operator=(const char* s)       { type_ = type_t::string_type; str_val_ = s;                              return *this; }
    value& operator=(const std::string& s){ type_ = type_t::string_type; str_val_ = s;                              return *this; }
    value& operator=(std::string&& s)     { type_ = type_t::string_type; str_val_ = std::move(s);                   return *this; }

    // ---- Factory ----
    static value array() {
        value v;
        v.type_ = type_t::array_type;
        return v;
    }

    // ---- Type checks ----
    [[nodiscard]] bool is_null()   const { return type_ == type_t::null_type; }
    [[nodiscard]] bool is_bool()   const { return type_ == type_t::bool_type; }
    [[nodiscard]] bool is_int()    const { return type_ == type_t::int_type; }
    [[nodiscard]] bool is_string() const { return type_ == type_t::string_type; }
    [[nodiscard]] bool is_array()  const { return type_ == type_t::array_type; }
    [[nodiscard]] bool is_object() const { return type_ == type_t::object_type; }

    // ---- Object operations ----
    [[nodiscard]] bool contains(const std::string& key) const {
        if (type_ != type_t::object_type) return false;
        return obj_val_.contains(key);
    }

    // at() - throws if missing
    [[nodiscard]] const value& at(const std::string& key) const {
        if (type_ != type_t::object_type)
            throw std::out_of_range("json: not an object");
        auto it = obj_val_.find(key);
        if (it == obj_val_.end())
            throw std::out_of_range("json: key not found: " + key);
        return it->second;
    }

    value& at(const std::string& key) {
        if (type_ != type_t::object_type)
            throw std::out_of_range("json: not an object");
        auto it = obj_val_.find(key);
        if (it == obj_val_.end())
            throw std::out_of_range("json: key not found: " + key);
        return it->second;
    }

    // operator[] - creates entry if missing (object must exist or be null)
    value& operator[](const std::string& key) {
        if (type_ == type_t::null_type) {
            type_ = type_t::object_type;
        }
        if (type_ != type_t::object_type)
            throw std::runtime_error("json: operator[] on non-object");
        return obj_val_[key];
    }

    const value& operator[](const std::string& key) const {
        if (type_ != type_t::object_type)
            throw std::runtime_error("json: operator[] on non-object");
        auto it = obj_val_.find(key);
        if (it == obj_val_.end())
            throw std::out_of_range("json: key not found: " + key);
        return it->second;
    }

    // ---- Array operations ----
    void push_back(const value& v) {
        if (type_ == type_t::null_type) type_ = type_t::array_type;
        if (type_ != type_t::array_type)
            throw std::runtime_error("json: push_back on non-array");
        arr_val_.push_back(v);
    }

    void push_back(value&& v) {
        if (type_ == type_t::null_type) type_ = type_t::array_type;
        if (type_ != type_t::array_type)
            throw std::runtime_error("json: push_back on non-array");
        arr_val_.push_back(std::move(v));
    }

    // ---- Typed getters ----
    template<typename T>
    T get() const;

    // ---- Merge patch (RFC 7396 style - shallow merge of objects) ----
    void merge_patch(const value& patch) {
        if (patch.type_ != type_t::object_type) {
            *this = patch;
            return;
        }
        if (type_ != type_t::object_type) {
            type_ = type_t::object_type;
        }
        for (auto& [k, v] : patch.obj_val_) {
            if (v.is_null()) {
                obj_val_.erase(k);
            } else {
                obj_val_[k].merge_patch(v);
            }
        }
    }

    // ---- Iterators (for range-for over arrays) ----
    using iterator = std::vector<value>::iterator;
    using const_iterator = std::vector<value>::const_iterator;

    iterator begin() {
        if (type_ != type_t::array_type)
            throw std::runtime_error("json: begin() on non-array");
        return arr_val_.begin();
    }

    iterator end() {
        if (type_ != type_t::array_type)
            throw std::runtime_error("json: end() on non-array");
        return arr_val_.end();
    }

    [[nodiscard]] const_iterator begin() const {
        if (type_ != type_t::array_type)
            throw std::runtime_error("json: begin() on non-array");
        return arr_val_.begin();
    }

    [[nodiscard]] const_iterator end() const {
        if (type_ != type_t::array_type)
            throw std::runtime_error("json: end() on non-array");
        return arr_val_.end();
    }

    // ---- Serialization ----
    [[nodiscard]] std::string dump(int indent = 0) const {
        return dump_internal(indent, 0);
    }

    // ---- Parse ----
    static value parse(const std::string& s);

private:
    [[nodiscard]] std::string dump_internal(int indent, int depth) const;
};

// ---- Template specializations ----

template<>
inline std::string value::get<std::string>() const {
    if (type_ == type_t::string_type) return str_val_;
    throw std::runtime_error("json: get<string> on non-string type");
}

template<>
inline int value::get<int>() const {
    if (type_ == type_t::int_type) return static_cast<int>(int_val_);
    if (type_ == type_t::bool_type) return bool_val_ ? 1 : 0;
    throw std::runtime_error("json: get<int> on non-int type");
}

template<>
inline uint32_t value::get<uint32_t>() const {
    if (type_ == type_t::int_type) return static_cast<uint32_t>(int_val_);
    if (type_ == type_t::bool_type) return bool_val_ ? 1U : 0U;
    throw std::runtime_error("json: get<uint32_t> on non-int type");
}

template<>
inline bool value::get<bool>() const {
    if (type_ == type_t::bool_type) return bool_val_;
    if (type_ == type_t::int_type) return int_val_ != 0;
    throw std::runtime_error("json: get<bool> on non-bool type");
}

// ---- Serialization implementation ----

static std::string json_escape_string(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 2);
    out += '"';
    for (unsigned char c : s) {
        if (c == '"')       { out += "\\\""; }
        else if (c == '\\') { out += "\\\\"; }
        else if (c == '\n') { out += "\\n"; }
        else if (c == '\r') { out += "\\r"; }
        else if (c == '\t') { out += "\\t"; }
        else if (c < 0x20) {
            char buf[8];
            snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned>(c));
            out += buf;
        } else {
            out += static_cast<char>(c);
        }
    }
    out += '"';
    return out;
}

inline std::string value::dump_internal(int indent, int depth) const {
    std::string ind1(indent > 0 ? static_cast<size_t>(indent * depth)       : 0U, ' ');
    std::string ind2(indent > 0 ? static_cast<size_t>(indent * (depth + 1)) : 0U, ' ');
    std::string nl = indent > 0 ? "\n" : "";
    std::string sp = indent > 0 ? " " : "";

    switch (type_) {
        case type_t::null_type:   return "null";
        case type_t::bool_type:   return bool_val_ ? "true" : "false";
        case type_t::int_type:    return std::to_string(int_val_);
        case type_t::string_type: return json_escape_string(str_val_);
        case type_t::array_type: {
            if (arr_val_.empty()) return "[]";
            std::string out = "[";
            out += nl;
            for (size_t i = 0; i < arr_val_.size(); i++) {
                out += ind2;
                out += arr_val_[i].dump_internal(indent, depth + 1);
                if (i + 1 < arr_val_.size()) out += ",";
                out += nl;
            }
            out += ind1;
            out += "]";
            return out;
        }
        case type_t::object_type: {
            if (obj_val_.empty()) return "{}";
            std::string out = "{";
            out += nl;
            size_t i = 0;
            for (auto& [k, v] : obj_val_) {
                out += ind2;
                out += json_escape_string(k);
                out += ":";
                out += sp;
                out += v.dump_internal(indent, depth + 1);
                if (i + 1 < obj_val_.size()) out += ",";
                out += nl;
                i++;
            }
            out += ind1;
            out += "}";
            return out;
        }
    }
    return "null";
}

// ---- Parser ----

struct Parser {
    const std::string& src;
    size_t pos = 0;

    explicit Parser(const std::string& s) : src(s) {}

    void skip_ws() {
        while (pos < src.size() && isspace(static_cast<unsigned char>(src[pos]))) pos++;
    }

    char peek() {
        skip_ws();
        return pos < src.size() ? src[pos] : '\0';
    }

    char next() {
        skip_ws();
        if (pos >= src.size()) throw std::runtime_error("json: unexpected end of input");
        return src[pos++];
    }

    void expect(char c) {
        char got = next();
        if (got != c) {
            std::string msg = "json: expected '";
            msg += c;
            msg += "' got '";
            msg += got;
            msg += "'";
            throw std::runtime_error(msg);
        }
    }

    value parse_value() {
        char c = peek();
        if (c == '"') return parse_string_val();
        if (c == '{') return parse_object();
        if (c == '[') return parse_array();
        if (c == 't') { pos++; expect('r'); expect('u'); expect('e'); return {true}; }
        if (c == 'f') { pos++; expect('a'); expect('l'); expect('s'); expect('e'); return {false}; }
        if (c == 'n') { pos++; expect('u'); expect('l'); expect('l'); return {}; }
        if (c == '-' || isdigit(static_cast<unsigned char>(c))) return parse_number();
        throw std::runtime_error(std::string("json: unexpected character '") + c + "'");
    }

    std::string parse_string() {
        expect('"');
        std::string out;
        while (pos < src.size()) {
            char c = src[pos++];
            if (c == '"') return out;
            if (c == '\\') {
                if (pos >= src.size()) break;
                char e = src[pos++];
                if (e == '"')       out += '"';
                else if (e == '\\') out += '\\';
                else if (e == '/')  out += '/';
                else if (e == 'n')  out += '\n';
                else if (e == 'r')  out += '\r';
                else if (e == 't')  out += '\t';
                else if (e == 'b')  out += '\b';
                else if (e == 'f')  out += '\f';
                else if (e == 'u') {
                    // 4-hex unicode (basic BMP only)
                    uint32_t code = 0;
                    for (int i = 0; i < 4; i++) {
                        char h = src[pos++];
                        code = code * 16 + static_cast<uint32_t>(
                            isdigit(static_cast<unsigned char>(h))
                                ? h - '0'
                                : tolower(static_cast<unsigned char>(h)) - 'a' + 10);
                    }
                    // Encode as UTF-8
                    if (code < 0x80U) {
                        out += static_cast<char>(code);
                    } else if (code < 0x800U) {
                        out += static_cast<char>(0xC0U | (code >> 6U));
                        out += static_cast<char>(0x80U | (code & 0x3FU));
                    } else {
                        out += static_cast<char>(0xE0U | (code >> 12U));
                        out += static_cast<char>(0x80U | ((code >> 6U) & 0x3FU));
                        out += static_cast<char>(0x80U | (code & 0x3FU));
                    }
                } else {
                    out += e;
                }
            } else {
                out += c;
            }
        }
        throw std::runtime_error("json: unterminated string");
    }

    value parse_string_val() {
        return {parse_string()};
    }

    value parse_number() {
        size_t start = pos;
        if (pos < src.size() && src[pos] == '-') pos++;
        while (pos < src.size() && isdigit(static_cast<unsigned char>(src[pos]))) pos++;
        bool is_float = false;
        if (pos < src.size() && src[pos] == '.') {
            is_float = true; pos++;
            while (pos < src.size() && isdigit(static_cast<unsigned char>(src[pos]))) pos++;
        }
        if (pos < src.size() && (src[pos] == 'e' || src[pos] == 'E')) {
            is_float = true; pos++;
            if (pos < src.size() && (src[pos] == '+' || src[pos] == '-')) pos++;
            while (pos < src.size() && isdigit(static_cast<unsigned char>(src[pos]))) pos++;
        }
        std::string num = src.substr(start, pos - start);
        if (is_float) {
            return {static_cast<long long>(std::stod(num))};
        }
        return {std::stoll(num)};
    }

    value parse_object() {
        expect('{');
        value obj;
        obj.type_ = type_t::object_type;
        skip_ws();
        if (peek() == '}') { pos++; return obj; }
        while (true) {
            skip_ws();
            std::string key = parse_string();
            skip_ws();
            expect(':');
            value val = parse_value();
            obj.obj_val_[key] = std::move(val);
            skip_ws();
            char c = peek();
            if (c == '}') { pos++; break; }
            if (c == ',') { pos++; continue; }
            throw std::runtime_error("json: expected ',' or '}' in object");
        }
        return obj;
    }

    value parse_array() {
        expect('[');
        value arr;
        arr.type_ = type_t::array_type;
        skip_ws();
        if (peek() == ']') { pos++; return arr; }
        while (true) {
            arr.arr_val_.push_back(parse_value());
            skip_ws();
            char c = peek();
            if (c == ']') { pos++; break; }
            if (c == ',') { pos++; continue; }
            throw std::runtime_error("json: expected ',' or ']' in array");
        }
        return arr;
    }
};

inline value value::parse(const std::string& s) {
    Parser p(s);
    return p.parse_value();
}

} // namespace json_ns

// Convenience alias
namespace json_ns {
    using json = value;
}
