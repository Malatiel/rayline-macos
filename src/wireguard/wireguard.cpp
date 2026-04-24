#include "wireguard.hpp"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <sys/select.h>
#include <cstring>
#include <stdexcept>
#include <iostream>
#include <chrono>

namespace wireguard {

// ---- Resolve endpoint "host:port" or "[ipv6]:port" ----
bool resolve_endpoint(const std::string& endpoint, struct sockaddr_storage& addr, socklen_t& addr_len) {
    std::string host, port_str;

    // Parse bracketed IPv6: [::1]:51820
    if (!endpoint.empty() && endpoint[0] == '[') {
        auto bracket = endpoint.find(']');
        if (bracket == std::string::npos) return false;
        host = endpoint.substr(1, bracket - 1);
        if (bracket + 1 >= endpoint.size() || endpoint[bracket + 1] != ':') return false;
        port_str = endpoint.substr(bracket + 2);
    } else {
        auto colon = endpoint.rfind(':');
        if (colon == std::string::npos) return false;
        host = endpoint.substr(0, colon);
        port_str = endpoint.substr(colon + 1);
    }

    memset(&addr, 0, sizeof(addr));

    // DNS lookup supporting both IPv4 and IPv6
    struct addrinfo hints{}, *res = nullptr;
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    int rc = getaddrinfo(host.c_str(), port_str.c_str(), &hints, &res);
    if (rc != 0 || !res) return false;

    memcpy(&addr, res->ai_addr, res->ai_addrlen);
    addr_len = res->ai_addrlen;
    freeaddrinfo(res);
    return true;
}

// ---- WireGuardPeer implementation ----

WireGuardPeer::WireGuardPeer(const config::PeerConfig& peer_config,
                             const crypto::Key& local_private_key,
                             const crypto::Key& local_public_key)
    : peer_config_(peer_config)
    , local_private_(local_private_key)
    , local_public_(local_public_key)
{
    init_static_context();
}

WireGuardPeer::~WireGuardPeer() {
    close_socket();
}

void WireGuardPeer::init_static_context() {
    // Compute the initial chaining key:
    //   CK = BLAKE2s(NOISE_CONSTRUCTION)
    static_chaining_key_ = crypto::blake2s_hash(
        (const uint8_t*)NOISE_CONSTRUCTION,
        strlen(NOISE_CONSTRUCTION)
    );

    // Compute the initial hash:
    //   H = BLAKE2s(CK || WIREGUARD_IDENTIFIER)
    static_hash_ = crypto::blake2s_hash2(
        static_chaining_key_.data(), static_chaining_key_.size(),
        (const uint8_t*)WIREGUARD_IDENTIFIER, strlen(WIREGUARD_IDENTIFIER)
    );

    // Mix responder (peer) public key into hash:
    //   H = BLAKE2s(H || peer_public_key)
    static_hash_ = crypto::blake2s_hash2(
        static_hash_.data(), static_hash_.size(),
        peer_config_.public_key.data(), peer_config_.public_key.size()
    );

    // Compute mac1 key: BLAKE2s(LABEL_MAC1 || peer_public_key)
    std::vector<uint8_t> mac1_input;
    mac1_input.resize(strlen(LABEL_MAC1) + 32);
    memcpy(mac1_input.data(), LABEL_MAC1, strlen(LABEL_MAC1));
    memcpy(mac1_input.data() + strlen(LABEL_MAC1),
           peer_config_.public_key.data(), 32);
    mac1_key_ = crypto::blake2s_hash(mac1_input.data(), mac1_input.size());
}

void WireGuardPeer::create_socket() {
    if (udp_fd_ >= 0) return;

    // Resolve endpoint (IPv4 or IPv6)
    if (!resolve_endpoint(peer_config_.endpoint, peer_addr_, peer_addr_len_)) {
        throw std::runtime_error("Failed to resolve endpoint: " + peer_config_.endpoint);
    }

    int af = peer_addr_.ss_family;
    udp_fd_ = ::socket(af, SOCK_DGRAM, IPPROTO_UDP);
    if (udp_fd_ < 0) {
        throw std::runtime_error(std::string("socket(UDP) failed: ") + strerror(errno));
    }

    std::cout << "[WG] Created UDP socket fd=" << udp_fd_
              << " (" << (af == AF_INET6 ? "IPv6" : "IPv4") << ")"
              << " -> " << peer_config_.endpoint << std::endl;
}

void WireGuardPeer::close_socket() {
    if (udp_fd_ >= 0) {
        ::close(udp_fd_);
        udp_fd_ = -1;
    }
}

void WireGuardPeer::send_junk_packets() {
    const auto& amn = peer_config_.obfs;
    if (amn.jc <= 0) return;

    std::cout << "[WG-OBFS] Sending " << amn.jc << " junk packets" << std::endl;

    for (int i = 0; i < amn.jc; i++) {
        int jsize = amn.jmin;
        if (amn.jmax > amn.jmin) {
            jsize += rand() % (amn.jmax - amn.jmin + 1);
        }
        std::vector<uint8_t> junk(jsize);
        crypto::random_bytes(junk.data(), jsize);
        // Overwrite first 4 bytes with a magic/random type to confuse DPI
        if (jsize >= 4) {
            uint32_t fake_type = 0;
            crypto::random_bytes((uint8_t*)&fake_type, 4);
            memcpy(junk.data(), &fake_type, 4);
        }
        sendto(udp_fd_, junk.data(), jsize, 0,
               (struct sockaddr*)&peer_addr_, peer_addr_len_);
    }
}

uint32_t WireGuardPeer::apply_magic_header(uint32_t type_field) {
    const auto& amn = peer_config_.obfs;
    if (!amn.enabled()) return type_field;

    // XORs the type field with magic headers
    uint8_t msg_type = type_field & 0xFF;
    uint32_t magic = 0;
    switch (msg_type) {
        case MSG_HANDSHAKE_INIT:     magic = amn.h1; break;
        case MSG_HANDSHAKE_RESPONSE: magic = amn.h2; break;
        case MSG_COOKIE_REPLY:       magic = amn.h3; break;
        case MSG_DATA:               magic = amn.h4; break;
        default: break;
    }
    return type_field ^ magic;
}

void WireGuardPeer::compute_mac1(uint8_t* msg, size_t msg_len_without_macs, uint8_t* mac1_out) {
    // mac1 = BLAKE2s(key=mac1_key, data=msg[0..len_without_macs], outlen=16)
    blake2s::blake2s(mac1_out, 16, msg, msg_len_without_macs,
                     mac1_key_.data(), 32);
}

void WireGuardPeer::compute_mac2(uint8_t* msg, size_t msg_len_without_macs, uint8_t* mac2_out) {
    // mac2 = 0 when no cookie (typical case for first connection)
    memset(mac2_out, 0, 16);
    (void)msg;
    (void)msg_len_without_macs;
}

MsgHandshakeInit WireGuardPeer::build_handshake_init() {
    // Generate local index
    crypto::random_bytes((uint8_t*)&hs_.local_index, 4);

    // Generate ephemeral key pair
    crypto::generate_keypair_wg(hs_.ephemeral_private, hs_.ephemeral_public);

    // Initialize handshake state
    hs_.chaining_key   = static_chaining_key_;
    hs_.handshake_hash = static_hash_;
    hs_.is_initiator   = true;

    // === Noise IKpsk2 Initiation ===
    // Reference: WireGuard whitepaper Section 5.4

    MsgHandshakeInit msg{};
    msg.message_type = MSG_HANDSHAKE_INIT;
    msg.sender_index = hs_.local_index;

    // 1. e: ephemeral
    //    msg.unencrypted_ephemeral = e_pub
    memcpy(msg.unencrypted_ephemeral, hs_.ephemeral_public.data(), 32);

    //    CK = HKDF1(CK, e_pub)
    auto r1 = crypto::hkdf1(hs_.chaining_key, hs_.ephemeral_public.data(), 32);
    hs_.chaining_key = r1.out1;

    //    H = BLAKE2s(H || e_pub)
    hs_.handshake_hash = crypto::blake2s_hash2(
        hs_.handshake_hash.data(), 32,
        hs_.ephemeral_public.data(), 32
    );

    // 2. es: DH(e_priv, s_pub_responder)
    auto es = crypto::dh(hs_.ephemeral_private, peer_config_.public_key);

    //    CK, k = HKDF2(CK, es)
    auto r2 = crypto::hkdf2(hs_.chaining_key, es.data(), 32);
    hs_.chaining_key = r2.out1;
    crypto::Key k_es = r2.out2;

    // 3. s: encrypt static
    //    msg.encrypted_static = AEAD(k, 0, s_pub_initiator, H)
    auto enc_static = crypto::aead_encrypt_zero_nonce(
        k_es,
        local_public_.data(), 32,
        hs_.handshake_hash.data(), 32
    );
    memcpy(msg.encrypted_static, enc_static.data(), 48);

    //    H = BLAKE2s(H || encrypted_static)
    hs_.handshake_hash = crypto::blake2s_hash2(
        hs_.handshake_hash.data(), 32,
        enc_static.data(), 48
    );

    // 4. ss: DH(s_priv_initiator, s_pub_responder)
    auto ss = crypto::dh(local_private_, peer_config_.public_key);

    //    CK, k = HKDF2(CK, ss)
    auto r3 = crypto::hkdf2(hs_.chaining_key, ss.data(), 32);
    hs_.chaining_key = r3.out1;
    crypto::Key k_ss = r3.out2;

    // 5. timestamp: encrypt TAI64N timestamp
    auto ts = make_tai64n_timestamp();
    auto enc_ts = crypto::aead_encrypt_zero_nonce(
        k_ss,
        ts.data(), ts.size(),
        hs_.handshake_hash.data(), 32
    );
    memcpy(msg.encrypted_timestamp, enc_ts.data(), 28);

    //    H = BLAKE2s(H || encrypted_timestamp)
    hs_.handshake_hash = crypto::blake2s_hash2(
        hs_.handshake_hash.data(), 32,
        enc_ts.data(), 28
    );

    // 6. Compute mac1 (over msg without mac1 and mac2)
    //    mac1_key = BLAKE2s(LABEL_MAC1 || responder_pub)
    //    mac1 = BLAKE2s(key=mac1_key, data=msg[0..116])
    constexpr size_t mac1_offset = offsetof(MsgHandshakeInit, mac1);
    compute_mac1((uint8_t*)&msg, mac1_offset, msg.mac1);

    // 7. mac2 = 0 (no cookie)
    constexpr size_t mac2_offset = offsetof(MsgHandshakeInit, mac2);
    compute_mac2((uint8_t*)&msg, mac2_offset, msg.mac2);

    return msg;
}

bool WireGuardPeer::process_handshake_response(const MsgHandshakeResponse& resp) {
    // Verify this response is for our initiation
    if (resp.receiver_index != hs_.local_index) {
        std::cerr << "[WG] Response receiver_index mismatch: "
                  << resp.receiver_index << " vs " << hs_.local_index << std::endl;
        return false;
    }

    hs_.remote_index = resp.sender_index;

    // Re-use handshake hash and chaining key from initiation state
    crypto::Hash H  = hs_.handshake_hash;
    crypto::Hash CK = hs_.chaining_key;

    // 1. e: remote ephemeral
    crypto::Key re{};
    memcpy(re.data(), resp.unencrypted_ephemeral, 32);
    hs_.remote_ephemeral = re;

    //    CK = HKDF1(CK, re)
    auto r1 = crypto::hkdf1(CK, re.data(), 32);
    CK = r1.out1;

    //    H = BLAKE2s(H || re)
    H = crypto::blake2s_hash2(H.data(), 32, re.data(), 32);

    // 2. ee: DH(e_priv, re)
    auto ee = crypto::dh(hs_.ephemeral_private, re);

    //    CK = HKDF1(CK, ee)
    auto r2 = crypto::hkdf1(CK, ee.data(), 32);
    CK = r2.out1;

    // 3. se: DH(s_priv, re)
    auto se = crypto::dh(local_private_, re);

    //    CK = HKDF1(CK, se)
    auto r3 = crypto::hkdf1(CK, se.data(), 32);
    CK = r3.out1;

    // 4. psk: mix pre-shared key (or zeros if none)
    crypto::Key psk{};
    if (peer_config_.preshared_key) {
        psk = *peer_config_.preshared_key;
    }

    //    CK, T, k = HKDF3(CK, psk)
    auto r4 = crypto::hkdf3(CK, psk.data(), 32);
    CK = r4.out1;
    crypto::Hash T = r4.out2;
    crypto::Key  k = r4.out3;

    //    H = BLAKE2s(H || T)
    H = crypto::blake2s_hash2(H.data(), 32, T.data(), 32);

    // 5. Decrypt "nothing"
    //    AEAD(k, 0, empty, H)
    try {
        auto decrypted = crypto::aead_decrypt_zero_nonce(
            k,
            resp.encrypted_nothing, 16,
            H.data(), 32
        );
        // decrypted should be empty (0 bytes)
    } catch (std::exception& e) {
        std::cerr << "[WG] Handshake response decryption failed: " << e.what() << std::endl;
        return false;
    }

    //    H = BLAKE2s(H || encrypted_nothing)
    H = crypto::blake2s_hash2(H.data(), 32, resp.encrypted_nothing, 16);

    // 6. Derive transport keys
    //    send_key, recv_key = HKDF2(CK, empty)
    auto r5 = crypto::hkdf2(CK, nullptr, 0);

    // Initiator sends on out1, receives on out2
    std::lock_guard<std::mutex> lk(session_mutex_);
    session_.send_key     = r5.out1;
    session_.recv_key     = r5.out2;
    session_.send_counter = 0;
    session_.recv_counter = 0;
    session_.replay_window = 0;
    session_.local_index  = hs_.local_index;
    session_.remote_index = hs_.remote_index;
    session_.valid        = true;

    last_handshake_time_ = std::chrono::steady_clock::now();
    last_keepalive_time_ = last_handshake_time_;

    std::cout << "[WG] Handshake complete. Session established." << std::endl;
    return true;
}

bool WireGuardPeer::do_handshake(int timeout_ms) {
    if (udp_fd_ < 0) {
        throw std::runtime_error("Socket not created before handshake");
    }

    // Obfuscation: send junk packets before handshake
    send_junk_packets();

    // Build and send initiation
    MsgHandshakeInit init_msg = build_handshake_init();

    // Apply magic header XOR (obfuscation)
    if (peer_config_.obfs.enabled()) {
        uint32_t type_field;
        memcpy(&type_field, &init_msg, 4);
        type_field = apply_magic_header(type_field);
        memcpy(&init_msg, &type_field, 4);
    }

    // s1 padding: append extra random bytes after the message
    std::vector<uint8_t> send_buf(sizeof(init_msg));
    memcpy(send_buf.data(), &init_msg, sizeof(init_msg));
    if (peer_config_.obfs.s1 > 0) {
        size_t old_size = send_buf.size();
        send_buf.resize(old_size + peer_config_.obfs.s1);
        crypto::random_bytes(send_buf.data() + old_size, peer_config_.obfs.s1);
    }

    ssize_t sent = sendto(udp_fd_, send_buf.data(), send_buf.size(), 0,
                          (struct sockaddr*)&peer_addr_, peer_addr_len_);
    if (sent < 0) {
        throw std::runtime_error(std::string("sendto handshake init failed: ") + strerror(errno));
    }
    std::cout << "[WG] Sent handshake initiation (" << sent << " bytes)" << std::endl;

    // Wait for response with timeout
    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(timeout_ms);

    while (std::chrono::steady_clock::now() < deadline) {
        fd_set rset;
        FD_ZERO(&rset);
        FD_SET(udp_fd_, &rset);

        auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
            deadline - std::chrono::steady_clock::now()
        ).count();
        if (remaining <= 0) break;

        struct timeval tv{};
        tv.tv_sec  = remaining / 1000000;
        tv.tv_usec = remaining % 1000000;

        int ready = select(udp_fd_ + 1, &rset, nullptr, nullptr, &tv);
        if (ready < 0) {
            if (errno == EINTR) continue;
            throw std::runtime_error(std::string("select failed: ") + strerror(errno));
        }
        if (ready == 0) break;  // timeout

        uint8_t buf[4096];
        struct sockaddr_storage from{};
        socklen_t fromlen = sizeof(from);
        ssize_t n = recvfrom(udp_fd_, buf, sizeof(buf), 0,
                             (struct sockaddr*)&from, &fromlen);
        if (n < 0) continue;

        if (n < 4) continue;

        uint8_t msg_type = buf[0];

        // Handle magic header (reverse XOR)
        if (peer_config_.obfs.enabled()) {
            uint32_t type_field;
            memcpy(&type_field, buf, 4);
            // Try to identify by XOR with h2 (response magic)
            uint32_t decoded = type_field ^ peer_config_.obfs.h2;
            if ((decoded & 0xFF) == MSG_HANDSHAKE_RESPONSE) {
                memcpy(buf, &decoded, 4);
                msg_type = MSG_HANDSHAKE_RESPONSE;
            }
        }

        if (msg_type != MSG_HANDSHAKE_RESPONSE) {
            std::cout << "[WG] Received unexpected message type " << (int)msg_type
                      << " during handshake, ignoring" << std::endl;
            continue;
        }

        if ((size_t)n < sizeof(MsgHandshakeResponse)) {
            std::cerr << "[WG] Response message too short: " << n << std::endl;
            continue;
        }

        MsgHandshakeResponse resp{};
        memcpy(&resp, buf, sizeof(resp));

        if (process_handshake_response(resp)) {
            return true;
        }
    }

