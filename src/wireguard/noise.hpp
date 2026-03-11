#pragma once
// WireGuard Noise_IKpsk2 protocol constants and types
// Based on WireGuard whitepaper and RFC 7748/8439

#include "../crypto/crypto.hpp"
#include <cstdint>
#include <cstring>
#include <array>

namespace wireguard {

// ---- Message type identifiers ----
static constexpr uint8_t MSG_HANDSHAKE_INIT     = 1;
static constexpr uint8_t MSG_HANDSHAKE_RESPONSE = 2;
static constexpr uint8_t MSG_COOKIE_REPLY       = 3;
static constexpr uint8_t MSG_DATA               = 4;

// ---- Size constants ----
static constexpr size_t NOISE_PUBLIC_KEY_LEN  = 32;
static constexpr size_t NOISE_SYMMETRIC_KEY_LEN = 32;
static constexpr size_t NOISE_TIMESTAMP_LEN   = 12;
static constexpr size_t NOISE_AUTHTAG_LEN     = 16;
static constexpr size_t NOISE_NONCE_LEN       = 12;

// Encrypted static key in handshake: 32 (pubkey) + 16 (tag) = 48
static constexpr size_t NOISE_ENCRYPTED_STATIC_LEN = 48;
// Encrypted timestamp: 12 + 16 = 28
static constexpr size_t NOISE_ENCRYPTED_TIMESTAMP_LEN = 28;
// Encrypted nothing (handshake response): 0 + 16 = 16
static constexpr size_t NOISE_ENCRYPTED_NOTHING_LEN = 16;

static constexpr size_t MAC_LEN = 16;

// ---- WireGuard protocol string constants ----
// These are hashed with BLAKE2s to produce the initial chaining key and hash

// Construction string: "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"
static const char NOISE_CONSTRUCTION[] = "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s";
// Identifier: "WireGuard v1 zx2c4 Jason@zx2c4.com"
static const char WIREGUARD_IDENTIFIER[] = "WireGuard v1 zx2c4 Jason@zx2c4.com";
// Label for mac1: "mac1----"
static const char LABEL_MAC1[] = "mac1----";
// Label for cookie: "cookie--"
static const char LABEL_COOKIE[] = "cookie--";

// ---- Handshake message structures ----
// These match the on-wire format exactly (packed, little-endian integers)

#pragma pack(push, 1)

// Handshake Initiation (type=1), total 148 bytes
struct MsgHandshakeInit {
    uint8_t  message_type;       // 1
    uint8_t  reserved[3];        // 0,0,0
    uint32_t sender_index;       // random local index
    uint8_t  unencrypted_ephemeral[32];      // ephemeral public key
    uint8_t  encrypted_static[32 + 16];     // AEAD(static public key)
    uint8_t  encrypted_timestamp[12 + 16];  // AEAD(TAI64N timestamp)
    uint8_t  mac1[16];
    uint8_t  mac2[16];
};
static_assert(sizeof(MsgHandshakeInit) == 148, "MsgHandshakeInit size mismatch");

// Handshake Response (type=2), total 92 bytes
struct MsgHandshakeResponse {
    uint8_t  message_type;       // 2
    uint8_t  reserved[3];
    uint32_t sender_index;       // remote's random index
    uint32_t receiver_index;     // our sender_index from initiation
    uint8_t  unencrypted_ephemeral[32];
    uint8_t  encrypted_nothing[16];   // AEAD(empty)
    uint8_t  mac1[16];
    uint8_t  mac2[16];
};
static_assert(sizeof(MsgHandshakeResponse) == 92, "MsgHandshakeResponse size mismatch");

// Data packet header
struct MsgData {
    uint8_t  message_type;       // 4
    uint8_t  reserved[3];
    uint32_t receiver_index;
    uint64_t counter;            // little-endian
    // followed by variable-length encrypted payload
};
static_assert(sizeof(MsgData) == 16, "MsgData size mismatch");

#pragma pack(pop)

// ---- Noise handshake state ----
struct NoiseHandshakeState {
    // Chaining key (32 bytes)
    crypto::Hash chaining_key{};
    // Handshake hash (32 bytes)
    crypto::Hash handshake_hash{};
    // Our ephemeral key pair
    crypto::Key  ephemeral_private{};
    crypto::Key  ephemeral_public{};
    // Remote's ephemeral public key
    crypto::Key  remote_ephemeral{};
    // Derived session keys (after handshake complete)
    crypto::Key  send_key{};
    crypto::Key  recv_key{};
    // Our local index for this session
    uint32_t     local_index = 0;
    // Remote index
    uint32_t     remote_index = 0;
    // Whether we are the initiator
    bool         is_initiator = false;
};

// ---- Session (transport) state ----
struct NoiseSession {
    crypto::Key  send_key{};
    crypto::Key  recv_key{};
    uint64_t     send_counter = 0;
    uint64_t     recv_counter = 0;
    uint32_t     local_index  = 0;
    uint32_t     remote_index = 0;
    bool         valid        = false;

