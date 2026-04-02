#pragma once
#include "noise.hpp"
#include "../config/config.hpp"
#include <string>
#include <vector>
#include <cstdint>
#include <functional>
#include <atomic>
#include <memory>
#include <thread>
#include <mutex>
#include <chrono>
#include <netinet/in.h>

namespace wireguard {

// Callback types
using PacketCallback = std::function<void(const uint8_t* data, size_t len)>;

// Resolve "host:port" or "[host]:port" -> sockaddr_storage (IPv4 or IPv6)
bool resolve_endpoint(const std::string& endpoint, struct sockaddr_storage& addr, socklen_t& addr_len);

class WireGuardPeer {
public:
    WireGuardPeer(const config::PeerConfig& peer_config,
                  const crypto::Key& local_private_key,
                  const crypto::Key& local_public_key);
    ~WireGuardPeer();

    // Initialize the static handshake context (pre-computed values)
    void init_static_context();

    // Create a UDP socket bound to 0.0.0.0:0
    void create_socket();

    // Close the UDP socket
    void close_socket();

    // Perform WireGuard handshake (blocking, with timeout)
    // Returns true on success
    bool do_handshake(int timeout_ms = 5000);

    // Send a data packet (IP packet wrapped in WireGuard transport message)
    bool send_packet(const uint8_t* data, size_t len);

    // Receive a data packet from UDP, decrypt, return IP payload
    // Returns empty vector if no data / error
    std::vector<uint8_t> recv_packet();

    // Send keepalive (empty encrypted packet)
    bool send_keepalive();

    // Check if handshake is complete
    bool is_connected() const { return session_.valid; }

    // Get the UDP socket fd
    int socket_fd() const { return udp_fd_; }

    // Force re-handshake on next send
    void invalidate_session() {
        std::lock_guard<std::mutex> lk(session_mutex_);
        session_.valid = false;
    }

    const config::PeerConfig& config() const { return peer_config_; }

    // Time of last handshake
    std::chrono::steady_clock::time_point last_handshake_time() const {
        return last_handshake_time_;
    }

    // Whether keepalive is due
    bool keepalive_due() const;

    void update_keepalive_time() {
        last_keepalive_time_ = std::chrono::steady_clock::now();
    }

private:
    // Build handshake initiation message
    MsgHandshakeInit build_handshake_init();

    // Process handshake response, derive session keys
    bool process_handshake_response(const MsgHandshakeResponse& resp);

    // Compute mac1 for a message
    void compute_mac1(uint8_t* msg, size_t msg_len_without_macs, uint8_t* mac1_out);
    void compute_mac2(uint8_t* msg, size_t msg_len_without_macs, uint8_t* mac2_out);

    // Send junk packets for traffic obfuscation
    void send_junk_packets();

    // XOR message type with magic header
    uint32_t apply_magic_header(uint32_t type_field);

    const config::PeerConfig&  peer_config_;
    crypto::Key                local_private_;
    crypto::Key                local_public_;

    // Pre-computed static values
    crypto::Hash               static_chaining_key_{};  // hash of construction string
    crypto::Hash               static_hash_{};           // hash of (CK, identifier, responder_pk)
    crypto::Hash               mac1_key_{};              // BLAKE2s(LABEL_MAC1 || peer_pub)

    // Active handshake state
    NoiseHandshakeState        hs_{};

    // Active session
    NoiseSession               session_;
    mutable std::mutex         session_mutex_;

    // UDP socket to peer
    int                        udp_fd_ = -1;
    struct sockaddr_storage    peer_addr_{};
    socklen_t                  peer_addr_len_ = 0;

    // Timing
    std::chrono::steady_clock::time_point last_handshake_time_{};
    std::chrono::steady_clock::time_point last_keepalive_time_{};
};

} // namespace wireguard
