import Foundation
import AppKit
import Network
import CommonCrypto
import Darwin

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
    @Published private(set) var customSingBoxPath: String = ""

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
    nonisolated static let customSingBoxPathKey = "customSingBoxPath"

    // Directory where we install sing-box
    nonisolated static let installDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".veil")

    private let configPath = VPNManager.installDir.appendingPathComponent("singbox.json").path
    private var process: Process?
    private var logTailHandle: FileHandle?
    private var logTailSource: DispatchSourceRead?
    private var pingTimer: Timer?
    private var connectTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var connectionGeneration: Int = 0
    private var proxySnapshots: [ProxySnapshot]?
    private let proxySnapshotStore: ProxySnapshotStore

    private func writeSecureTextFile(_ text: String, to path: String) throws {
        let data = Data(text.utf8)
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode_t(0o600))
        guard fd >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { close(fd) }

        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { rawBuffer in
                write(fd, rawBuffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written <= 0 {
                throw CocoaError(.fileWriteUnknown)
            }
            offset += written
        }
    }

    // MARK: - Init

    private var didAutoConnect = false

    init(
        performStartupRecovery: Bool = true,
        proxySnapshotStore: ProxySnapshotStore = .default
    ) {
        self.proxySnapshotStore = proxySnapshotStore
        killSwitchEnabled = UserDefaults.standard.bool(forKey: "killSwitchEnabled")
        autoConnectEnabled = UserDefaults.standard.bool(forKey: "autoConnect")
        customSingBoxPath = UserDefaults.standard.string(forKey: Self.customSingBoxPathKey) ?? ""
        hasSingBox = findSingBox() != nil
        if !hasSingBox {
            let L = LanguageManager.shared
            addLog(L.t("sing-box не найден — нажмите «Скачать»",
                        "sing-box not found — click «Download»"))
        }
        if performStartupRecovery {
            Task { [weak self] in
                await self?.recoverPreviousSessionIfNeeded()
            }
        }
    }

    // MARK: - Connect

    func connect(urlString: String) {
        startConnectTask { manager, generation in
            if !manager.hasSingBox {
                await manager.downloadSingBox()
                guard manager.isCurrentConnect(generation), manager.hasSingBox else { return }
            }
            await manager.doConnect(urlString: urlString, generation: generation)
        }
    }

    func connect(config cfg: ProxyConfig) {
        startConnectTask { manager, generation in
            if !manager.hasSingBox {
                await manager.downloadSingBox()
                guard manager.isCurrentConnect(generation), manager.hasSingBox else { return }
            }
            await manager.doConnectWith(config: cfg, generation: generation)
        }
    }

    func autoConnectOnLaunchIfNeeded(activeProfile: ProxyConfig?) {
        guard !didAutoConnect else { return }
        didAutoConnect = true
        guard autoConnectEnabled, let profile = activeProfile else { return }
        connect(config: profile)
    }

    private func startConnectTask(
        _ operation: @escaping @MainActor (VPNManager, Int) async -> Void
    ) {
        connectTask?.cancel()
        connectionGeneration += 1
        let generation = connectionGeneration
        connectTask = Task { [weak self] in
            guard let self else { return }
            await operation(self, generation)
            if self.connectionGeneration == generation {
                self.connectTask = nil
            }
        }
    }

    private func isCurrentConnect(_ generation: Int) -> Bool {
        generation == connectionGeneration && !Task.isCancelled
    }

    private func doConnect(urlString: String, generation: Int) async {
        let L = LanguageManager.shared
        guard isCurrentConnect(generation) else { return }
        state = .connecting
        addLog(L.t("Разбор ссылки…", "Parsing link…"))

        let cfg: ProxyConfig
        do {
            cfg = try ProxyParser.parse(urlString)
            guard cfg.isValid else {
                if isCurrentConnect(generation) {
                    setState(.error(L.t("Неверная ссылка (нет сервера/порта)",
                                        "Invalid link (no server or port)")))
                }
                return
            }
        } catch {
            if isCurrentConnect(generation) {
                setState(.error(error.localizedDescription))
            }
            return
        }
        await doConnectWith(config: cfg, generation: generation)
    }

    private func doConnectWith(config cfg: ProxyConfig, generation: Int) async {
        let L = LanguageManager.shared
        guard isCurrentConnect(generation) else { return }
        state = .connecting
        config = cfg

        let json = cfg.toSingBoxConfig()
        do {
            try FileManager.default.createDirectory(at: Self.installDir,
                                                     withIntermediateDirectories: true)
            try writeSecureTextFile(json, to: configPath)
            addLog("Config → \(configPath)")
        } catch {
            if isCurrentConnect(generation) {
                setState(.error(L.t("Не удалось записать конфиг: \(error.localizedDescription)",
                                    "Failed to write config: \(error.localizedDescription)")))
            }
            return
        }

        guard let sbPath = findSingBox() else {
            if isCurrentConnect(generation) {
                setState(.error(L.t("sing-box не найден", "sing-box not found")))
            }
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
            if isCurrentConnect(generation) {
                setState(.error(L.t("Не удалось запустить sing-box: \(error.localizedDescription)",
                                    "Failed to start sing-box: \(error.localizedDescription)")))
            }
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
        guard isCurrentConnect(generation) else {
            cleanupCancelledConnect(process: proc)
            return
        }
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

        let proxyResult = await Task.detached(priority: .utility) {
            enableSystemProxy(port: Self.socksPort)
        }.value
        proxySnapshots = proxyResult.snapshots
        do {
            try proxySnapshotStore.save(proxyResult.snapshots)
        } catch {
            addLog(L.t("⚠ Не удалось сохранить состояние системного proxy: \(error.localizedDescription)",
                       "⚠ Failed to save system proxy state: \(error.localizedDescription)"))
        }
        guard isCurrentConnect(generation) else {
            let restoreFailures = await Task.detached(priority: .utility) {
                restoreSystemProxy(proxyResult.snapshots)
            }.value
            if restoreFailures.isEmpty {
                proxySnapshotStore.clear()
            }
            cleanupCancelledConnect(process: proc)
            return
        }
        let proxyFailures = proxyResult.failures
        if !proxyFailures.isEmpty {
            let detail = proxyFailures.joined(separator: "; ")
            addLog(L.t("⚠ Не удалось настроить системный proxy: \(detail)",
                       "⚠ Failed to set system proxy: \(detail)"))
            let restoreFailures = await Task.detached(priority: .utility) {
                restoreSystemProxy(proxyResult.snapshots)
            }.value
            if restoreFailures.isEmpty {
                proxySnapshotStore.clear()
            }
            proxySnapshots = nil
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
        connectTask?.cancel()
        connectTask = nil
        connectionGeneration += 1
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
        let snapshots = proxySnapshots
        let failures = await Task.detached(priority: .utility) {
            restoreSystemProxy(snapshots)
        }.value
        if !failures.isEmpty {
            addLog(L.t("⚠ Не удалось снять системный proxy: \(failures.joined(separator: "; "))",
                       "⚠ Failed to clear system proxy: \(failures.joined(separator: "; "))"))
        } else {
            proxySnapshotStore.clear()
        }
        proxySnapshots = nil
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
            // Keep the snapshot too: a later manual disconnect can restore
            // the user's previous SOCKS settings after the guard state.
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
            let snapshots = proxySnapshots
            let snapshotStore = proxySnapshotStore
            proxySnapshots = nil
            Task.detached(priority: .utility) {
                let failures = restoreSystemProxy(snapshots)
                if !failures.isEmpty {
                    await MainActor.run { [weak self] in
                        self?.addLog(L.t("⚠ Не удалось снять proxy: \(failures.joined(separator: "; "))",
                                         "⚠ Failed to clear proxy: \(failures.joined(separator: "; "))"))
                    }
                } else {
                    snapshotStore.clear()
                }
            }
            try? FileManager.default.removeItem(atPath: self.configPath)
            addLog(L.t("Соединение оборвалось", "Connection lost"))
            setState(.error(L.t("Соединение оборвалось", "Connection lost")))
        }
    }

    private func recoverPreviousSessionIfNeeded() async {
        let L = LanguageManager.shared
        let startupConfigPath = configPath
        let stoppedProcesses = await Task.detached(priority: .utility) {
            StaleSingBoxCleaner(configPath: startupConfigPath).terminateStaleProcesses()
        }.value

        if !stoppedProcesses.isEmpty {
            addLog(L.t("Остановлен зависший sing-box после предыдущего запуска",
                       "Stopped stale sing-box from previous run"))
        }

        let snapshots: [ProxySnapshot]
        do {
            snapshots = try proxySnapshotStore.load()
        } catch {
            addLog(L.t("⚠ Не удалось прочитать сохранённое состояние proxy: \(error.localizedDescription)",
                       "⚠ Failed to read saved proxy state: \(error.localizedDescription)"))
            proxySnapshotStore.clear()
            return
        }

        guard !snapshots.isEmpty else { return }

        addLog(L.t("Восстановление системного proxy после предыдущего запуска…",
                   "Restoring system proxy after previous run…"))
        let failures = await Task.detached(priority: .utility) {
            restoreSystemProxy(snapshots)
        }.value
        if failures.isEmpty {
            addLog(L.t("Системный proxy восстановлен", "System proxy restored"))
            proxySnapshotStore.clear()
            try? FileManager.default.removeItem(atPath: configPath)
        } else {
            addLog(L.t("⚠ Не удалось восстановить proxy: \(failures.joined(separator: "; "))",
                       "⚠ Failed to restore proxy: \(failures.joined(separator: "; "))"))
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
            if !Task.isCancelled {
                addLog(L.t("ОШИБКА скачивания: \(error.localizedDescription)",
                           "Download error: \(error.localizedDescription)"))
                state = .error(L.t("Не удалось скачать sing-box: \(error.localizedDescription)",
                                   "Failed to download sing-box: \(error.localizedDescription)"))
            }
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
                final class ResumeOnce: @unchecked Sendable {
                    private let lock = NSLock()
                    private var resumed = false
                    private let cont: CheckedContinuation<Bool, Never>
                    init(_ cont: CheckedContinuation<Bool, Never>) { self.cont = cont }
                    func callAsFunction(_ value: Bool) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard !resumed else { return }
                        resumed = true
                        cont.resume(returning: value)
                    }
                }
                let resumeOnce = ResumeOnce(cont)

                conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        conn.cancel()
                        resumeOnce(true)
                    case .failed, .cancelled:
                        resumeOnce(false)
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

    private func cleanupCancelledConnect(process proc: Process) {
        stopLogTail()
        if proc.isRunning {
            proc.terminate()
        }
        if process?.processIdentifier == proc.processIdentifier {
            process = nil
        }
        if state.isConnecting {
            state = .disconnected
        }
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

    @discardableResult
    func setCustomSingBoxPath(_ path: String) -> Bool {
        let L = LanguageManager.shared
        guard FileManager.default.isExecutableFile(atPath: path) else {
            addLog(L.t("Выбранный sing-box не найден или не исполняемый: \(path)",
                       "Selected sing-box was not found or is not executable: \(path)"))
            state = .error(L.t("Выбранный sing-box не исполняемый",
                               "Selected sing-box is not executable"))
            hasSingBox = findSingBox() != nil
            return false
        }

        customSingBoxPath = path
        UserDefaults.standard.set(path, forKey: Self.customSingBoxPathKey)
        hasSingBox = true
        addLog(L.t("Локальный sing-box выбран: \(path)",
                   "Local sing-box selected: \(path)"))
        return true
    }

    func clearCustomSingBoxPath() {
        customSingBoxPath = ""
        UserDefaults.standard.removeObject(forKey: Self.customSingBoxPathKey)
        hasSingBox = findSingBox() != nil
        let L = LanguageManager.shared
        addLog(L.t("Локальный путь sing-box очищен",
                   "Local sing-box path cleared"))
    }

    func findSingBox() -> String? {
        // 1. Bundled inside .app/Contents/MacOS/ — highest priority
        let bundledInApp = Bundle.main.bundlePath + "/Contents/MacOS/sing-box"
        // 2. User-selected local binary
        let selected = customSingBoxPath
        // 3. Previously downloaded to ~/.veil/
        let downloaded = Self.installDir.appendingPathComponent("sing-box").path
        // 4. System-wide installs
        let candidates = [bundledInApp, selected, downloaded,
                          "/opt/homebrew/bin/sing-box",
                          "/usr/local/bin/sing-box",
                          "/usr/bin/sing-box"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        return nil
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

struct ProxySnapshot: Sendable, Codable, Equatable {
    let service: String
    let enabled: Bool
    let server: String
    let port: String
}

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

private func networkSetupOutput(_ args: [String]) -> (Int32, String, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    p.arguments     = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError  = errPipe
    do {
        try p.run()
    } catch {
        return (-1, "", error.localizedDescription)
    }
    p.waitUntilExit()
    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (p.terminationStatus, out, err)
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

private func valueAfterColon(in line: String) -> String {
    guard let colon = line.firstIndex(of: ":") else { return "" }
    return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func readProxySnapshot(service: String) -> ProxySnapshot {
    let (status, output, _) = networkSetupOutput(["-getsocksfirewallproxy", service])
    guard status == 0 else {
        return ProxySnapshot(service: service, enabled: false, server: "", port: "")
    }

    var enabled = false
    var server = ""
    var port = ""
    for line in output.split(separator: "\n").map(String.init) {
        if line.hasPrefix("Enabled:") {
            enabled = valueAfterColon(in: line).lowercased().hasPrefix("yes")
        } else if line.hasPrefix("Server:") {
            server = valueAfterColon(in: line)
        } else if line.hasPrefix("Port:") {
            port = valueAfterColon(in: line)
        }
    }
    return ProxySnapshot(service: service, enabled: enabled, server: server, port: port)
}

private func enableSystemProxy(port: Int = VPNManager.socksPort) -> (failures: [String], snapshots: [ProxySnapshot]) {
    var failures: [String] = []
    let services = allNetworkServices()
    let snapshots = services.map(readProxySnapshot)

    for svc in services {
        let (s1, e1) = networkSetup(["-setsocksfirewallproxy", svc, "127.0.0.1", "\(port)"])
        let (s2, e2) = networkSetup(["-setsocksfirewallproxystate", svc, "on"])
        if s1 != 0 || s2 != 0 {
            failures.append("\(svc): \(e1) \(e2)".trimmingCharacters(in: .whitespaces))
        }
    }
    return (failures, snapshots)
}

private func restoreSystemProxy(_ snapshots: [ProxySnapshot]?) -> [String] {
    var failures: [String] = []
    guard let snapshots else {
        return failures
    }

    for snapshot in snapshots {
        if snapshot.enabled {
            guard !snapshot.server.isEmpty, !snapshot.port.isEmpty else {
                failures.append("\(snapshot.service): saved proxy endpoint is empty")
                continue
            }
            let (s1, e1) = networkSetup([
                "-setsocksfirewallproxy",
                snapshot.service,
                snapshot.server,
                snapshot.port
            ])
            let (s2, e2) = networkSetup(["-setsocksfirewallproxystate", snapshot.service, "on"])
            if s1 != 0 || s2 != 0 {
                failures.append("\(snapshot.service): \(e1) \(e2)".trimmingCharacters(in: .whitespaces))
            }
        } else {
            let (s, e) = networkSetup(["-setsocksfirewallproxystate", snapshot.service, "off"])
            if s != 0 {
                failures.append("\(snapshot.service): \(e)")
            }
        }
    }
    return failures
}