    std::cerr << "[WG] Handshake timed out after " << timeout_ms << "ms" << std::endl;
    return false;
}

bool WireGuardPeer::send_packet(const uint8_t* data, size_t len) {
    std::lock_guard<std::mutex> lk(session_mutex_);
    if (!session_.valid) return false;
    if (udp_fd_ < 0) return false;

    // Encrypt the IP packet
    uint64_t counter = session_.send_counter++;

    std::vector<uint8_t> ct;
    try {
        ct = crypto::aead_encrypt(session_.send_key, counter, data, len, nullptr, 0);
    } catch (std::exception& e) {
        std::cerr << "[WG] Encrypt failed: " << e.what() << std::endl;
        return false;
    }

    // Build transport message header
    MsgData hdr{};
    hdr.message_type   = MSG_DATA;
    hdr.receiver_index = session_.remote_index;
    hdr.counter        = counter;

    // Apply magic header
    if (peer_config_.obfs.enabled()) {
        uint32_t type_field;
        memcpy(&type_field, &hdr, 4);
        type_field = apply_magic_header(type_field);
        memcpy(&hdr, &type_field, 4);
    }

    // Assemble: header + ciphertext
    std::vector<uint8_t> pkt(sizeof(MsgData) + ct.size());
    memcpy(pkt.data(), &hdr, sizeof(MsgData));
    memcpy(pkt.data() + sizeof(MsgData), ct.data(), ct.size());

    ssize_t sent = sendto(udp_fd_, pkt.data(), pkt.size(), 0,
                          (struct sockaddr*)&peer_addr_, peer_addr_len_);
    if (sent < 0) {
        std::cerr << "[WG] sendto data failed: " << strerror(errno) << std::endl;
        return false;
    }
    return true;
}

