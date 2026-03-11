#pragma once
// Crypto abstraction layer for WireGuard
// Standalone implementation: no libsodium, no external dependencies
// Uses our own Curve25519, ChaCha20-Poly1305, and BLAKE2s

#include "blake2s.hpp"
#include "curve25519.hpp"
#include "chacha20poly1305.hpp"
#include <array>
#include <vector>
#include <cstring>
#include <stdexcept>
#include <cstdint>
#include <fcntl.h>
#include <unistd.h>

namespace crypto {

// Key size constants
static constexpr size_t KEY_SIZE     = 32;
static constexpr size_t HASH_SIZE    = 32;
static constexpr size_t MAC_SIZE     = 16;
static constexpr size_t NONCE_SIZE   = 12;  // ChaCha20-Poly1305 nonce
static constexpr size_t TIMESTAMP_SIZE = 12;

using Key     = std::array<uint8_t, KEY_SIZE>;
using Hash    = std::array<uint8_t, HASH_SIZE>;
using MacTag  = std::array<uint8_t, MAC_SIZE>;

// ---- Random bytes ----
inline void random_bytes(uint8_t* buf, size_t n) {
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) throw std::runtime_error("Cannot open /dev/urandom");
    ssize_t got = 0;
    while ((size_t)got < n) {
        ssize_t r = read(fd, buf + got, n - (size_t)got);
        if (r <= 0) { close(fd); throw std::runtime_error("read /dev/urandom failed"); }
        got += r;
    }
    close(fd);
}

inline Key random_key() {
    Key k{};
    random_bytes(k.data(), KEY_SIZE);
    return k;
}

// ---- Curve25519 DH ----

// Clamp a Curve25519 private key (as per RFC 7748)
inline void clamp_private_key(Key& priv) {
    priv[0]  &= 248;
    priv[31] &= 127;
    priv[31] |= 64;
}

// Generate a random clamped private key and derive public key
inline void generate_keypair_wg(Key& private_key, Key& public_key) {
    random_bytes(private_key.data(), KEY_SIZE);
    clamp_private_key(private_key);
    curve25519::x25519_base(public_key.data(), private_key.data());
}

// Derive public key from private key
inline Key public_from_private(const Key& private_key) {
    Key pub{};
    curve25519::x25519_base(pub.data(), private_key.data());
    return pub;
}

// Curve25519 DH
inline Key dh(const Key& private_key, const Key& peer_public) {
    Key shared{};
    curve25519::x25519(shared.data(), private_key.data(), peer_public.data());
    // Check for all-zero output (low-order point)
    uint8_t acc = 0;
    for (auto b : shared) acc |= b;
    if (acc == 0) throw std::runtime_error("DH computation failed (low-order point)");
    return shared;
}

// ---- BLAKE2s hashing ----

inline Hash blake2s_hash(const uint8_t* data, size_t len) {
    return blake2s::hash(data, len);
}

// Hash of two concatenated inputs
inline Hash blake2s_hash2(const uint8_t* a, size_t alen,
                           const uint8_t* b, size_t blen)
{
    blake2s::blake2s_state S;
    blake2s::blake2s_init(&S, HASH_SIZE);
    blake2s::blake2s_update(&S, a, alen);
    blake2s::blake2s_update(&S, b, blen);
    Hash out{};
    blake2s::blake2s_final(&S, out.data(), HASH_SIZE);
    return out;
}

// BLAKE2s-MAC (keyed BLAKE2s)
inline Hash blake2s_mac(const uint8_t* key, size_t keylen,
                         const uint8_t* data, size_t datalen)
{
    return blake2s::hmac(key, keylen, data, datalen);
}

// ---- HKDF using BLAKE2s ----
// WireGuard HKDF:
//   HKDF-Extract(salt, ikm):  T0 = BLAKE2s-MAC(key=salt, data=ikm)
//   HKDF-Expand(prk, info):   Ti = BLAKE2s-MAC(key=prk, data=prev||info||counter)

struct HKDFOutput1 { Hash out1; };
struct HKDFOutput2 { Hash out1; Hash out2; };
struct HKDFOutput3 { Hash out1; Hash out2; Hash out3; };

