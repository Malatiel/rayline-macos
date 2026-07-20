import Foundation
import Darwin

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
    let updatedCount: Int
    let removedCount: Int
    let failedCount: Int
    let fastestProfileName: String?
    let message: String

    init(
        sourceId: UUID,
        sourceName: String,
        addedCount: Int,
        skippedDuplicateCount: Int,
        updatedCount: Int = 0,
        removedCount: Int = 0,
        failedCount: Int,
        fastestProfileName: String?,
        message: String
    ) {
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.addedCount = addedCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.updatedCount = updatedCount
        self.removedCount = removedCount
        self.failedCount = failedCount
        self.fastestProfileName = fastestProfileName
        self.message = message
    }
}

enum SubscriptionError: LocalizableError, Equatable {
    case invalidURL
    case proxyLinkNotSubscription
    case duplicateURL
    case sourceNotFound

    var localizedMessage: LocalizedMessage {
        switch self {
        case .invalidURL:
            return LocalizedMessage(ru: "Введите HTTP(S) ссылку подписки", en: "Enter an HTTP(S) subscription URL")
        case .proxyLinkNotSubscription:
            return LocalizedMessage(
                ru: "Это ссылка на профиль, а не подписка — вставьте её в поле импорта ниже",
                en: "This is a profile link, not a subscription — paste it into the import field below"
            )
        case .duplicateURL:
            return LocalizedMessage(ru: "Такая подписка уже добавлена", en: "This subscription is already added")
        case .sourceNotFound:
            return LocalizedMessage(ru: "Подписка не найдена", en: "Subscription not found")
        }
    }
}

enum SubscriptionFetchError: LocalizableError, Equatable {
    case httpStatus(Int)
    case tooLarge
    case nonUTF8
    case noValidProfiles

