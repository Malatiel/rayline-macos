#include "../src/crypto/crypto.hpp"
#include "../src/wireguard/noise.hpp"
#include <cassert>
#include <iostream>
#include <string>
#include <cstring>

static int g_failed = 0;
#define CHECK(expr) do { \
    if (!(expr)) { \
        std::cerr << "FAIL [" << __LINE__ << "]: " << #expr << "\n"; \
        ++g_failed; \
    } \
} while(0)
#define CHECK_EQ(a, b) do { \
    auto _a = (a); auto _b = (b); \
    if (_a != _b) { \
        std::cerr << "FAIL [" << __LINE__ << "]: " << #a << " == " << #b \
                  << "  (got " << _a << " vs " << _b << ")\n"; \
        ++g_failed; \
    } \
} while(0)

// ── BLAKE2s ───────────────────────────────────────────────────────────────

static void test_blake2s_empty() {
    // BLAKE2s hash of empty string (RFC 7693 test vector)
    auto h = crypto::blake2s_hash(nullptr, 0);
    // Known: BLAKE2s("") = 69217a3079908094e11121d042354a7c1f55b6482ca1a51e1b250dfd1ed0eef9
    CHECK_EQ(h[0], 0x69);
    CHECK_EQ(h[1], 0x21);
    CHECK_EQ(h[31], 0xf9);
}

static void test_blake2s_abc() {
    // BLAKE2s("abc") = 508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982
    const uint8_t data[] = {'a', 'b', 'c'};
    auto h = crypto::blake2s_hash(data, 3);
    CHECK_EQ(h[0], 0x50);
    CHECK_EQ(h[1], 0x8c);
    CHECK_EQ(h[2], 0x5e);
}

static void test_blake2s_keyed() {
    // Keyed BLAKE2s should differ from unkeyed
    const uint8_t data[] = {1, 2, 3};
    const uint8_t key[32] = {0x42};
    auto h_unkeyed = crypto::blake2s_hash(data, 3);
    auto h_keyed = crypto::blake2s_mac(key, 32, data, 3);
    CHECK(h_unkeyed != h_keyed);
}

static void test_blake2s_hash2() {
    // hash2(a, b) should equal hash(a || b)
    const uint8_t a[] = {1, 2, 3};
    const uint8_t b[] = {4, 5, 6};
    auto h2 = crypto::blake2s_hash2(a, 3, b, 3);
    uint8_t ab[] = {1, 2, 3, 4, 5, 6};
    auto h_concat = crypto::blake2s_hash(ab, 6);
    CHECK(h2 == h_concat);
}

// ── HKDF ──────────────────────────────────────────────────────────────────

static void test_hkdf1_deterministic() {
    crypto::Hash ck{};
    ck[0] = 0xAA;
    const uint8_t ikm[] = {0xBB};
    auto r1 = crypto::hkdf1(ck, ikm, 1);
    auto r2 = crypto::hkdf1(ck, ikm, 1);
    CHECK(r1.out1 == r2.out1);
}

static void test_hkdf2_outputs_differ() {
    crypto::Hash ck{};
    ck[0] = 0x01;
    const uint8_t ikm[] = {0x02};
    auto r = crypto::hkdf2(ck, ikm, 1);
    CHECK(r.out1 != r.out2);
}

static void test_hkdf3_outputs_differ() {
    crypto::Hash ck{};
    ck[0] = 0x03;
    const uint8_t ikm[] = {0x04};
    auto r = crypto::hkdf3(ck, ikm, 1);
    CHECK(r.out1 != r.out2);
    CHECK(r.out2 != r.out3);
    CHECK(r.out1 != r.out3);
}

// ── ChaCha20-Poly1305 AEAD ───────────────────────────────────────────────

static void test_aead_roundtrip() {
    crypto::Key key{};
    key[0] = 0x42; key[31] = 0xFF;
    const uint8_t pt[] = "hello wireguard";
    const uint8_t aad[] = "additional data";

    auto ct = crypto::aead_encrypt(key, 1, pt, sizeof(pt) - 1, aad, sizeof(aad) - 1);
    CHECK_EQ(ct.size(), sizeof(pt) - 1 + crypto::MAC_SIZE);

    auto decrypted = crypto::aead_decrypt(key, 1, ct.data(), ct.size(), aad, sizeof(aad) - 1);
    CHECK_EQ(decrypted.size(), sizeof(pt) - 1);
    CHECK(memcmp(decrypted.data(), pt, sizeof(pt) - 1) == 0);
}

