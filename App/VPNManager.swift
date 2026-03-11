import Foundation
import AppKit
import Network

@MainActor
final class VPNManager: ObservableObject {

    // MARK: - State

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var label: String {
            switch self {
            case .disconnected:  return "Отключено"
            case .connecting:    return "Подключение…"
            case .connected:     return "Подключено"
            case .error(let e):  return e
            }
        }

        var isConnected: Bool  { if case .connected  = self { return true }; return false }
        var isConnecting: Bool { if case .connecting = self { return true }; return false }
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

    static let socksPort: Int = 10808

    // Directory where we install sing-box
    static let installDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".veil")

    private let configPath = "/tmp/veil_singbox.json"
    private var process: Process?
    private var logTailHandle: FileHandle?
    private var logTailSource: DispatchSourceRead?
    private var pingTimer: Timer?

    // MARK: - Init

    init() {
        hasSingBox = findSingBox() != nil
        if !hasSingBox {
            addLog("sing-box не найден — нажмите «Скачать»")
        }
    }

    // MARK: - Connect

    func connect(urlString: String) {
        Task {
            // Auto-download if needed
            if !hasSingBox {
                await downloadSingBox()
                guard hasSingBox else { return }
            }
            await doConnect(urlString: urlString)
        }
    }

    private func doConnect(urlString: String) async {
        state = .connecting
        addLog("Разбор ссылки…")

        let cfg: ProxyConfig
        do {
            cfg = try ProxyParser.parse(urlString)
            guard cfg.isValid else {
                setState(.error("Неверная ссылка (нет сервера/порта)"))
                return
            }
        } catch {
            setState(.error(error.localizedDescription))
            return
        }
        config = cfg

        let json = cfg.toSingBoxConfig()
        do {
            try json.write(toFile: configPath, atomically: true, encoding: .utf8)
            chmod(configPath, 0o600)
            addLog("Конфиг → \(configPath)")
        } catch {
            setState(.error("Не удалось записать конфиг: \(error.localizedDescription)"))
            return
        }

        guard let sbPath = findSingBox() else {
            setState(.error("sing-box не найден"))
            return
        }
        addLog("sing-box: \(sbPath)")
        stopProcess()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: sbPath)
        proc.arguments     = ["run", "-c", configPath]

        let logFile = "/tmp/veil_singbox.log"
        FileManager.default.createFile(atPath: logFile, contents: nil)
        if let fh = FileHandle(forWritingAtPath: logFile) {
            proc.standardOutput = fh
            proc.standardError  = fh
        }

        do { try proc.run() } catch {
            setState(.error("Не удалось запустить sing-box: \(error.localizedDescription)"))
            return
        }
        process = proc
        addLog("sing-box PID=\(proc.processIdentifier)")

        // Start tailing the log file so sing-box output appears in UI
        startLogTail(path: logFile)

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard proc.isRunning else {
            setState(.error("sing-box завершился сразу (см. /tmp/veil_singbox.log)"))
            stopLogTail()
            process = nil
            return
        }

        await Task.detached(priority: .utility) { setSystemProxy(true) }.value
        addLog("Подключено! SOCKS5 127.0.0.1:\(Self.socksPort)")
        state = .connected
        startPing(host: cfg.server, port: cfg.port)
    }

    // MARK: - Disconnect

    func disconnect() {
        stopPing()
        stopLogTail()
        stopProcess()
        Task.detached(priority: .utility) { setSystemProxy(false) }
        try? FileManager.default.removeItem(atPath: configPath)
        config = nil
        state  = .disconnected
        addLog("Отключено")
    }

    // MARK: - Download sing-box

    func downloadSingBox() async {
        isDownloading  = true
        downloadStatus = "Получение информации о версии…"
        addLog("Скачивание sing-box с GitHub…")

        do {
            // 1. GitHub releases API
            let apiURL = URL(string: "https://api.github.com/repos/SagerNet/sing-box/releases/latest")!
            var req = URLRequest(url: apiURL)
            req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            let (apiData, _) = try await URLSession.shared.data(for: req)

            // 2. Parse JSON, find asset for current arch
            guard let json = try JSONSerialization.jsonObject(with: apiData) as? [String: Any],
                  let assets  = json["assets"]   as? [[String: Any]],
                  let tagName = json["tag_name"]  as? String else {
                throw SingBoxDownloadError.parseError
            }

            let archSuffix = isArm64 ? "darwin-arm64.tar.gz" : "darwin-amd64.tar.gz"
            guard let asset = assets.first(where: {
                      ($0["name"] as? String)?.hasSuffix(archSuffix) == true
                  }),
                  let urlStr = asset["browser_download_url"] as? String,
                  let dlURL  = URL(string: urlStr) else {
                throw SingBoxDownloadError.assetNotFound
            }

            downloadStatus = "Скачивание sing-box \(tagName)…"
            addLog("Версия: \(tagName), архитектура: \(archSuffix)")

            // 3. Download tarball
            let (tmpURL, _) = try await URLSession.shared.download(from: dlURL)

            downloadStatus = "Установка…"

            // 4. Extract on background thread
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
            addLog("ОШИБКА скачивания: \(error.localizedDescription)")
            state          = .error("Не удалось скачать sing-box: \(error.localizedDescription)")
            isDownloading  = false
            downloadStatus = ""
        }
    }

    // MARK: - Ping (TCP RTT)

    private func startPing(host: String, port: Int) {
        stopPing()
        measureRTT(host: host, port: port)          // first probe immediately
        pingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.measureRTT(host: host, port: port) }
        }
    }

    private func stopPing() {
        pingTimer?.invalidate(); pingTimer = nil
        pingMs = nil; packetsSent = 0; packetsRecv = 0
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
                DispatchQueue.main.async { self?.pingMs = ms; self?.packetsRecv += 1 }
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

    private func stopProcess() {
        guard let proc = process, proc.isRunning else { process = nil; return }
        proc.terminate()
        addLog("sing-box PID=\(proc.processIdentifier) остановлен")
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
    private static func stripAnsi(_ s: String) -> String {
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
        if case .error(let msg) = s { addLog("ОШИБКА: \(msg)") }
    }

    func addLog(_ msg: String) {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        logs.append("\(df.string(from: Date())) \(msg)")
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
    case parseError, assetNotFound, extractFailed
    var errorDescription: String? {
        switch self {
        case .parseError:    return "Ошибка разбора ответа GitHub API"
        case .assetNotFound: return "Бинарник для этой архитектуры не найден в релизе"
        case .extractFailed: return "Ошибка распаковки архива"
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
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let services = out.split(separator: "\n")
        .map(String.init)
        .filter { !$0.hasPrefix("*") && !$0.contains("asterisk") && !$0.isEmpty }
    return services.isEmpty ? ["Wi-Fi"] : services
}

private let kSocksPort = 10808

private func setSystemProxy(_ enabled: Bool) {
    for svc in allNetworkServices() {
        if enabled {
            shell("/usr/sbin/networksetup -setsocksfirewallproxy \"\(svc)\" 127.0.0.1 \(kSocksPort)")
            shell("/usr/sbin/networksetup -setsocksfirewallproxystate \"\(svc)\" on")
        } else {
            shell("/usr/sbin/networksetup -setsocksfirewallproxystate \"\(svc)\" off")
        }
    }
}

@discardableResult
private func shell(_ cmd: String) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "\(cmd) 2>/dev/null"]
    try? p.run(); p.waitUntilExit()
    return p.terminationStatus
}
