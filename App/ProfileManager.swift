import Foundation

@MainActor
final class ProfileManager: ObservableObject {

    private static let profilesDir: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".veil")
    private static let profilesFile: URL = profilesDir
        .appendingPathComponent("profiles.json")

    @Published var profiles: [ProxyConfig] = []
    @Published var activeProfileId: UUID? {
        didSet { UserDefaults.standard.set(activeProfileId?.uuidString, forKey: "activeProfileId") }
    }

    var activeProfile: ProxyConfig? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    init() {
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

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
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
        let path = Self.profilesFile.path
        guard fm.fileExists(atPath: path) else { return }
        do {
            let data = try Data(contentsOf: Self.profilesFile)
            profiles = try JSONDecoder().decode([ProxyConfig].self, from: data)
        } catch {
            profiles = []
        }
    }

    private func saveProfiles() {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: Self.profilesDir.path) {
                try fm.createDirectory(at: Self.profilesDir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: Self.profilesFile, options: .atomic)
            try fm.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Self.profilesFile.path
            )
        } catch {
            // Silent failure — file I/O errors are non-fatal
        }
    }
}
