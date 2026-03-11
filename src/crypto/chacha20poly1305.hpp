#pragma once
// Standalone ChaCha20-Poly1305 AEAD per RFC 8439
// No external dependencies

#include <cstdint>
#include <cstring>
#include <cstdlib>

namespace chacha20poly1305 {

// ---- ChaCha20 ----

#define ROTL32(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

static void qr(uint32_t s[16], int a, int b, int c, int d) {
    s[a] += s[b]; s[d] ^= s[a]; s[d] = ROTL32(s[d], 16);
    s[c] += s[d]; s[b] ^= s[c]; s[b] = ROTL32(s[b], 12);
    s[a] += s[b]; s[d] ^= s[a]; s[d] = ROTL32(s[d],  8);
    s[c] += s[d]; s[b] ^= s[c]; s[b] = ROTL32(s[b],  7);
}

static inline uint32_t load32_le(const uint8_t* p) {
    return (uint32_t)p[0]
         | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16)
         | ((uint32_t)p[3] << 24);
}

static inline void store32_le(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)(v);
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static inline uint64_t load64_le(const uint8_t* p) {
    return (uint64_t)load32_le(p) | ((uint64_t)load32_le(p + 4) << 32);
}

static inline void store64_le(uint8_t* p, uint64_t v) {
    store32_le(p,     (uint32_t)(v));
    store32_le(p + 4, (uint32_t)(v >> 32));
}

// Generate one ChaCha20 64-byte block
static void chacha20_block(uint32_t out[16], const uint8_t key[32],
                            const uint8_t nonce[12], uint32_t counter)
{
    uint32_t s[16] = {
        0x61707865u, 0x3320646eu, 0x79622d32u, 0x6b206574u,
        load32_le(key),      load32_le(key+4),  load32_le(key+8),  load32_le(key+12),
        load32_le(key+16),   load32_le(key+20), load32_le(key+24), load32_le(key+28),
        counter,
        load32_le(nonce),    load32_le(nonce+4), load32_le(nonce+8)
    };

    uint32_t w[16];
    memcpy(w, s, sizeof(w));

    for (int i = 0; i < 10; i++) {
        // Column rounds
        qr(w, 0, 4,  8, 12);
        qr(w, 1, 5,  9, 13);
        qr(w, 2, 6, 10, 14);
        qr(w, 3, 7, 11, 15);
        // Diagonal rounds
        qr(w, 0, 5, 10, 15);
        qr(w, 1, 6, 11, 12);
        qr(w, 2, 7,  8, 13);
        qr(w, 3, 4,  9, 14);
    }

    for (int i = 0; i < 16; i++) out[i] = w[i] + s[i];
}

// XOR data with ChaCha20 keystream starting at block `counter`
static void chacha20_xor(const uint8_t key[32], const uint8_t nonce[12],
                          uint32_t counter,
                          const uint8_t* in, size_t len, uint8_t* out)
{
    uint32_t block[16];
    uint8_t  buf[64];
    size_t pos = 0;

    while (pos < len) {
        chacha20_block(block, key, nonce, counter++);
        for (int i = 0; i < 16; i++) store32_le(buf + 4 * i, block[i]);

        size_t chunk = (len - pos < 64) ? (len - pos) : 64;
        for (size_t i = 0; i < chunk; i++) out[pos + i] = in[pos + i] ^ buf[i];
        pos += chunk;
    }
}

// ---- Poly1305 ----

// Poly1305 uses 130-bit field GF(2^130 - 5)
// Key: 32 bytes = r (16 bytes, clamped) || s (16 bytes)
// Clamp r: clear bits 4,7 of bytes 3,7,11,15 and bits 2,3 of bytes 4,8,12

struct Poly1305State {
    // Accumulator as three 64-bit words (fits 130 bits)
    uint64_t h0, h1, h2;
    // r and s as 130-bit and 128-bit values
    uint64_t r0, r1;   // r as two 64-bit halves (each 64 bits, effective ~65 bits after carry)
    uint64_t s0, s1;   // s as two 64-bit halves
    // r as four 32-bit limbs for multiplication
    uint32_t rl[5];    // r broken into 26-bit limbs for reduction
};

// Process one 16-byte block (or pad if final)
// We implement using __uint128_t for simplicity and correctness

static void poly1305_init(Poly1305State& st, const uint8_t key[32]) {
    // Load r (first 16 bytes), apply clamp
    uint8_t r[16];
    memcpy(r, key, 16);
    r[3]  &= 15;
    r[7]  &= 15;
    r[11] &= 15;
    r[15] &= 15;
    r[4]  &= 252;
    r[8]  &= 252;
    r[12] &= 252;

    st.r0 = load64_le(r);
    st.r1 = load64_le(r + 8);
    st.s0 = load64_le(key + 16);
    st.s1 = load64_le(key + 24);
    st.h0 = st.h1 = st.h2 = 0;
}