// HKDF-Extract: PRK = HMAC(salt, ikm)
inline Hash hkdf_extract(const uint8_t* salt, size_t saltlen,
                          const uint8_t* ikm,  size_t ikmlen)
{
    return blake2s_mac(salt, saltlen, ikm, ikmlen);
}

// HKDF-Expand one output
inline Hash hkdf_expand_one(const Hash& prk, const uint8_t* info, size_t infolen) {
    std::vector<uint8_t> input(infolen + 1);
    if (infolen > 0) memcpy(input.data(), info, infolen);
    input[infolen] = 0x01;
    return blake2s_mac(prk.data(), HASH_SIZE, input.data(), input.size());
}

// WireGuard HKDF variants
inline HKDFOutput1 hkdf1(const Hash& chaining_key,
                          const uint8_t* ikm, size_t ikmlen)
{
    Hash prk = blake2s_mac(chaining_key.data(), HASH_SIZE, ikm, ikmlen);
    uint8_t c1 = 0x01;
    Hash t1 = blake2s_mac(prk.data(), HASH_SIZE, &c1, 1);
    return {t1};
}

inline HKDFOutput2 hkdf2(const Hash& chaining_key,
                          const uint8_t* ikm, size_t ikmlen)
{
    Hash prk = blake2s_mac(chaining_key.data(), HASH_SIZE, ikm, ikmlen);
    uint8_t c1 = 0x01;
    Hash t1 = blake2s_mac(prk.data(), HASH_SIZE, &c1, 1);
    uint8_t t1c2[HASH_SIZE + 1];
    memcpy(t1c2, t1.data(), HASH_SIZE);
    t1c2[HASH_SIZE] = 0x02;
    Hash t2 = blake2s_mac(prk.data(), HASH_SIZE, t1c2, HASH_SIZE + 1);
    return {t1, t2};
}

inline HKDFOutput3 hkdf3(const Hash& chaining_key,
                          const uint8_t* ikm, size_t ikmlen)
{
    Hash prk = blake2s_mac(chaining_key.data(), HASH_SIZE, ikm, ikmlen);
    uint8_t c1 = 0x01;
    Hash t1 = blake2s_mac(prk.data(), HASH_SIZE, &c1, 1);
    uint8_t t1c2[HASH_SIZE + 1];
    memcpy(t1c2, t1.data(), HASH_SIZE);
    t1c2[HASH_SIZE] = 0x02;
    Hash t2 = blake2s_mac(prk.data(), HASH_SIZE, t1c2, HASH_SIZE + 1);
    uint8_t t2c3[HASH_SIZE + 1];
    memcpy(t2c3, t2.data(), HASH_SIZE);
    t2c3[HASH_SIZE] = 0x03;
    Hash t3 = blake2s_mac(prk.data(), HASH_SIZE, t2c3, HASH_SIZE + 1);
    return {t1, t2, t3};
}

// ---- ChaCha20-Poly1305 AEAD ----
// WireGuard uses AEAD_CHACHA20POLY1305 with 96-bit nonce
// Counter is 64-bit (LE) placed in nonce bytes [4..11], bytes [0..3] = 0

// Build a 12-byte nonce from 64-bit counter
inline std::array<uint8_t, NONCE_SIZE> make_nonce(uint64_t counter) {
    std::array<uint8_t, NONCE_SIZE> nonce{};
    // bytes [0..3] = 0
    // Little-endian counter in bytes [4..11]
    nonce[4]  = (uint8_t)(counter);
    nonce[5]  = (uint8_t)(counter >> 8);
    nonce[6]  = (uint8_t)(counter >> 16);
    nonce[7]  = (uint8_t)(counter >> 24);
    nonce[8]  = (uint8_t)(counter >> 32);
    nonce[9]  = (uint8_t)(counter >> 40);
    nonce[10] = (uint8_t)(counter >> 48);
    nonce[11] = (uint8_t)(counter >> 56);
    return nonce;
}

