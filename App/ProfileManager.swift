import Foundation
import Darwin

@MainActor
final class ProfileManager: ObservableObject {

    static let defaultProfilesDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".veil")

    let profilesDir: URL
    let profilesFile: URL

    @Published var profiles: [ProxyConfig] = []
    @Published var lastError: String?
    @Published var activeProfileId: UUID? {
        didSet { UserDefaults.standard.set(activeProfileId?.uuidString, forKey: "activeProfileId") }
    }

    var activeProfile: ProxyConfig? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    convenience init() {
        self.init(profilesDir: Self.defaultProfilesDir)
    }

    init(profilesDir: URL) {
        self.profilesDir = profilesDir
        self.profilesFile = profilesDir.appendingPathComponent("profiles.json")
        activeProfileId = UserDefaults.standard.string(forKey: "activeProfileId")
            .flatMap(UUID.init)
        loadProfiles()
    }

    // MARK: - CRUD

    func addProfile(_ config: ProxyConfig) {
        var cfg = config
        if profiles.contains(where: { $0.id == cfg.id }) {
            cfg.id = UUID()
        }
        profiles.append(cfg)
        if activeProfileId == nil { activeProfileId = cfg.id }
        saveProfiles()
    }

    @discardableResult
    func addProfiles(_ configs: [ProxyConfig]) -> ProfileBatchAddResult {
        var addedCount = 0
        var skippedDuplicateCount = 0
        var knownProfiles = profiles

        for config in configs {
            if knownProfiles.contains(where: { $0.hasSameConnection(as: config) }) {
                skippedDuplicateCount += 1
                continue
            }

            var cfg = config
            if knownProfiles.contains(where: { $0.id == cfg.id }) {
                cfg.id = UUID()
            }

            profiles.append(cfg)
            knownProfiles.append(cfg)
            addedCount += 1
            if activeProfileId == nil { activeProfileId = cfg.id }
        }

        if addedCount > 0 {
            saveProfiles()
        }

        return ProfileBatchAddResult(
            addedCount: addedCount,
            skippedDuplicateCount: skippedDuplicateCount
        )
    }

    @discardableResult
    func attachMatchingProfiles(
        _ configs: [ProxyConfig],
        sourceId: UUID,
        sourceName: String
    ) -> Int {
        var updatedCount = 0
        for config in configs {
            guard let idx = profiles.firstIndex(where: { $0.hasSameConnection(as: config) }) else {
                continue
            }
            if profiles[idx].sourceId != sourceId || profiles[idx].sourceName != sourceName {
                profiles[idx].sourceId = sourceId
                profiles[idx].sourceName = sourceName
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            saveProfiles()
        }
        return updatedCount
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        saveProfiles()
    }

    func deleteProfiles(sourceId: UUID, sourceName: String? = nil) {
        let removedActiveProfile = activeProfileId.map { activeId in
            profiles.contains { profile in
                profile.id == activeId && (
                    profile.sourceId == sourceId
                        || (sourceName != nil && profile.sourceName == sourceName)
                )
            }
        } ?? false
        profiles.removeAll { profile in
            profile.sourceId == sourceId
                || (sourceName != nil && profile.sourceName == sourceName)
        }
        if removedActiveProfile {
            activeProfileId = profiles.first?.id
        }
        saveProfiles()
    }

    func renameProfile(id: UUID, name: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].name = name
        saveProfiles()
    }

    func selectProfile(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileId = id
    }

    // MARK: - Persistence

    private func loadProfiles() {
        let fm = FileManager.default
        let path = profilesFile.path
        guard fm.fileExists(atPath: path) else { return }
        do {
            let data = try Data(contentsOf: profilesFile)
            profiles = try JSONDecoder().decode([ProxyConfig].self, from: data)
            lastError = nil
        } catch {
            let L = LanguageManager.shared
            lastError = L.t(
                "Не удалось загрузить профили: \(error.localizedDescription)",
                "Failed to load profiles: \(error.localizedDescription)"
            )
            profiles = []
        }
    }

    private func saveProfiles() {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: profilesDir.path) {
                try fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(profiles)
            let tmpURL = profilesDir.appendingPathComponent(".profiles.\(UUID().uuidString).tmp")
            let fd = open(tmpURL.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
            guard fd >= 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            do {
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
            } catch {
                try? fm.removeItem(at: tmpURL)
                throw error
            }
            _ = try fm.replaceItemAt(profilesFile, withItemAt: tmpURL)
            lastError = nil
        } catch {
            let L = LanguageManager.shared
            lastError = L.t(
                "Не удалось сохранить профили: \(error.localizedDescription)",
                "Failed to save profiles: \(error.localizedDescription)"
            )
        }
    }
}