static void test_aead_wrong_key_fails() {
    crypto::Key key1{}, key2{};
    key1[0] = 0x01; key2[0] = 0x02;
    const uint8_t pt[] = "secret";

    auto ct = crypto::aead_encrypt(key1, 0, pt, 6, nullptr, 0);
    bool threw = false;
    try {
        crypto::aead_decrypt(key2, 0, ct.data(), ct.size(), nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    CHECK(threw);
}

static void test_aead_tampered_ciphertext_fails() {
    crypto::Key key{};
    key[0] = 0x99;
    const uint8_t pt[] = "data";

    auto ct = crypto::aead_encrypt(key, 0, pt, 4, nullptr, 0);
    ct[0] ^= 0xFF;  // tamper
    bool threw = false;
    try {
        crypto::aead_decrypt(key, 0, ct.data(), ct.size(), nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    CHECK(threw);
}

static void test_aead_wrong_counter_fails() {
    crypto::Key key{};
    key[0] = 0xAA;
    const uint8_t pt[] = "test";

    auto ct = crypto::aead_encrypt(key, 5, pt, 4, nullptr, 0);
    bool threw = false;
    try {
        crypto::aead_decrypt(key, 6, ct.data(), ct.size(), nullptr, 0);
    } catch (const std::runtime_error&) {
        threw = true;
    }
    CHECK(threw);
}

static void test_aead_empty_plaintext() {
    crypto::Key key{};
    key[0] = 0xBB;
    auto ct = crypto::aead_encrypt(key, 0, nullptr, 0, nullptr, 0);
    CHECK_EQ(ct.size(), (size_t)crypto::MAC_SIZE);
    auto pt = crypto::aead_decrypt(key, 0, ct.data(), ct.size(), nullptr, 0);
    CHECK_EQ(pt.size(), (size_t)0);
}

static void test_aead_zero_nonce_wrappers() {
    crypto::Key key{};
    key[5] = 0xCC;
    const uint8_t pt[] = "zero nonce";
    auto ct = crypto::aead_encrypt_zero_nonce(key, pt, 10, nullptr, 0);
    auto dec = crypto::aead_decrypt_zero_nonce(key, ct.data(), ct.size(), nullptr, 0);
    CHECK(memcmp(dec.data(), pt, 10) == 0);
}

// ── Curve25519 ────────────────────────────────────────────────────────────

static void test_keypair_generation() {
    crypto::Key priv, pub;
    crypto::generate_keypair_wg(priv, pub);
    // Public key should not be all zeros
    uint8_t acc = 0;
    for (auto b : pub) acc |= b;
    CHECK(acc != 0);
    // Private key should be clamped
    CHECK((priv[0] & 7) == 0);
    CHECK((priv[31] & 128) == 0);
    CHECK((priv[31] & 64) == 64);
}

static void test_dh_shared_secret() {
    // Alice and Bob DH
    crypto::Key a_priv, a_pub, b_priv, b_pub;
    crypto::generate_keypair_wg(a_priv, a_pub);
    crypto::generate_keypair_wg(b_priv, b_pub);

    auto shared_ab = crypto::dh(a_priv, b_pub);
    auto shared_ba = crypto::dh(b_priv, a_pub);
    CHECK(shared_ab == shared_ba);
}

static void test_public_from_private() {
    crypto::Key priv, pub;
    crypto::generate_keypair_wg(priv, pub);
    auto pub2 = crypto::public_from_private(priv);
    CHECK(pub == pub2);
}

// ── Base64 ────────────────────────────────────────────────────────────────

static void test_base64_roundtrip() {
    crypto::Key key;
    crypto::random_bytes(key.data(), 32);
    std::string encoded = crypto::base64_encode(key);
    auto decoded = crypto::base64_decode(encoded);
    CHECK_EQ(decoded.size(), (size_t)32);
    CHECK(memcmp(decoded.data(), key.data(), 32) == 0);
}

static void test_base64_key_from_base64() {
    crypto::Key original;
    crypto::random_bytes(original.data(), 32);
    std::string b64 = crypto::base64_encode(original);
    auto restored = crypto::key_from_base64(b64);
    CHECK(original == restored);
}

static void test_base64_invalid_length_throws() {
    bool threw = false;
    try {
        crypto::key_from_base64("AAAA");  // 3 bytes, not 32
    } catch (const std::runtime_error&) {
        threw = true;
    }
    CHECK(threw);
}

// ── Nonce construction ────────────────────────────────────────────────────

static void test_make_nonce_zero() {
    auto n = crypto::make_nonce(0);
    for (int i = 0; i < 12; i++) CHECK_EQ(n[i], 0);
}

static void test_make_nonce_one() {
    auto n = crypto::make_nonce(1);
    CHECK_EQ(n[0], 0); CHECK_EQ(n[1], 0); CHECK_EQ(n[2], 0); CHECK_EQ(n[3], 0);
    CHECK_EQ(n[4], 1);  // LE byte 0 of counter
    for (int i = 5; i < 12; i++) CHECK_EQ(n[i], 0);
}

static void test_make_nonce_large() {
    auto n = crypto::make_nonce(0x0102030405060708ULL);
    CHECK_EQ(n[4], 0x08); CHECK_EQ(n[5], 0x07); CHECK_EQ(n[6], 0x06); CHECK_EQ(n[7], 0x05);
    CHECK_EQ(n[8], 0x04); CHECK_EQ(n[9], 0x03); CHECK_EQ(n[10], 0x02); CHECK_EQ(n[11], 0x01);
}

// ── Noise replay window ──────────────────────────────────────────────────

static void test_replay_first_packet() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
}

static void test_replay_sequential() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
    CHECK(s.check_replay(1));
    CHECK(s.check_replay(2));
    CHECK(s.check_replay(3));
}

static void test_replay_duplicate_rejected() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
    CHECK(s.check_replay(1));
    CHECK(!s.check_replay(1));  // duplicate
    CHECK(!s.check_replay(0));  // duplicate
}

static void test_replay_out_of_order() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
    CHECK(s.check_replay(5));
    CHECK(s.check_replay(3));  // within window, not seen
    CHECK(s.check_replay(2));  // within window, not seen
    CHECK(!s.check_replay(3)); // already seen
}

