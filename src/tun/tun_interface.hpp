#pragma once
#include <string>
#include <vector>
#include <cstdint>
#include <functional>
#include <atomic>

namespace tun {

// Represents a macOS utun interface
// Created via PF_SYSTEM / SYSPROTO_CONTROL socket
class TunInterface {
public:
    TunInterface();
    ~TunInterface();

    // Open a utun interface. unit=-1 = let kernel choose.
    // Returns the interface name (e.g. "utun3")
    std::string open(int unit = -1);

    // Close and destroy the interface
    void close();

    // Configure the interface: set IP address, MTU, bring it up
    void configure(const std::string& local_ip,
                   const std::string& peer_ip,
                   const std::string& subnet_mask,
                   int mtu = 1420);

    // Read one packet from the TUN interface.
    // The 4-byte utun family header is stripped; raw IP packet is returned.
    // Returns empty vector on EOF/error (check is_open()).
    std::vector<uint8_t> read_packet();

    // Write one IP packet to TUN.
    // Automatically prepends the 4-byte AF_INET header.
    bool write_packet(const uint8_t* data, size_t len);
    bool write_packet(const std::vector<uint8_t>& pkt) {
        return write_packet(pkt.data(), pkt.size());
    }

    // File descriptor (for select/poll)
    int fd() const { return fd_; }

    bool is_open() const { return fd_ >= 0; }

    const std::string& name() const { return name_; }

private:
    int         fd_   = -1;
    std::string name_;
};

} // namespace tun