std::vector<uint8_t> WireGuardPeer::recv_packet() {
    if (udp_fd_ < 0) return {};

    uint8_t buf[65536 + 32];
    struct sockaddr_storage from{};
    socklen_t fromlen = sizeof(from);

    ssize_t n = recvfrom(udp_fd_, buf, sizeof(buf), MSG_DONTWAIT,
                         (struct sockaddr*)&from, &fromlen);
    if (n < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return {};
        std::cerr << "[WG] recvfrom failed: " << strerror(errno) << std::endl;
        return {};
    }

    if (n < 4) return {};

    uint8_t msg_type = buf[0];

    // Handle magic header
    if (peer_config_.obfs.enabled()) {
        uint32_t type_field;
        memcpy(&type_field, buf, 4);
        uint32_t decoded = type_field ^ peer_config_.obfs.h4;
        if ((decoded & 0xFF) == MSG_DATA) {
            memcpy(buf, &decoded, 4);
            msg_type = MSG_DATA;
        }
    }

    if (msg_type != MSG_DATA) {
        // Could be a handshake response or cookie; handle in do_handshake
        return {};
    }

    if ((size_t)n < sizeof(MsgData) + 16) {
        std::cerr << "[WG] Data packet too short: " << n << std::endl;
        return {};
    }

    MsgData hdr{};
    memcpy(&hdr, buf, sizeof(MsgData));

    uint64_t counter = hdr.counter;

    const uint8_t* ct = buf + sizeof(MsgData);
    size_t ct_len     = n - sizeof(MsgData);

    std::lock_guard<std::mutex> lk(session_mutex_);
    if (!session_.valid) return {};

    // Verify this is for us
    if (hdr.receiver_index != session_.local_index) {
        // Could be an old session or stale packet
        return {};
    }

    // Replay protection: only mutate the replay window after AEAD succeeds.
    if (!session_.replay_would_accept(counter)) {
        std::cerr << "[WG] Replay attack detected (counter=" << counter << ")" << std::endl;
        return {};
    }

    // Decrypt
    std::vector<uint8_t> plaintext;
    try {
        plaintext = crypto::aead_decrypt(session_.recv_key, counter,
                                         ct, ct_len, nullptr, 0);
    } catch (std::exception& e) {
        std::cerr << "[WG] Decrypt failed: " << e.what() << std::endl;
        return {};
    }

    session_.update_replay_window(counter);
    return plaintext;
}