static void test_replay_too_old() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
    CHECK(s.check_replay(100));  // jump ahead
    // Counter 0 is now 100 packets behind, window is 64
    CHECK(!s.check_replay(30));  // too old (100 - 30 = 70 > 64)
}

static void test_replay_window_boundary() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
    CHECK(s.check_replay(63));  // 63 - 0 = 63 < 64, within window
    CHECK(s.check_replay(1));   // within window
    CHECK(!s.check_replay(1));  // duplicate
}

static void test_replay_large_jump() {
    wireguard::NoiseSession s;
    CHECK(s.check_replay(0));
    CHECK(s.check_replay(1000));  // huge jump
    CHECK(s.check_replay(1001));
    CHECK(!s.check_replay(900));  // 1001 - 900 = 101 > 64, too old
}

// ── TAI64N timestamp ─────────────────────────────────────────────────────

static void test_tai64n_not_zero() {
    auto ts = wireguard::make_tai64n_timestamp();
    uint8_t acc = 0;
    for (auto b : ts) acc |= b;
    CHECK(acc != 0);
}

static void test_tai64n_monotonic() {
    auto ts1 = wireguard::make_tai64n_timestamp();
    auto ts2 = wireguard::make_tai64n_timestamp();
    // ts2 >= ts1 (memcmp on big-endian representation)
    CHECK(memcmp(ts2.data(), ts1.data(), 12) >= 0);
}

// ── Message struct sizes ─────────────────────────────────────────────────

static void test_message_struct_sizes() {
    CHECK_EQ(sizeof(wireguard::MsgHandshakeInit), (size_t)148);
    CHECK_EQ(sizeof(wireguard::MsgHandshakeResponse), (size_t)92);
    CHECK_EQ(sizeof(wireguard::MsgData), (size_t)16);
}

static void test_noise_constants() {
    CHECK_EQ(wireguard::NOISE_PUBLIC_KEY_LEN, (size_t)32);
    CHECK_EQ(wireguard::NOISE_SYMMETRIC_KEY_LEN, (size_t)32);
    CHECK_EQ(wireguard::NOISE_AUTHTAG_LEN, (size_t)16);
    CHECK_EQ(wireguard::NOISE_NONCE_LEN, (size_t)12);
    CHECK_EQ(wireguard::NOISE_ENCRYPTED_STATIC_LEN, (size_t)48);
    CHECK_EQ(wireguard::NOISE_ENCRYPTED_TIMESTAMP_LEN, (size_t)28);
    CHECK_EQ(wireguard::NOISE_ENCRYPTED_NOTHING_LEN, (size_t)16);
}

// ── main ──────────────────────────────────────────────────────────────────

int main() {
    // BLAKE2s
    test_blake2s_empty();
    test_blake2s_abc();
    test_blake2s_keyed();
    test_blake2s_hash2();
    // HKDF
    test_hkdf1_deterministic();
    test_hkdf2_outputs_differ();
    test_hkdf3_outputs_differ();
    // AEAD
    test_aead_roundtrip();
    test_aead_wrong_key_fails();
    test_aead_tampered_ciphertext_fails();
    test_aead_wrong_counter_fails();
    test_aead_empty_plaintext();
    test_aead_zero_nonce_wrappers();
    // Curve25519
    test_keypair_generation();
    test_dh_shared_secret();
    test_public_from_private();
    // Base64
    test_base64_roundtrip();
    test_base64_key_from_base64();
    test_base64_invalid_length_throws();
    // Nonce
    test_make_nonce_zero();
    test_make_nonce_one();
    test_make_nonce_large();
    // Replay window
    test_replay_first_packet();
    test_replay_sequential();
    test_replay_duplicate_rejected();
    test_replay_out_of_order();
    test_replay_too_old();
    test_replay_window_boundary();
    test_replay_large_jump();
    // TAI64N
    test_tai64n_not_zero();
    test_tai64n_monotonic();
    // Struct sizes
    test_message_struct_sizes();
    test_noise_constants();

    int total = 33;
    if (g_failed == 0) {
        std::cout << "All " << total << " wireguard tests passed.\n";
        return 0;
    }
    std::cerr << g_failed << " test(s) failed.\n";
    return 1;
}