// Add a block to the accumulator; hibit = 1 for full blocks, 0 for final pad
static void poly1305_block(Poly1305State& st, const uint8_t* m, size_t len, uint32_t hibit) {
    // Load message block as 130-bit integer
    uint8_t buf[17] = {};
    if (len > 16) len = 16;
    memcpy(buf, m, len);
    buf[len] = (uint8_t)hibit;

    uint64_t m0 = load64_le(buf);
    uint64_t m1 = load64_le(buf + 8);
    uint64_t m2 = buf[16];

    // h += m
    __uint128_t acc0 = (__uint128_t)st.h0 + m0;
    __uint128_t acc1 = (__uint128_t)st.h1 + m1 + (uint64_t)(acc0 >> 64);
    __uint128_t acc2 = (__uint128_t)st.h2 + m2 + (uint64_t)(acc1 >> 64);

    uint64_t h0 = (uint64_t)acc0;
    uint64_t h1 = (uint64_t)acc1;
    uint64_t h2 = (uint64_t)acc2;

    // h *= r  (mod 2^130 - 5)
    // h is 130 bits: h0, h1, h2 (h2 is at most 3 bits after addition)
    // r is 128 bits: r0, r1
    // Product is up to 258 bits; reduce mod 2^130-5

    uint64_t r0 = st.r0;
    uint64_t r1 = st.r1;

    // Full 258-bit product, h = h0 + h1*2^64 + h2*2^128, r = r0 + r1*2^64
    __uint128_t lo = (__uint128_t)h0 * r0;
    __uint128_t mid1 = (__uint128_t)h0 * r1;
    __uint128_t mid2 = (__uint128_t)h1 * r0;
    __uint128_t hi_part = (__uint128_t)h1 * r1;
    // h2 is at most 3 (2 bits), r0/r1 are 64-bit
    __uint128_t ext0 = (__uint128_t)h2 * r0;
    __uint128_t ext1 = (__uint128_t)h2 * r1;

    // 258-bit result in four 64-bit words
    __uint128_t w64_0 = lo;
    __uint128_t w64_1 = mid1 + mid2 + (w64_0 >> 64);
    __uint128_t w64_2 = hi_part + ext0 + (w64_1 >> 64);
    __uint128_t w64_3 = ext1 + (w64_2 >> 64);

    uint64_t res0 = (uint64_t)w64_0;
    uint64_t res1 = (uint64_t)w64_1;
    // bits 128..129 of result:
    uint64_t res2 = (uint64_t)w64_2 & 3;
    // bits 130+ (need to fold with *5):
    // upper = w64_2 >> 2 ... combined with w64_3
    // But we also need to fold the carry from w64_2 bits [2..63] and w64_3
    __uint128_t upper = (w64_2 >> 2) + (w64_3 << 62);

    // fold: result = (res0, res1, res2) + upper * 5
    __uint128_t fold = (__uint128_t)upper * 5;
    __uint128_t a0 = (__uint128_t)res0 + (uint64_t)fold;
    __uint128_t a1 = (__uint128_t)res1 + (uint64_t)(fold >> 64) + (a0 >> 64);
    __uint128_t a2 = (__uint128_t)res2 + (a1 >> 64);

    st.h0 = (uint64_t)a0;
    st.h1 = (uint64_t)a1;
    st.h2 = (uint64_t)a2;
}

static void poly1305_finish(Poly1305State& st, uint8_t tag[16]) {
    // Partially reduce mod 2^130-5: carry h2 overflow
    uint64_t h0 = st.h0, h1 = st.h1, h2 = st.h2;

    // h2 carries
    __uint128_t acc = (__uint128_t)(h2 >> 2) * 5 + h0;
    h0 = (uint64_t)acc;
    acc = (acc >> 64) + h1;
    h1 = (uint64_t)acc;
    h2 = (h2 & 3) + (uint64_t)(acc >> 64);

    // Fully reduce: subtract p = 2^130 - 5 if h >= p
    // Compute h - p; if no borrow use it
    __uint128_t g0 = (__uint128_t)h0 + 5;
    __uint128_t g1 = (__uint128_t)h1 + (g0 >> 64);
    uint64_t g2 = h2 + (uint64_t)(g1 >> 64);
    // If g2 >= 4 (bit 2 set), h >= p, use g
    uint64_t mask = (uint64_t)(-(long long)(g2 >> 2));  // all-ones if overflow
    h0 = (h0 & ~mask) | ((uint64_t)g0 & mask);
    h1 = (h1 & ~mask) | ((uint64_t)g1 & mask);

    // h += s
    __uint128_t s0_acc = (__uint128_t)h0 + st.s0;
    __uint128_t s1_acc = (__uint128_t)h1 + st.s1 + (s0_acc >> 64);
    h0 = (uint64_t)s0_acc;
    h1 = (uint64_t)s1_acc;

    store64_le(tag,     h0);
    store64_le(tag + 8, h1);
}