bool WireGuardPeer::send_keepalive() {
    // Send an empty encrypted packet (WireGuard keepalive)
    std::lock_guard<std::mutex> lk(session_mutex_);
    if (!session_.valid || udp_fd_ < 0) return false;

    uint64_t counter = session_.send_counter++;
    std::vector<uint8_t> ct;
    try {
        ct = crypto::aead_encrypt(session_.send_key, counter, nullptr, 0, nullptr, 0);
    } catch (...) {
        return false;
    }

    MsgData hdr{};
    hdr.message_type   = MSG_DATA;
    hdr.receiver_index = session_.remote_index;
    hdr.counter        = counter;

    if (peer_config_.obfs.enabled()) {
        uint32_t type_field;
        memcpy(&type_field, &hdr, 4);
        type_field = apply_magic_header(type_field);
        memcpy(&hdr, &type_field, 4);
    }

    std::vector<uint8_t> pkt(sizeof(MsgData) + ct.size());
    memcpy(pkt.data(), &hdr, sizeof(MsgData));
    memcpy(pkt.data() + sizeof(MsgData), ct.data(), ct.size());

    sendto(udp_fd_, pkt.data(), pkt.size(), 0,
           (struct sockaddr*)&peer_addr_, peer_addr_len_);
    return true;
}

bool WireGuardPeer::keepalive_due() const {
    if (peer_config_.persistent_keepalive <= 0) return false;
    if (!session_.valid) return false;

    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        now - last_keepalive_time_
    ).count();

    return elapsed >= peer_config_.persistent_keepalive;
}

} // namespace wireguard
