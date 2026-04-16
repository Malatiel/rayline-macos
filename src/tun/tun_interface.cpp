#include "tun_interface.hpp"

#include <sys/socket.h>
#include <sys/kern_control.h>
#include <sys/sys_domain.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <net/if.h>
#include <arpa/inet.h>

#include <unistd.h>
#include <cstring>
#include <stdexcept>
#include <iostream>
#include <vector>

// macOS utun control name
#define UTUN_CONTROL_NAME "com.apple.net.utun_control"
#define UTUN_OPT_IFNAME   2

namespace tun {

static int run_argv(const std::vector<std::string>& args) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        std::vector<const char*> argv;
        for (auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);
        execvp(argv[0], const_cast<char* const*>(argv.data()));
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}


TunInterface::TunInterface() : fd_(-1) {}

TunInterface::~TunInterface() {
    close();
}

std::string TunInterface::open(int unit) {
    if (fd_ >= 0) {
        throw std::runtime_error("TUN interface already open");
    }

    // Create a PF_SYSTEM / SYSPROTO_CONTROL socket
    fd_ = ::socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
    if (fd_ < 0) {
        throw std::runtime_error(std::string("socket(PF_SYSTEM) failed: ") + strerror(errno));
    }

    // Look up the control ID for UTUN_CONTROL_NAME
    struct ctl_info ctlInfo{};
    memset(&ctlInfo, 0, sizeof(ctlInfo));
    strncpy(ctlInfo.ctl_name, UTUN_CONTROL_NAME, sizeof(ctlInfo.ctl_name) - 1);

    if (ioctl(fd_, CTLIOCGINFO, &ctlInfo) < 0) {
        ::close(fd_);
        fd_ = -1;
        throw std::runtime_error(std::string("ioctl(CTLIOCGINFO) failed: ") + strerror(errno));
    }

    // Connect to the utun control
    struct sockaddr_ctl sc{};
    sc.sc_len     = sizeof(sc);
    sc.sc_family  = AF_SYSTEM;
    sc.ss_sysaddr = AF_SYS_CONTROL;
    sc.sc_id      = ctlInfo.ctl_id;
    // unit 0 means "utun0"; unit N means "utunN"; 0 special = auto
    sc.sc_unit    = (unit >= 0) ? (uint32_t)(unit + 1) : 0;

    if (::connect(fd_, (struct sockaddr*)&sc, sizeof(sc)) < 0) {
        ::close(fd_);
        fd_ = -1;
        throw std::runtime_error(std::string("connect(utun) failed: ") + strerror(errno));
    }

    // Get the assigned interface name
    char ifname[IFNAMSIZ + 1] = {};
    socklen_t ifname_len = sizeof(ifname);
    if (getsockopt(fd_, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, ifname, &ifname_len) < 0) {
        ::close(fd_);
        fd_ = -1;
        throw std::runtime_error(std::string("getsockopt(UTUN_OPT_IFNAME) failed: ") + strerror(errno));
    }

    name_ = std::string(ifname);
    std::cout << "[TUN] Opened interface: " << name_ << " (fd=" << fd_ << ")" << std::endl;
    return name_;
}

void TunInterface::close() {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
        if (!name_.empty()) {
            std::cout << "[TUN] Closed interface: " << name_ << std::endl;
        }
        name_.clear();
    }
}

static bool is_valid_ip_or_mask(const std::string& s) {
    if (s.empty() || s.size() > 45) return false;
    for (unsigned char c : s) {
        if (!isdigit(c) && c != '.' && c != ':' &&
            !(c >= 'a' && c <= 'f') && !(c >= 'A' && c <= 'F'))
            return false;
    }
    return true;
}

void TunInterface::configure(const std::string& local_ip,
                              const std::string& peer_ip,
                              const std::string& subnet_mask,
                              int mtu)
{
    if (fd_ < 0 || name_.empty()) {
        throw std::runtime_error("TUN interface not open");
    }

    if (!is_valid_ip_or_mask(local_ip) || !is_valid_ip_or_mask(peer_ip) ||
        !is_valid_ip_or_mask(subnet_mask)) {
        throw std::runtime_error("Invalid IP address in TUN configure");
    }

    // Configure the utun interface via ifconfig (no shell)
    std::cout << "[TUN] ifconfig " << name_ << " inet " << local_ip
              << " " << peer_ip << " netmask " << subnet_mask << " up" << std::endl;
    int rc = run_argv({"ifconfig", name_, "inet", local_ip, peer_ip,
                       "netmask", subnet_mask, "up"});
    if (rc != 0) {
        throw std::runtime_error("ifconfig failed (rc=" + std::to_string(rc) + ")");
    }

    // Set MTU
    std::cout << "[TUN] ifconfig " << name_ << " mtu " << mtu << std::endl;
    rc = run_argv({"ifconfig", name_, "mtu", std::to_string(mtu)});
    if (rc != 0) {
        std::cerr << "[TUN] Warning: failed to set MTU" << std::endl;
    }
}

std::vector<uint8_t> TunInterface::read_packet() {
    if (fd_ < 0) return {};

    // Max IP packet + 4-byte utun family header
    uint8_t buf[65536 + 4];
    ssize_t n = ::read(fd_, buf, sizeof(buf));
    if (n < 0) {
        if (errno == EINTR || errno == EAGAIN) return {};
        std::cerr << "[TUN] read error: " << strerror(errno) << std::endl;
        return {};
    }
    if (n < 4) {
        // Too short to contain the family header
        return {};
    }

    // First 4 bytes are the address family (big-endian uint32)
    // We skip them and return raw IP
    std::vector<uint8_t> pkt(buf + 4, buf + n);
    return pkt;
}

bool TunInterface::write_packet(const uint8_t* data, size_t len) {
    if (fd_ < 0) return false;
    if (len == 0) return true;

    // Determine address family from IP version
    uint8_t version = (data[0] >> 4) & 0x0F;
    uint32_t af;
    if (version == 4) {
        af = htonl(AF_INET);
    } else if (version == 6) {
        af = htonl(AF_INET6);
    } else {
        af = htonl(AF_INET);  // default to IPv4
    }

    // Prepend 4-byte family header
    std::vector<uint8_t> buf(4 + len);
    memcpy(buf.data(), &af, 4);
    memcpy(buf.data() + 4, data, len);

    ssize_t n = ::write(fd_, buf.data(), buf.size());
    if (n < 0) {
        if (errno == EINTR || errno == EAGAIN) return false;
        std::cerr << "[TUN] write error: " << strerror(errno) << std::endl;
        return false;
    }
    return (size_t)n == buf.size();
}

} // namespace tun