// Constant-time 16-byte compare
static bool tag_eq(const uint8_t* a, const uint8_t* b) {
    uint8_t diff = 0;
    for (int i = 0; i < 16; i++) diff |= a[i] ^ b[i];
    return diff == 0;
}

// ---- AEAD ----

// Compute AEAD MAC per RFC 8439:
// MAC_DATA = aad || pad(aad) || ciphertext || pad(ciphertext) || len(aad) u64le || len(ciphertext) u64le
static void aead_mac(uint8_t tag[16],
                     const uint8_t poly_key[32],
                     const uint8_t* aad, size_t aad_len,
                     const uint8_t* ct,  size_t ct_len)
{
    static const uint8_t zeros[16] = {};
    Poly1305State st;
    poly1305_init(st, poly_key);

    // AAD
    size_t rem = aad_len;
    const uint8_t* p = aad;
    while (rem >= 16) { poly1305_block(st, p, 16, 1); p += 16; rem -= 16; }
    if (rem > 0) poly1305_block(st, p, rem, 1);
    // pad aad
    size_t aad_pad = (16 - (aad_len % 16)) % 16;
    if (aad_pad > 0) poly1305_block(st, zeros, aad_pad, 1);

    // Ciphertext
    rem = ct_len;
    p = ct;
    while (rem >= 16) { poly1305_block(st, p, 16, 1); p += 16; rem -= 16; }
    if (rem > 0) poly1305_block(st, p, rem, 1);
    // pad ct
    size_t ct_pad = (16 - (ct_len % 16)) % 16;
    if (ct_pad > 0) poly1305_block(st, zeros, ct_pad, 1);

    // Lengths
    uint8_t lengths[16];
    store64_le(lengths,     (uint64_t)aad_len);
    store64_le(lengths + 8, (uint64_t)ct_len);
    poly1305_block(st, lengths, 16, 1);

    poly1305_finish(st, tag);
}

// Encrypt: out = ciphertext (plen bytes) || poly1305 tag (16 bytes)
// out must be at least plen + 16 bytes
inline void encrypt(const uint8_t key[32], const uint8_t nonce[12],
                    uint32_t counter,
                    const uint8_t* plain, size_t plen,
                    const uint8_t* aad, size_t aad_len,
                    uint8_t* out)
{
    // Generate Poly1305 key: first 32 bytes of ChaCha20 block 0
    uint32_t poly_block[16];
    chacha20_block(poly_block, key, nonce, 0);
    uint8_t poly_key[32];
    for (int i = 0; i < 8; i++) store32_le(poly_key + 4 * i, poly_block[i]);

    // Encrypt plaintext using ChaCha20 starting at specified counter
    chacha20_xor(key, nonce, counter, plain, plen, out);

    // Compute MAC over AAD and ciphertext
    aead_mac(out + plen, poly_key, aad, aad_len, out, plen);
}

// Decrypt: out = plaintext (clen - 16 bytes), returns true on success
// clen must be >= 16; out must be at least clen - 16 bytes
inline bool decrypt(const uint8_t key[32], const uint8_t nonce[12],
                    uint32_t counter,
                    const uint8_t* cipher, size_t clen,
                    const uint8_t* aad, size_t aad_len,
                    uint8_t* out)
{
    if (clen < 16) return false;

    size_t plen = clen - 16;
    const uint8_t* ct  = cipher;
    const uint8_t* tag = cipher + plen;

    // Generate Poly1305 key: first 32 bytes of ChaCha20 block 0
    uint32_t poly_block[16];
    chacha20_block(poly_block, key, nonce, 0);
    uint8_t poly_key[32];
    for (int i = 0; i < 8; i++) store32_le(poly_key + 4 * i, poly_block[i]);

    // Verify MAC
    uint8_t expected_tag[16];
    aead_mac(expected_tag, poly_key, aad, aad_len, ct, plen);
    if (!tag_eq(expected_tag, tag)) return false;

    // Decrypt
    chacha20_xor(key, nonce, counter, ct, plen, out);
    return true;
}

#undef ROTL32

} // namespace chacha20poly1305
