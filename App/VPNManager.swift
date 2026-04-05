import Foundation
import AppKit
import Network
import CommonCrypto

@MainActor
final class VPNManager: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case disconnected
        case connecting
        case disconnecting
        case connected
        case error(String)

        var isConnected: Bool  { if case .connected  = self { return true }; return false }
        var isConnecting: Bool    { if case .connecting    = self { return true }; return false }
        var isDisconnecting: Bool { if case .disconnecting = self { return true }; return false }
        var isError: Bool      { if case .error      = self { return true }; return false }
    }

    // MARK: - Published

    @Published var state:          State    = .disconnected
    @Published var logs:           [String] = []
    @Published var config:         ProxyConfig?
    @Published var hasSingBox:     Bool     = false
    @Published var isDownloading:  Bool     = false
    @Published var downloadStatus: String   = ""

    @Published var pingMs:      Int? = nil
    @Published var packetsSent: Int  = 0
    @Published var packetsRecv: Int  = 0

    @Published var killSwitchEnabled: Bool = false {
        didSet { UserDefaults.standard.set(killSwitchEnabled, forKey: "killSwitchEnabled") }
    }

    @Published var autoConnectEnabled: Bool = false {
        didSet { UserDefaults.standard.set(autoConnectEnabled, forKey: "autoConnect") }
    }

    @Published var lastPingUpdate: Date?

    nonisolated static let socksPort: Int = 10808

    // Directory where we install sing-box
    static let installDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".veil")

    private let configPath = VPNManager.installDir.appendingPathComponent("singbox.json").path
    private var process: Process?
    private var logTailHandle: FileHandle?
    private var logTailSource: DispatchSourceRead?
    private var pingTimer: Timer?
    private var disconnectTask: Task<Void, Never>?

    // MARK: - Init

    private var didAutoConnect = false

    init() {
        killSwitchEnabled = UserDefaults.standard.bool(forKey: "killSwitchEnabled")
        autoConnectEnabled = UserDefaults.standard.bool(forKey: "autoConnect")
        hasSingBox = findSingBox() != nil
        if !hasSingBox {
            let L = LanguageManager.shared
            addLog(L.t("sing-box не найден — нажмите «Скачать»",
                        "sing-box not found — click «Download»"))
        }
    }

    // MARK: - Connect

    func connect(urlString: String) {
        Task {
            if !hasSingBox {
                await downloadSingBox()
                guard hasSingBox else { return }
            }
            await doConnect(urlString: urlString)
        }
    }

    func connect(config cfg: ProxyConfig) {
        Task {
            if !hasSingBox {
                await downloadSingBox()
                guard hasSingBox else { return }
            }
            await doConnectWith(config: cfg)
        }
    }

    func autoConnectOnLaunchIfNeeded(activeProfile: ProxyConfig?) {
        guard !didAutoConnect else { return }
        didAutoConnect = true
        guard autoConnectEnabled, let profile = activeProfile else { return }
        connect(config: profile)
    }

    private func doConnect(urlString: String) async {
        let L = LanguageManager.shared
        state = .connecting
        addLog(L.t("Разбор ссылки…", "Parsing link…"))

        let cfg: ProxyConfig
        do {
            cfg = try ProxyParser.parse(urlString)
            guard cfg.isValid else {
                setState(.error(L.t("Неверная ссылка (нет сервера/порта)",
                                    "Invalid link (no server or port)")))
                return
            }
        } catch {
            setState(.error(error.localizedDescription))
            return
        }
        await doConnectWith(config: cfg)
    }

    private func doConnectWith(config cfg: ProxyConfig) async {
        let L = LanguageManager.shared
        state = .connecting
        config = cfg

        let json = cfg.toSingBoxConfig()
        do {
            try FileManager.default.createDirectory(at: Self.installDir,
                                                     withIntermediateDirectories: true)
            try json.write(toFile: configPath, atomically: true, encoding: .utf8)
            chmod(configPath, 0o600)
            addLog("Config → \(configPath)")
        } catch {
            setState(.error(L.t("Не удалось записать конфиг: \(error.localizedDescription)",
                                "Failed to write config: \(error.localizedDescription)")))
            return
        }

        guard let sbPath = findSingBox() else {
            setState(.error(L.t("sing-box не найден", "sing-box not found")))
            return
        }
        addLog("sing-box: \(sbPath)")
        stopProcess()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sbPath)
        proc.arguments     = ["run", "-c", configPath]

        let logFile = Self.installDir.appendingPathComponent("singbox.log").path
        FileManager.default.createFile(atPath: logFile, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        if let fh = FileHandle(forWritingAtPath: logFile) {
            proc.standardOutput = fh
            proc.standardError  = fh
        }

        do { try proc.run() } catch {
            setState(.error(L.t("Не удалось запустить sing-box: \(error.localizedDescription)",
                                "Failed to start sing-box: \(error.localizedDescription)")))
            return
        }
        process = proc
        proc.terminationHandler = { [weak self] terminatedProc in
            Task { @MainActor [weak self] in
                guard let self,
                      self.process?.processIdentifier == terminatedProc.processIdentifier,
                      self.state.isConnected || self.state.isConnecting else { return }
                self.handleUnexpectedDisconnect()
            }
        }
        addLog("sing-box PID=\(proc.processIdentifier)")

        // Start tailing the log file so sing-box output appears in UI
        startLogTail(path: logFile)

        let ready = await waitForSocksPort(timeout: 5.0, process: proc)
        guard proc.isRunning else {
            setState(.error(L.t("sing-box завершился сразу (см. лог)",
                                "sing-box exited immediately (check log tab)")))
            stopLogTail()
            process = nil
            return
        }
        guard ready else {
            stopProcess()
            stopLogTail()
            setState(.error(L.t("sing-box не открыл порт \(Self.socksPort) за 5 сек",
                                "sing-box did not open port \(Self.socksPort) within 5 sec")))
            return
        }

        let proxyFailures = await Task.detached(priority: .utility) { setSystemProxy(true) }.value
        if !proxyFailures.isEmpty {
            let detail = proxyFailures.joined(separator: "; ")
            addLog(L.t("⚠ Не удалось настроить системный proxy: \(detail)",
                       "⚠ Failed to set system proxy: \(detail)"))
            stopProcess()
            stopLogTail()
            setState(.error(L.t("Не удалось применить системный proxy",
                                "Failed to apply system proxy")))
            return
        }
        addLog(L.t("Подключено! SOCKS5 127.0.0.1:\(Self.socksPort)",
                   "Connected! SOCKS5 127.0.0.1:\(Self.socksPort)"))
        state = .connected
        startPing(host: cfg.server, port: cfg.port)
    }

    // MARK: - Disconnect

    func disconnect() {
        guard disconnectTask == nil else { return }
        disconnectTask = Task { [weak self] in
            await self?.performDisconnect()
        }
    }

    func disconnectAndWait() async {
        disconnect()
        await disconnectTask?.value
    }

    private func performDisconnect() async {
        stopPing()
        stopLogTail()
        stopProcess()
        state = .disconnecting
        let L = LanguageManager.shared
        let failures = await Task.detached(priority: .utility) {
            setSystemProxy(false)
        }.value
        if !failures.isEmpty {
            addLog(L.t("⚠ Не удалось снять системный proxy: \(failures.joined(separator: "; "))",
                       "⚠ Failed to clear system proxy: \(failures.joined(separator: "; "))"))
        }
        try? FileManager.default.removeItem(atPath: configPath)
        config = nil
        state  = .disconnected
        addLog(L.t("Отключено", "Disconnected"))
        disconnectTask = nil
    }

    private func handleUnexpectedDisconnect() {
        let L = LanguageManager.shared
        stopPing()
        stopLogTail()
        process = nil
        disconnectTask = nil

        if killSwitchEnabled {
            // Keep system proxy active → traffic fails → no leaks
            try? FileManager.default.removeItem(atPath: self.configPath)
            addLog(L.t(
                "⚠️ Прокси-защита: соединение оборвалось — системный прокси оставлен включённым",
                "⚠️ Proxy Guard: connection lost — system proxy kept active"
            ))
            setState(.error(L.t(
                "Прокси-защита: соединение оборвалось",
                "Proxy Guard: connection lost"
            )))
        } else {
            Task.detached(priority: .utility) {
                let failures = setSystemProxy(false)
                if !failures.isEmpty {
                    await MainActor.run { [weak self] in
                        self?.addLog(L.t("⚠ Не удалось снять proxy: \(failures.joined(separator: "; "))",
                                         "⚠ Failed to clear proxy: \(failures.joined(separator: "; "))"))
                    }
                }
            }
            try? FileManager.default.removeItem(atPath: self.configPath)
            addLog(L.t("Соединение оборвалось", "Connection lost"))
            setState(.error(L.t("Соединение оборвалось", "Connection lost")))
        }
    }

    // MARK: - Download sing-box

    // Pinned version and checksums for supply-chain safety.
    // To update: change the tag, version, and SHA256 hashes from the official release.
    private static let singBoxTag     = "v1.11.4"
    private static let singBoxVersion = "1.11.4"
    private static let singBoxChecksums: [String: String] = [
        "darwin-arm64": "f4349633befd75c972a5a958cbfb6236a1e20b585425ae7c3ec73e5fa29217c5",
        "darwin-amd64": "ba5ee4d4630b6cb36c24f0f33d7f9b790b185eceebc74818ca6ff1283bd5e94b",
    ]

    private static func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = data.withUnsafeBytes { buf -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: 32)
            CC_SHA256(buf.baseAddress, CC_LONG(buf.count), &hash)
            return hash
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func downloadSingBox() async {
        let L = LanguageManager.shared
        isDownloading  = true
        downloadStatus = L.t("Скачивание sing-box…", "Downloading sing-box…")
        addLog(L.t("Скачивание sing-box с GitHub…", "Downloading sing-box from GitHub…"))

        do {
            let tag     = Self.singBoxTag
            let version = Self.singBoxVersion
            let archKey = isArm64 ? "darwin-arm64" : "darwin-amd64"
            let tarball = "sing-box-\(version)-\(archKey).tar.gz"
            let dlURL   = URL(string: "https://github.com/SagerNet/sing-box/releases/download/\(tag)/\(tarball)")!

            downloadStatus = L.t("Скачивание sing-box \(tag)…", "Downloading sing-box \(tag)…")
            addLog(L.t("Версия: \(tag), архитектура: \(archKey)",
                       "Version: \(tag), arch: \(archKey)"))

            // 1. Download tarball
            let (tmpURL, _) = try await URLSession.shared.download(from: dlURL)

            // 2. Verify SHA256 checksum
            downloadStatus = L.t("Проверка контрольной суммы…", "Verifying checksum…")
            let actualHash = try Self.sha256Hex(of: tmpURL)
            if let expectedHash = Self.singBoxChecksums[archKey] {
                guard actualHash == expectedHash else {
                    addLog(L.t("SHA256 не совпадает!\n  ожидалось: \(expectedHash)\n  получено:  \(actualHash)",
                               "SHA256 mismatch!\n  expected: \(expectedHash)\n  got:      \(actualHash)"))
                    throw SingBoxDownloadError.checksumMismatch
                }
                addLog(L.t("SHA256 ✓", "SHA256 ✓"))
            } else {
                addLog(L.t("⚠ Нет эталонного SHA256 для \(archKey) — пропуск проверки",
                           "⚠ No reference SHA256 for \(archKey) — skipping verification"))
            }

            downloadStatus = L.t("Установка…", "Installing…")

            // 3. Extract on background thread
            let installDir = Self.installDir
            try await Task.detached(priority: .utility) {
                let dir = installDir
                try FileManager.default.createDirectory(at: dir,
                                                        withIntermediateDirectories: true)
                let tar = Process()
                tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tar.arguments = ["-xzf", tmpURL.path,
                                 "-C",   dir.path,
                                 "--strip-components=1"]
                try tar.run()
                tar.waitUntilExit()

                let binary = dir.appendingPathComponent("sing-box")
                guard FileManager.default.fileExists(atPath: binary.path) else {
                    throw SingBoxDownloadError.extractFailed
                }
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: binary.path)
            }.value

            let installedPath = Self.installDir.appendingPathComponent("sing-box").path
            addLog("sing-box установлен: \(installedPath)")
            hasSingBox     = true
            isDownloading  = false
            downloadStatus = ""

        } catch {
            addLog(L.t("ОШИБКА скачивания: \(error.localizedDescription)",
                       "Download error: \(error.localizedDescription)"))
            state          = .error(L.t("Не удалось скачать sing-box: \(error.localizedDescription)",
                                        "Failed to download sing-box: \(error.localizedDescription)"))
            isDownloading  = false
            downloadStatus = ""
        }
    }

    // MARK: - Ping (TCP RTT)

    private func startPing(host: String, port: Int) {
        stopPing()
        measureRTT(host: host, port: port)
        pingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.measureRTT(host: host, port: port) }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate(); pingTimer = nil
        pingMs = nil; packetsSent = 0; packetsRecv = 0
    }

    func refreshPing() {
        guard state.isConnected, let cfg = config else { return }
        measureRTT(host: cfg.server, port: cfg.port)
    }

    private func measureRTT(host: String, port: Int) {
        packetsSent += 1
        let conn = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host),
                          port: NWEndpoint.Port(integerLiteral: UInt16(port))),
            using: .tcp)
        let t0 = Date()
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                DispatchQueue.main.async {
                    self?.pingMs = ms
                    self?.packetsRecv += 1
                    self?.lastPingUpdate = Date()
                }
                conn.cancel()
            case .failed:
                conn.cancel()
            default: break
            }
        }
        conn.start(queue: .global(qos: .background))
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { conn.cancel() }
    }

    // MARK: - Helpers

    /// Poll TCP connect to the local SOCKS port until it accepts or timeout expires.
    private func waitForSocksPort(timeout: Double, process proc: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && proc.isRunning {
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                let conn = NWConnection(
                    to: .hostPort(host: "127.0.0.1",
                                  port: NWEndpoint.Port(integerLiteral: UInt16(Self.socksPort))),
                    using: .tcp)
                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        conn.cancel()
                        cont.resume(returning: true)
                    case .failed, .cancelled:
                        cont.resume(returning: false)
                    default: break
                    }
                }
                conn.start(queue: .global(qos: .utility))
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    conn.cancel()
                }
            }
            if ok { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    private func stopProcess() {
        guard let proc = process, proc.isRunning else { process = nil; return }
        proc.terminate()
        addLog("sing-box PID=\(proc.processIdentifier) " +
               LanguageManager.shared.t("остановлен", "stopped"))
        process = nil
    }

    // MARK: - Log tailing

    private func startLogTail(path: String) {
        stopLogTail()
        guard let fh = FileHandle(forReadingAtPath: path) else { return }
        fh.seekToEndOfFile()

        let source = DispatchSource.makeReadSource(fileDescriptor: fh.fileDescriptor,
                                                   queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            let data = fh.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: "\n")
                            .map { Self.stripAnsi($0) }
                            .filter { !$0.isEmpty }
            DispatchQueue.main.async {
                guard let self else { return }
                for line in lines { self.addLog("▸ \(line)") }
            }
        }
        source.setCancelHandler { try? fh.close() }
        source.resume()

        logTailHandle = fh
        logTailSource = source
    }

    private func stopLogTail() {
        logTailSource?.cancel()
        logTailSource = nil
        logTailHandle = nil
    }

    /// Strip ANSI colour escape sequences from sing-box log output.
    static func stripAnsi(_ s: String) -> String {
        // Matches ESC[ ... m sequences
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}", let bracket = s.index(i, offsetBy: 1, limitedBy: s.endIndex),
               bracket < s.endIndex, s[bracket] == "[" {
                // skip until 'm'
                var j = s.index(bracket, offsetBy: 1, limitedBy: s.endIndex) ?? bracket
                while j < s.endIndex && s[j] != "m" { j = s.index(after: j) }
                if j < s.endIndex { j = s.index(after: j) }
                i = j
            } else {
                result.append(s[i])
                i = s.index(after: i)
            }
        }
        return result
    }

    private func setState(_ s: State) {
        state = s
        if case .error(let msg) = s {
            addLog(LanguageManager.shared.t("ОШИБКА: \(msg)", "ERROR: \(msg)"))
        }
    }

    private static let logDateFormatter: DateFormatter = {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"; return df
    }()

    func addLog(_ msg: String) {
        logs.append("\(Self.logDateFormatter.string(from: Date())) \(msg)")
        if logs.count > 300 { logs.removeFirst() }
    }

    func clearLog() { logs.removeAll() }

    func findSingBox() -> String? {
        // 1. Bundled inside .app/Contents/MacOS/ — highest priority
        let bundledInApp = Bundle.main.bundlePath + "/Contents/MacOS/sing-box"
        // 2. Previously downloaded to ~/.veil/
        let downloaded = Self.installDir.appendingPathComponent("sing-box").path
        // 3. System-wide installs
        let candidates = [bundledInApp, downloaded,
                          "/opt/homebrew/bin/sing-box",
                          "/usr/local/bin/sing-box",
                          "/usr/bin/sing-box"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        // 4. Try `which`
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = ["sing-box"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    private var isArm64: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Download error

enum SingBoxDownloadError: LocalizedError {
    case extractFailed, checksumMismatch
    var errorDescription: String? {
        let L = LanguageManager.shared
        switch self {
        case .extractFailed:    return L.t("Ошибка распаковки архива", "Failed to extract archive")
        case .checksumMismatch: return L.t("Контрольная сумма SHA256 не совпадает — файл повреждён или подменён",
                                           "SHA256 checksum mismatch — file corrupted or tampered")
        }
    }
}

// MARK: - System proxy (nonisolated, blocking — run off main thread)

private func allNetworkServices() -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    p.arguments = ["-listallnetworkservices"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError  = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let services = out.split(separator: "\n")
        .map(String.init)
        .filter { !$0.hasPrefix("*") && !$0.contains("asterisk") && !$0.isEmpty }
    return services.isEmpty ? ["Wi-Fi"] : services
}

/// Runs networksetup with the given arguments directly — no shell, no injection risk.
/// Returns (terminationStatus, stderrOutput).
private func networkSetup(_ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    p.arguments     = args
    p.standardOutput = FileHandle.nullDevice
    let errPipe = Pipe()
    p.standardError  = errPipe
    do {
        try p.run()
    } catch {
        return (-1, error.localizedDescription)
    }
    p.waitUntilExit()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (p.terminationStatus, errStr)
}

/// Returns list of network services where proxy setup failed.
private func setSystemProxy(_ enabled: Bool, port: Int = VPNManager.socksPort) -> [String] {
    var failures: [String] = []
    for svc in allNetworkServices() {
        if enabled {
            let (s1, e1) = networkSetup(["-setsocksfirewallproxy", svc, "127.0.0.1", "\(port)"])
            let (s2, e2) = networkSetup(["-setsocksfirewallproxystate", svc, "on"])
            if s1 != 0 || s2 != 0 {
                failures.append("\(svc): \(e1) \(e2)".trimmingCharacters(in: .whitespaces))
            }
        } else {
            let (s, e) = networkSetup(["-setsocksfirewallproxystate", svc, "off"])
            if s != 0 {
                failures.append("\(svc): \(e)")
            }
        }
    }
    return failures
}