// Encrypt: plaintext -> ciphertext + 16-byte MAC appended
// Returns ciphertext+tag
inline std::vector<uint8_t> aead_encrypt(const Key& key, uint64_t counter,
                                          const uint8_t* plaintext, size_t ptlen,
                                          const uint8_t* aad, size_t aadlen)
{
    auto nonce = make_nonce(counter);
    std::vector<uint8_t> ct(ptlen + MAC_SIZE);
    chacha20poly1305::encrypt(
        key.data(), nonce.data(),
        1,                         // counter starts at 1 for encryption
        plaintext, ptlen,
        aad, aadlen,
        ct.data()
    );
    return ct;
}

// Decrypt: ciphertext (with 16-byte tag) -> plaintext
// Returns plaintext on success, throws on failure
inline std::vector<uint8_t> aead_decrypt(const Key& key, uint64_t counter,
                                          const uint8_t* ciphertext, size_t ctlen,
                                          const uint8_t* aad, size_t aadlen)
{
    if (ctlen < MAC_SIZE) throw std::runtime_error("Ciphertext too short");
    auto nonce = make_nonce(counter);
    std::vector<uint8_t> pt(ctlen - MAC_SIZE);
    bool ok = chacha20poly1305::decrypt(
        key.data(), nonce.data(),
        1,                         // counter starts at 1 for decryption
        ciphertext, ctlen,
        aad, aadlen,
        pt.data()
    );
    if (!ok) throw std::runtime_error("AEAD decrypt failed (authentication error)");
    return pt;
}

// Seal with zero-length nonce (for handshake messages using zero nonce)
inline std::vector<uint8_t> aead_encrypt_zero_nonce(const Key& key,
                                                      const uint8_t* plaintext, size_t ptlen,
                                                      const uint8_t* aad, size_t aadlen)
{
    return aead_encrypt(key, 0, plaintext, ptlen, aad, aadlen);
}

inline std::vector<uint8_t> aead_decrypt_zero_nonce(const Key& key,
                                                      const uint8_t* ciphertext, size_t ctlen,
                                                      const uint8_t* aad, size_t aadlen)
{
    return aead_decrypt(key, 0, ciphertext, ctlen, aad, aadlen);
}

// ---- Poly1305 MAC for WireGuard mac1/mac2 ----
// mac1/mac2 use BLAKE2s-MAC (BLAKE2s keyed)

inline std::array<uint8_t, 16> poly1305_mac16(const uint8_t* key, size_t keylen,
                                                const uint8_t* data, size_t datalen)
{
    std::array<uint8_t, 16> out{};
    blake2s::blake2s(out.data(), 16, data, datalen, key, keylen);
    return out;
}

// ---- Base64 encoding/decoding ----
static const char* B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

inline std::string base64_encode(const uint8_t* data, size_t len) {
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        uint32_t b = (uint32_t)data[i] << 16;
        if (i+1 < len) b |= (uint32_t)data[i+1] << 8;
        if (i+2 < len) b |= (uint32_t)data[i+2];
        out += B64_CHARS[(b >> 18) & 63];
        out += B64_CHARS[(b >> 12) & 63];
        out += (i+1 < len) ? B64_CHARS[(b >> 6) & 63] : '=';
        out += (i+2 < len) ? B64_CHARS[(b     ) & 63] : '=';
    }
    return out;
}

inline std::string base64_encode(const Key& key) {
    return base64_encode(key.data(), key.size());
}

inline std::vector<uint8_t> base64_decode(const std::string& s) {
    static const int8_t DECODE[256] = {
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
        52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,
        -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
        15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
        -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    };
    std::vector<uint8_t> out;
    out.reserve((s.size() * 3) / 4);
    uint32_t acc = 0;
    int bits = 0;
    for (char c : s) {
        if (c == '=') break;
        int v = DECODE[(uint8_t)c];
        if (v < 0) continue;
        acc = (acc << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back((uint8_t)(acc >> bits));
        }
    }
    return out;
}

inline Key key_from_base64(const std::string& s) {
    auto bytes = base64_decode(s);
    if (bytes.size() != KEY_SIZE)
        throw std::runtime_error("Invalid key length in base64: got " +
                                 std::to_string(bytes.size()) + " bytes");
    Key k{};
    memcpy(k.data(), bytes.data(), KEY_SIZE);
    return k;
}

} // namespace crypto
