import Foundation
import Darwin
import Network

struct SubscriptionSource: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var createdAt: Date = Date()
    var lastRefreshedAt: Date?
    var lastSummary: String?
    var lastError: String?
}

struct SubscriptionRefreshResult: Equatable {
    let sourceId: UUID
    let sourceName: String
    let addedCount: Int
    let skippedDuplicateCount: Int
    let failedCount: Int
    let fastestProfileName: String?
    let message: String
}

enum SubscriptionError: LocalizedError, Equatable {
    case invalidURL
    case duplicateURL
    case sourceNotFound

    var errorDescription: String? {
        let L = LanguageManager.shared
        switch self {
        case .invalidURL:
            return L.t("Введите HTTP(S) ссылку подписки", "Enter an HTTP(S) subscription URL")
        case .duplicateURL:
            return L.t("Такая подписка уже добавлена", "This subscription is already added")
        case .sourceNotFound:
            return L.t("Подписка не найдена", "Subscription not found")
        }
    }
}

enum SubscriptionFetchError: LocalizedError, Equatable {
    case httpStatus(Int)
    case tooLarge
    case nonUTF8

    var errorDescription: String? {
        let L = LanguageManager.shared
        switch self {
        case .httpStatus(let status):
            return L.t("Подписка вернула HTTP \(status)", "Subscription returned HTTP \(status)")
        case .tooLarge:
            return L.t("Подписка слишком большая", "Subscription is too large")
        case .nonUTF8:
            return L.t("Подписка не похожа на текст UTF-8", "Subscription is not UTF-8 text")
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    typealias Fetch = (URL) async throws -> String
    typealias MeasureLatency = (ProxyConfig) async -> Int?

    static let defaultSubscriptionsDir = ProfileManager.defaultProfilesDir

    let subscriptionsDir: URL
    let subscriptionsFile: URL

    @Published var sources: [SubscriptionSource] = []
    @Published var lastError: String?

    convenience init() {
        self.init(subscriptionsDir: Self.defaultSubscriptionsDir)
    }

    init(subscriptionsDir: URL) {
        self.subscriptionsDir = subscriptionsDir
        self.subscriptionsFile = subscriptionsDir.appendingPathComponent("subscriptions.json")
        loadSources()
    }

    @discardableResult
    func addSource(urlString: String, name: String) throws -> SubscriptionSource {
        let normalizedURL = try normalizeURL(urlString)
        guard !sources.contains(where: { $0.url == normalizedURL.absoluteString }) else {
            throw SubscriptionError.duplicateURL
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = SubscriptionSource(
            name: cleanName.isEmpty ? defaultName(for: normalizedURL) : cleanName,
            url: normalizedURL.absoluteString
        )
        sources.append(source)
        saveSources()
        return source
    }

    func deleteSource(id: UUID) {
        sources.removeAll { $0.id == id }
        saveSources()
    }

    func deleteSource(id: UUID, profileManager: ProfileManager) {
        let sourceName = sources.first { $0.id == id }?.name
        profileManager.deleteProfiles(sourceId: id, sourceName: sourceName)
        deleteSource(id: id)
    }

    func refreshAll(
        profileManager: ProfileManager,
        fetch: @escaping Fetch = SubscriptionContentFetcher.fetch
    ) async -> [SubscriptionRefreshResult] {
        var results: [SubscriptionRefreshResult] = []
        for source in sources {
            let result = await refresh(sourceId: source.id, profileManager: profileManager, fetch: fetch)
            results.append(result)
        }
        return results
    }

    func refresh(
        sourceId: UUID,
        profileManager: ProfileManager,
        fetch: @escaping Fetch = SubscriptionContentFetcher.fetch,
        measureLatency: @escaping MeasureLatency = SubscriptionLatencyMeasurer.measure
    ) async -> SubscriptionRefreshResult {
        guard let idx = sources.firstIndex(where: { $0.id == sourceId }) else {
            return SubscriptionRefreshResult(
                sourceId: sourceId,
                sourceName: "",
                addedCount: 0,
                skippedDuplicateCount: 0,
                failedCount: 1,
                fastestProfileName: nil,
                message: SubscriptionError.sourceNotFound.localizedDescription
            )
        }

        let source = sources[idx]
        guard let url = URL(string: source.url) else {
            return finishRefresh(
                sourceIndex: idx,
                added: 0,
                skipped: 0,
                failed: 1,
                error: SubscriptionError.invalidURL.localizedDescription
            )
        }

        do {
            let text = try await fetch(url)
            let parsed = ProfileImportParser.parse(text)
            var labeledProfiles = parsed.profiles
            for index in labeledProfiles.indices {
                labeledProfiles[index].sourceId = source.id
                labeledProfiles[index].sourceName = source.name
            }

            _ = profileManager.attachMatchingProfiles(
                labeledProfiles,
                sourceId: source.id,
                sourceName: source.name
            )
            let addResult = profileManager.addProfiles(labeledProfiles)
            let fastest = await selectFastestProfile(
                sourceId: source.id,
                profileManager: profileManager,
                measureLatency: measureLatency
            )
            let message = "Added: \(addResult.addedCount), duplicates: \(addResult.skippedDuplicateCount), failed: \(parsed.failureCount)"
            return finishRefresh(
                sourceIndex: idx,
                added: addResult.addedCount,
                skipped: addResult.skippedDuplicateCount,
                failed: parsed.failureCount,
                fastestProfileName: fastest?.name,
                summary: message
            )
        } catch {
            return finishRefresh(
                sourceIndex: idx,
                added: 0,
                skipped: 0,
                failed: 1,
                error: error.localizedDescription
            )
        }
    }

    private func finishRefresh(
        sourceIndex idx: Int,
        added: Int,
        skipped: Int,
        failed: Int,
        fastestProfileName: String? = nil,
        summary: String? = nil,
        error: String? = nil
    ) -> SubscriptionRefreshResult {
        sources[idx].lastRefreshedAt = Date()
        sources[idx].lastSummary = summary
        sources[idx].lastError = error
        saveSources()

        return SubscriptionRefreshResult(
            sourceId: sources[idx].id,
            sourceName: sources[idx].name,
            addedCount: added,
            skippedDuplicateCount: skipped,
            failedCount: failed,
            fastestProfileName: fastestProfileName,
            message: error ?? summary ?? ""
        )
    }

    private func fastestProfile(
        from profiles: [ProxyConfig],
        measureLatency: MeasureLatency
    ) async -> ProxyConfig? {
        var best: (profile: ProxyConfig, latency: Int)?
        for profile in profiles {
            guard let latency = await measureLatency(profile) else { continue }
            if best == nil || latency < best!.latency {
                best = (profile, latency)
            }
        }
        return best?.profile
    }

    func selectFastestProfile(
        sourceId: UUID,
        profileManager: ProfileManager,
        measureLatency: @escaping MeasureLatency = SubscriptionLatencyMeasurer.measure
    ) async -> ProxyConfig? {
        let sourceProfiles = profileManager.profiles.filter { $0.sourceId == sourceId }
        guard let fastest = await fastestProfile(from: sourceProfiles, measureLatency: measureLatency) else {
            return nil
        }
        profileManager.selectProfile(id: fastest.id)
        return fastest
    }

    private func normalizeURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw SubscriptionError.invalidURL
        }
        return url
    }

    private func defaultName(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return "Subscription \(sources.count + 1)"
    }

    private func loadSources() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: subscriptionsFile.path) else { return }
        do {
            let data = try Data(contentsOf: subscriptionsFile)
            sources = try JSONDecoder().decode([SubscriptionSource].self, from: data)
            lastError = nil
        } catch {
            let L = LanguageManager.shared
            lastError = L.t(
                "Не удалось загрузить подписки: \(error.localizedDescription)",
                "Failed to load subscriptions: \(error.localizedDescription)"
            )
            sources = []
        }
    }

    private func saveSources() {
        do {
            try SecureJSONFile.write(sources, to: subscriptionsFile, directory: subscriptionsDir)
            lastError = nil
        } catch {
            let L = LanguageManager.shared
            lastError = L.t(
                "Не удалось сохранить подписки: \(error.localizedDescription)",
                "Failed to save subscriptions: \(error.localizedDescription)"
            )
        }
    }
}

