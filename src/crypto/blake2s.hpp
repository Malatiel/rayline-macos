#pragma once
// BLAKE2s - complete standalone implementation
// Based on RFC 7693 and the BLAKE2 paper
// BLAKE2s uses 32-bit words, 10 rounds, max 256-bit output, max 32-byte key

#include <cstdint>
#include <cstddef>
#include <cstring>
#include <stdexcept>
#include <array>

namespace blake2s {

static constexpr size_t BLAKE2S_BLOCKBYTES   = 64;
static constexpr size_t BLAKE2S_OUTBYTES     = 32;
static constexpr size_t BLAKE2S_KEYBYTES     = 32;
static constexpr size_t BLAKE2S_SALTBYTES    = 8;
static constexpr size_t BLAKE2S_PERSONALBYTES= 8;

// BLAKE2s IV constants (first 8 primes' square roots, 32-bit)
static const uint32_t BLAKE2S_IV[8] = {
    0x6A09E667UL, 0xBB67AE85UL, 0x3C6EF372UL, 0xA54FF53AUL,
    0x510E527FUL, 0x9B05688CUL, 0x1F83D9ABUL, 0x5BE0CD19UL
};

// BLAKE2s sigma permutations (10 rounds, 16 entries each)
static const uint8_t BLAKE2S_SIGMA[10][16] = {
    {  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15 },
    { 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3 },
    { 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4 },
    {  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8 },
    {  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13 },
    {  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9 },
    { 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11 },
    { 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10 },
    {  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5 },
    { 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0 },
};

// Rotate right 32-bit
inline uint32_t rotr32(uint32_t x, unsigned n) {
    return (x >> n) | (x << (32 - n));
}

// Load/store little-endian 32-bit
inline uint32_t load32_le(const uint8_t* p) {
    return ((uint32_t)p[0])       |
           ((uint32_t)p[1] <<  8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

inline void store32_le(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)(v);
    p[1] = (uint8_t)(v >>  8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

// BLAKE2s parameter block (exactly 32 bytes as per RFC 7693)
// Byte offsets: 0=digest_length, 1=key_length, 2=fanout, 3=depth,
//               4-7=leaf_length, 8-11=node_offset, 12-13=xof_length,
//               14=node_depth, 15=inner_length, 16-23=salt, 24-31=personal
#pragma pack(push, 1)
struct blake2s_param {
    uint8_t  digest_length;                    // [0]
    uint8_t  key_length;                       // [1]
    uint8_t  fanout;                           // [2]
    uint8_t  depth;                            // [3]
    uint32_t leaf_length;                      // [4-7]
    uint32_t node_offset;                      // [8-11]
    uint16_t xof_length;                       // [12-13]
    uint8_t  node_depth;                       // [14]
    uint8_t  inner_length;                     // [15]
    uint8_t  salt[BLAKE2S_SALTBYTES];          // [16-23]
    uint8_t  personal[BLAKE2S_PERSONALBYTES];  // [24-31]
};
#pragma pack(pop)
static_assert(sizeof(blake2s_param) == 32, "blake2s_param must be 32 bytes");

struct blake2s_state {
    uint32_t h[8];
    uint32_t t[2];   // counter
    uint32_t f[2];   // finalization flags
    uint8_t  buf[BLAKE2S_BLOCKBYTES];
    size_t   buflen;
    uint8_t  outlen;
    uint8_t  last_node;
};

// Mixing function G
#define BLAKE2S_G(r, i, a, b, c, d) \
    do { \
        a = a + b + m[BLAKE2S_SIGMA[r][2*i+0]]; \
        d = rotr32(d ^ a, 16); \
        c = c + d; \
        b = rotr32(b ^ c, 12); \
        a = a + b + m[BLAKE2S_SIGMA[r][2*i+1]]; \
        d = rotr32(d ^ a, 8); \
        c = c + d; \
        b = rotr32(b ^ c, 7); \
    } while(0)

// One compression
inline void blake2s_compress(blake2s_state* S, const uint8_t block[BLAKE2S_BLOCKBYTES]) {
    uint32_t m[16];
    uint32_t v[16];

    for (int i = 0; i < 16; i++)
        m[i] = load32_le(block + i * sizeof(uint32_t));

    for (int i = 0; i < 8; i++)
        v[i] = S->h[i];

    v[ 8] = BLAKE2S_IV[0];
    v[ 9] = BLAKE2S_IV[1];
    v[10] = BLAKE2S_IV[2];
    v[11] = BLAKE2S_IV[3];
    v[12] = S->t[0] ^ BLAKE2S_IV[4];
    v[13] = S->t[1] ^ BLAKE2S_IV[5];
    v[14] = S->f[0] ^ BLAKE2S_IV[6];
    v[15] = S->f[1] ^ BLAKE2S_IV[7];

    for (int r = 0; r < 10; r++) {
        BLAKE2S_G(r, 0, v[ 0], v[ 4], v[ 8], v[12]);
        BLAKE2S_G(r, 1, v[ 1], v[ 5], v[ 9], v[13]);
        BLAKE2S_G(r, 2, v[ 2], v[ 6], v[10], v[14]);
        BLAKE2S_G(r, 3, v[ 3], v[ 7], v[11], v[15]);
        BLAKE2S_G(r, 4, v[ 0], v[ 5], v[10], v[15]);
        BLAKE2S_G(r, 5, v[ 1], v[ 6], v[11], v[12]);
        BLAKE2S_G(r, 6, v[ 2], v[ 7], v[ 8], v[13]);
        BLAKE2S_G(r, 7, v[ 3], v[ 4], v[ 9], v[14]);
    }

    for (int i = 0; i < 8; i++)
        S->h[i] = S->h[i] ^ v[i] ^ v[i+8];
}

#undef BLAKE2S_G

inline int blake2s_init_param(blake2s_state* S, const blake2s_param* P) {
    const uint8_t* p = (const uint8_t*)P;
    memset(S, 0, sizeof(blake2s_state));
    for (int i = 0; i < 8; i++)
        S->h[i] = BLAKE2S_IV[i];
    // XOR h[0..7] with param block (8 x 32-bit words)
    for (int i = 0; i < 8; i++)
        S->h[i] ^= load32_le(p + i * sizeof(uint32_t));
    S->outlen = P->digest_length;
    return 0;
}

inline int blake2s_init(blake2s_state* S, size_t outlen) {
    if (outlen == 0 || outlen > BLAKE2S_OUTBYTES) return -1;
    blake2s_param P{};
    P.digest_length = (uint8_t)outlen;
    P.key_length    = 0;
    P.fanout        = 1;
    P.depth         = 1;
    return blake2s_init_param(S, &P);
}

inline int blake2s_init_key(blake2s_state* S, size_t outlen, const void* key, size_t keylen) {
    if (outlen == 0 || outlen > BLAKE2S_OUTBYTES) return -1;
    if (!key || keylen == 0 || keylen > BLAKE2S_KEYBYTES) return -1;
    blake2s_param P{};
    P.digest_length = (uint8_t)outlen;
    P.key_length    = (uint8_t)keylen;
    P.fanout        = 1;
    P.depth         = 1;
    blake2s_init_param(S, &P);
    // Pad key to block, update
    uint8_t block[BLAKE2S_BLOCKBYTES] = {};
    memcpy(block, key, keylen);
    // increment counter and compress
    S->t[0] += BLAKE2S_BLOCKBYTES;
    if (S->t[0] < BLAKE2S_BLOCKBYTES) S->t[1]++;
    blake2s_compress(S, block);
    memset(block, 0, sizeof(block));
    return 0;
}

inline void blake2s_increment_counter(blake2s_state* S, uint32_t inc) {
    S->t[0] += inc;
    if (S->t[0] < inc) S->t[1]++;
}

inline int blake2s_update(blake2s_state* S, const void* in, size_t inlen) {
    if (!in || inlen == 0) return 0;
    const uint8_t* pin = (const uint8_t*)in;
    while (inlen > 0) {
        size_t left = S->buflen;
        size_t fill = BLAKE2S_BLOCKBYTES - left;
        if (inlen > fill) {
            // Fill buffer and compress
            memcpy(S->buf + left, pin, fill);
            blake2s_increment_counter(S, BLAKE2S_BLOCKBYTES);
            blake2s_compress(S, S->buf);
            S->buflen = 0;
            pin    += fill;
            inlen  -= fill;
        } else {
            memcpy(S->buf + left, pin, inlen);
            S->buflen += inlen;
            inlen = 0;
        }
    }
    return 0;
}

inline int blake2s_final(blake2s_state* S, void* out, size_t outlen) {
    if (!out || outlen < S->outlen) return -1;
    // Last block: set finalization flag
    S->f[0] = 0xFFFFFFFFUL;
    blake2s_increment_counter(S, (uint32_t)S->buflen);
    // Zero-pad last block
    memset(S->buf + S->buflen, 0, BLAKE2S_BLOCKBYTES - S->buflen);
    blake2s_compress(S, S->buf);
    // Serialize output
    uint8_t* pout = (uint8_t*)out;
    for (int i = 0; i < (int)S->outlen; i += 4) {
        int remaining = (int)S->outlen - i;
        if (remaining >= 4) {
            store32_le(pout + i, S->h[i/4]);
        } else {
            uint8_t tmp[4];
            store32_le(tmp, S->h[i/4]);
            memcpy(pout + i, tmp, remaining);
        }
    }
    memset(S, 0, sizeof(blake2s_state));
    return 0;
}

// All-in-one hash
inline int blake2s(void* out, size_t outlen,
                   const void* in,  size_t inlen,
                   const void* key, size_t keylen)
{
    blake2s_state S;
    int ret;
    if (keylen > 0) {
        ret = blake2s_init_key(&S, outlen, key, keylen);
    } else {
        ret = blake2s_init(&S, outlen);
    }
    if (ret < 0) return ret;
    blake2s_update(&S, in, inlen);
    blake2s_final(&S, out, outlen);
    return 0;
}

// Convenience wrappers returning arrays

inline std::array<uint8_t,32> hash(const void* data, size_t len) {
    std::array<uint8_t,32> out{};
    blake2s(out.data(), 32, data, len, nullptr, 0);
    return out;
}

inline std::array<uint8_t,32> mac(const void* key, size_t keylen, const void* data, size_t datalen) {
    std::array<uint8_t,32> out{};
    blake2s(out.data(), 32, data, datalen, key, keylen);
    return out;
}

// BLAKE2s-based HMAC-like construction for WireGuard HKDF
// WireGuard uses BLAKE2s as PRF for HKDF:
//   HMAC(key, data) = BLAKE2s(data, key=key, outlen=32)
inline std::array<uint8_t,32> hmac(const uint8_t* key, size_t keylen,
                                    const uint8_t* data, size_t datalen)
{
    std::array<uint8_t,32> out{};
    blake2s(out.data(), 32, data, datalen, key, keylen);
    return out;
}

} // namespace blake2s