    var localizedMessage: LocalizedMessage {
        switch self {
        case .httpStatus(let status):
            return LocalizedMessage(ru: "Подписка вернула HTTP \(status)", en: "Subscription returned HTTP \(status)")
        case .tooLarge:
            return LocalizedMessage(ru: "Подписка слишком большая", en: "Subscription is too large")
        case .nonUTF8:
            return LocalizedMessage(ru: "Подписка не похожа на текст UTF-8", en: "Subscription is not UTF-8 text")
        case .noValidProfiles:
            return LocalizedMessage(
                ru: "В подписке не найдено валидных профилей",
                en: "No valid profiles found in subscription"
            )
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    typealias Fetch = (URL) async throws -> String
    typealias MeasureLatency = @Sendable (ProxyConfig) async -> Int?

    static let defaultSubscriptionsDir = ProfileManager.defaultProfilesDir
    nonisolated static let defaultMaxConcurrentLatencyChecks = 8

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
        measureLatency: @escaping MeasureLatency = { profile in
            await SubscriptionLatencyMeasurer.measure(profile)
        }
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
            guard !labeledProfiles.isEmpty else {
                return finishRefresh(
                    sourceIndex: idx,
                    added: 0,
                    skipped: 0,
                    failed: max(1, parsed.failureCount),
                    error: SubscriptionFetchError.noValidProfiles.localizedDescription
                )
            }

            let syncResult = profileManager.syncSubscriptionProfiles(
                labeledProfiles,
                sourceId: source.id,
                sourceName: source.name
            )
            // Refresh records latency and reports the fastest profile, but must
            // not change the user's active selection — that is reserved for the
            // explicit "select fastest" action (selectFastestProfile).
            let fastest = await measureFastestProfile(
                sourceId: source.id,
                profileManager: profileManager,
                measureLatency: measureLatency
            )
            let message = "Added: \(syncResult.addedCount), duplicates: \(syncResult.skippedDuplicateCount), updated: \(syncResult.updatedCount), removed: \(syncResult.removedCount), failed: \(parsed.failureCount)"
            return finishRefresh(
                sourceIndex: idx,
                added: syncResult.addedCount,
                skipped: syncResult.skippedDuplicateCount,
                updated: syncResult.updatedCount,
                removed: syncResult.removedCount,
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
        updated: Int = 0,
        removed: Int = 0,
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
            updatedCount: updated,
            removedCount: removed,
            failedCount: failed,
            fastestProfileName: fastestProfileName,
            message: error ?? summary ?? ""
        )
    }

    private func measureProfiles(
        from profiles: [ProxyConfig],
        maxConcurrentLatencyChecks: Int = SubscriptionManager.defaultMaxConcurrentLatencyChecks,
        measureLatency: @escaping MeasureLatency
    ) async -> [ProfileLatencyMeasurement] {
        let limit = max(1, maxConcurrentLatencyChecks)
        var nextIndex = 0
        var inFlight = 0
        let measuredAt = Date()
        var measurements: [ProfileLatencyMeasurement] = []

        return await withTaskGroup(of: ProfileLatencyMeasurement.self) { group in
            func scheduleNext() {
                guard nextIndex < profiles.count else { return }
                let profile = profiles[nextIndex]
                nextIndex += 1
                inFlight += 1
                group.addTask {
                    let latency = await measureLatency(profile)
                    return ProfileLatencyMeasurement(
                        profileId: profile.id,
                        latencyMs: latency,
                        measuredAt: measuredAt
                    )
                }
            }

            for _ in 0..<min(limit, profiles.count) {
                scheduleNext()
            }

            while inFlight > 0, let measurement = await group.next() {
                inFlight -= 1
                measurements.append(measurement)
                scheduleNext()
            }

            return measurements
        }
    }

    /// Measures latency for every profile of a source, records the results, and
    /// returns the lowest-latency profile **without** changing the active
    /// selection. Used by refresh, which should report (but not impose) the
    /// fastest profile.
    func measureFastestProfile(
        sourceId: UUID,
        profileManager: ProfileManager,
        maxConcurrentLatencyChecks: Int = SubscriptionManager.defaultMaxConcurrentLatencyChecks,
        measureLatency: @escaping MeasureLatency = { profile in
            await SubscriptionLatencyMeasurer.measure(profile)
        }
    ) async -> ProxyConfig? {
        let sourceProfiles = profileManager.profiles.filter { $0.sourceId == sourceId }
        let measurements = await measureProfiles(
            from: sourceProfiles,
            maxConcurrentLatencyChecks: maxConcurrentLatencyChecks,
            measureLatency: measureLatency
        )
        profileManager.updateLatencyMeasurements(measurements)

        let successfulMeasurements = measurements.compactMap { measurement in
            measurement.latencyMs.map { (profileId: measurement.profileId, latencyMs: $0) }
        }
        guard let best = successfulMeasurements.min(by: { $0.latencyMs < $1.latencyMs }) else {
            return nil
        }
        return profileManager.profiles.first(where: { $0.id == best.profileId })
    }

    /// Measures latency and switches the active profile to the fastest one.
    /// Triggered only by the explicit "select fastest" user action.
    @discardableResult
    func selectFastestProfile(
        sourceId: UUID,
        profileManager: ProfileManager,
        maxConcurrentLatencyChecks: Int = SubscriptionManager.defaultMaxConcurrentLatencyChecks,
        measureLatency: @escaping MeasureLatency = { profile in
            await SubscriptionLatencyMeasurer.measure(profile)
        }
    ) async -> ProxyConfig? {
        guard let fastest = await measureFastestProfile(
            sourceId: sourceId,
            profileManager: profileManager,
            maxConcurrentLatencyChecks: maxConcurrentLatencyChecks,
            measureLatency: measureLatency
        ) else {
            return nil
        }
        profileManager.selectProfile(id: fastest.id)
        return fastest
    }

    /// Schemes that identify a single proxy profile rather than a subscription.
    /// Pasting one of these into the subscription field is an easy mistake: the
    /// two inputs sit next to each other, so the error needs to say where the
    /// link actually belongs instead of just rejecting it.
    private static let proxyLinkSchemes: Set<String> = ["vless", "vmess", "ss", "trojan"]

    /// Reads the scheme by hand rather than via `URL(string:)`, because proxy
    /// links can carry characters that make `URL` parsing return nil — in which
    /// case we would lose the very information needed to explain the mistake.
    private func schemePrefix(of raw: String) -> String? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = raw[raw.startIndex..<colon].lowercased()
        return scheme.isEmpty ? nil : scheme
    }

    private func normalizeURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let scheme = schemePrefix(of: trimmed),
           Self.proxyLinkSchemes.contains(scheme) {
            throw SubscriptionError.proxyLinkNotSubscription
        }

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
        await TCPProbe.measure(host: profile.server, port: profile.port, timeout: 2.0)
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