enum SubscriptionContentFetcher {
    static func fetch(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw SubscriptionFetchError.httpStatus(http.statusCode)
        }
        guard data.count <= ProfileImportParser.maxInputBytes else {
            throw SubscriptionFetchError.tooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SubscriptionFetchError.nonUTF8
        }
        return text
    }
}

enum SubscriptionLatencyMeasurer {
    static func measure(_ profile: ProxyConfig) async -> Int? {
        await withCheckedContinuation { continuation in
            let start = Date()
            let conn = NWConnection(
                host: NWEndpoint.Host(profile.server),
                port: NWEndpoint.Port(rawValue: UInt16(profile.port))!,
                using: .tcp
            )
            let resumeBox = LatencyResumeBox(connection: conn, continuation: continuation)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeBox.finish(Int(Date().timeIntervalSince(start) * 1000))
                case .failed, .cancelled:
                    resumeBox.finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                resumeBox.finish(nil)
            }
        }
    }
}

private final class LatencyResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let connection: NWConnection
    private let continuation: CheckedContinuation<Int?, Never>

    init(connection: NWConnection, continuation: CheckedContinuation<Int?, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ value: Int?) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        connection.cancel()
        continuation.resume(returning: value)
    }
}

enum SecureJSONFile {
    static func write<T: Encodable>(_ value: T, to fileURL: URL, directory: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let data = try JSONEncoder().encode(value)
        let tmpURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(tmpURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard fd >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            defer { close(fd) }
            var offset = 0
            while offset < data.count {
                let written = data.withUnsafeBytes { rawBuffer in
                    Darwin.write(fd, rawBuffer.baseAddress!.advanced(by: offset), data.count - offset)
                }
                if written <= 0 {
                    throw CocoaError(.fileWriteUnknown)
                }
                offset += written
            }
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw error
        }

        _ = try fm.replaceItemAt(fileURL, withItemAt: tmpURL)
    }
}