    // Replay window: 64-bit sliding window for out-of-order detection
    // Protects against replay attacks
    static constexpr int WINDOW_SIZE = 64;
    uint64_t replay_window = 0;  // bitmask

    // Check and update replay window
    // Returns true if packet is acceptable (not a replay)
    bool check_replay(uint64_t counter) {
        if (counter == 0 && recv_counter == 0) {
            // First packet
            recv_counter = 0;
            replay_window = 1;
            return true;
        }
        if (counter + WINDOW_SIZE <= recv_counter) {
            // Too old
            return false;
        }
        if (counter > recv_counter) {
            // New max: slide window
            uint64_t shift = counter - recv_counter;
            if (shift >= WINDOW_SIZE) {
                replay_window = 0;
            } else {
                replay_window <<= shift;
            }
            recv_counter = counter;
            replay_window |= 1ULL;
            return true;
        }
        // Within window
        uint64_t diff = recv_counter - counter;
        uint64_t bit = 1ULL << diff;
        if (replay_window & bit) {
            return false;  // replay
        }
        replay_window |= bit;
        return true;
    }
};

// ---- TAI64N timestamp ----
// WireGuard timestamps are TAI64N: 8-byte seconds + 4-byte nanoseconds
// Both big-endian. Seconds are TAI64 (Unix + 10 + 37 leap seconds offset ≈ Unix + 10).
inline std::array<uint8_t, 12> make_tai64n_timestamp() {
    struct timespec ts{};
    clock_gettime(CLOCK_REALTIME, &ts);
    // TAI64 epoch offset: TAI = UTC + 37 (current leap seconds as of 2017) + 10
    // We use a simplified version: TAI64 = Unix + 10 + leap_seconds
    // WireGuard uses TAI64N but any monotonically increasing value works for our purposes
    uint64_t tai_sec = (uint64_t)ts.tv_sec + 10 + 37;  // TAI offset
    tai_sec += (1ULL << 62);  // TAI64 format: bit 62 set means "seconds after 1970"

    std::array<uint8_t, 12> stamp{};
    // Big-endian seconds
    stamp[0] = (uint8_t)(tai_sec >> 56);
    stamp[1] = (uint8_t)(tai_sec >> 48);
    stamp[2] = (uint8_t)(tai_sec >> 40);
    stamp[3] = (uint8_t)(tai_sec >> 32);
    stamp[4] = (uint8_t)(tai_sec >> 24);
    stamp[5] = (uint8_t)(tai_sec >> 16);
    stamp[6] = (uint8_t)(tai_sec >>  8);
    stamp[7] = (uint8_t)(tai_sec      );
    // Big-endian nanoseconds
    uint32_t ns = (uint32_t)ts.tv_nsec;
    stamp[8]  = (uint8_t)(ns >> 24);
    stamp[9]  = (uint8_t)(ns >> 16);
    stamp[10] = (uint8_t)(ns >>  8);
    stamp[11] = (uint8_t)(ns      );
    return stamp;
}

} // namespace wireguard
