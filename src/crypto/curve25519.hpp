#pragma once
// Standalone X25519 Diffie-Hellman (Curve25519) implementation
// Based on TweetNaCl 16-limb field arithmetic
// No external dependencies

#include <cstdint>
#include <cstring>

namespace curve25519 {

typedef long long gf[16];

static const gf _121665 = {0xDB41, 1};

static void fe_0(gf o) {
    memset(o, 0, sizeof(gf));
}

static void fe_1(gf o) {
    memset(o, 0, sizeof(gf));
    o[0] = 1;
}

static void fe_copy(gf o, const gf a) {
    memcpy(o, a, sizeof(gf));
}

static void carry25519(gf o) {
    int i;
    long long c;
    for (i = 0; i < 16; i++) {
        o[i] += (1LL << 16);
        c = o[i] >> 16;
        o[(i + 1) * (i < 15)] += c - 1 + 37 * (c - 1) * (i == 15);
        o[i] -= c << 16;
    }
}

static void fe_add(gf o, const gf a, const gf b) {
    for (int i = 0; i < 16; i++) o[i] = a[i] + b[i];
}

static void fe_sub(gf o, const gf a, const gf b) {
    for (int i = 0; i < 16; i++) o[i] = a[i] - b[i];
}

static void fe_mul(gf o, const gf a, const gf b) {
    long long t[31] = {};
    for (int i = 0; i < 16; i++)
        for (int j = 0; j < 16; j++)
            t[i + j] += a[i] * b[j];
    for (int i = 0; i < 15; i++) t[i] += 38 * t[i + 16];
    for (int i = 0; i < 16; i++) o[i] = t[i];
    carry25519(o);
    carry25519(o);
}

static void fe_sq(gf o, const gf a) {
    fe_mul(o, a, a);
}

static void fe_mul_small(gf o, const gf a, long long b) {
    for (int i = 0; i < 16; i++) o[i] = a[i] * b;
    carry25519(o);
    carry25519(o);
}

// Inversion via Fermat: a^(p-2) mod p where p = 2^255 - 19
static void fe_inv(gf o, const gf a) {
    gf c;
    fe_copy(c, a);
    // Use the addition chain for 2^255 - 21
    for (int i = 253; i >= 0; i--) {
        fe_sq(c, c);
        if (i != 2 && i != 4) fe_mul(c, c, a);
    }
    fe_copy(o, c);
}

// Conditional swap: if b==1, swap p and q
static void cswap(gf p, gf q, long long b) {
    long long t;
    long long mask = ~(b - 1);  // 0 if b==0, all-ones if b==1
    for (int i = 0; i < 16; i++) {
        t = mask & (p[i] ^ q[i]);
        p[i] ^= t;
        q[i] ^= t;
    }
}

// Pack a field element to 32 bytes (little-endian)
static void fe_pack(uint8_t out[32], gf n) {
    int i;
    long long m[16], t[16];
    memcpy(t, n, sizeof(gf));
    carry25519(t);
    carry25519(t);
    carry25519(t);
    for (int j = 0; j < 2; j++) {
        m[0] = t[0] - 0xFFED;
        for (i = 1; i < 15; i++) {
            m[i] = t[i] - 0xFFFF - ((m[i - 1] >> 16) & 1);
            m[i - 1] &= 0xFFFF;
        }
        m[15] = t[15] - 0x7FFF - ((m[14] >> 16) & 1);
        long long b = (m[15] >> 16) & 1;
        m[14] &= 0xFFFF;
        // cswap based on b
        long long mask2 = b - 1;  // 0xFFFF...FFFF if b==0 (no reduce needed), 0 if b==1
        for (i = 0; i < 16; i++) {
            t[i] ^= mask2 & (t[i] ^ m[i]);
        }
    }
    for (i = 0; i < 16; i++) {
        out[2 * i]     = (uint8_t)(t[i] & 0xFF);
        out[2 * i + 1] = (uint8_t)(t[i] >> 8);
    }
}

// Unpack 32 bytes to field element
static void fe_unpack(gf o, const uint8_t in[32]) {
    for (int i = 0; i < 16; i++) {
        o[i] = (long long)(in[2 * i]) | ((long long)(in[2 * i + 1]) << 8);
    }
    o[15] &= 0x7FFF;
}

// Montgomery ladder scalar multiplication
static void scalarmult(uint8_t out[32], const uint8_t scalar[32], const uint8_t point[32]) {
    uint8_t e[32];
    memcpy(e, scalar, 32);
    // Clamp scalar
    e[0]  &= 248;
    e[31] &= 127;
    e[31] |= 64;

    gf x1, x2, z2, x3, z3, tmp0, tmp1;

    fe_unpack(x1, point);
    fe_1(x2);
    fe_0(z2);
    fe_copy(x3, x1);
    fe_1(z3);

    long long swap = 0;

    for (int pos = 254; pos >= 0; pos--) {
        long long b = (e[pos / 8] >> (pos & 7)) & 1;
        swap ^= b;
        cswap(x2, x3, swap);
        cswap(z2, z3, swap);
        swap = b;

        // Montgomery step
        fe_sub(tmp0, x3, z3);
        fe_sub(tmp1, x2, z2);
        fe_add(x2, x2, z2);
        fe_add(z2, x3, z3);
        fe_mul(z3, tmp0, x2);
        fe_mul(z2, z2, tmp1);
        fe_sq(tmp0, tmp1);
        fe_sq(tmp1, x2);
        fe_add(x3, z3, z2);
        fe_sub(z2, z3, z2);
        fe_mul(x2, tmp1, tmp0);
        fe_sub(tmp1, tmp1, tmp0);
        fe_sq(z2, z2);
        fe_mul_small(z3, tmp1, 121665);
        fe_sq(x3, x3);
        fe_add(tmp0, tmp0, z3);
        fe_mul(z3, x1, z2);
        fe_mul(z2, tmp1, tmp0);
    }

    cswap(x2, x3, swap);
    cswap(z2, z3, swap);

    // out = x2 / z2
    gf z2inv;
    fe_inv(z2inv, z2);
    fe_mul(x2, x2, z2inv);
    fe_pack(out, x2);
}

// X25519: compute scalar * point
inline void x25519(uint8_t out[32], const uint8_t scalar[32], const uint8_t point[32]) {
    scalarmult(out, scalar, point);
}

// X25519 base point multiplication (base point u=9)
inline void x25519_base(uint8_t out[32], const uint8_t scalar[32]) {
    static const uint8_t basepoint[32] = {9};
    scalarmult(out, scalar, basepoint);
}

} // namespace curve25519
