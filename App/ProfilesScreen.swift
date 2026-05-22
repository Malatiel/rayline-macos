import SwiftUI
import AppKit

struct ProfilesScreen: View {
    @EnvironmentObject var vpn: VPNManager
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var toastManager: ToastManager

    @Binding var urlText: String
    @Binding var parseInfo: String
    @Binding var parseOK: Bool
    @Binding var isImportExpanded: Bool
    @Binding var renamingProfileId: UUID?
    @Binding var renameText: String
    @Binding var profileNameText: String
    @Binding var subscriptionURLText: String
    let isImportingSubscription: Bool

    let displayConfig: ProxyConfig?
    let checkURL: () -> Void
    let saveProfile: () -> Void
    let pasteFromClipboard: () -> Void
    let importQRCodeFromClipboard: () -> Void
    let importSubscription: () -> Void
    let openStatus: () -> Void

    private var trimmed: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftConfig: ProxyConfig? {
        ProfileImportParser.parse(urlText).profiles.first
    }

    private var draftImport: ProfileImportResult {
        ProfileImportParser.parse(urlText)
    }

    private var isBulkImport: Bool {
        draftImport.profiles.count > 1
    }

    private var summary: ProfilesSummary {
        ProfilesSummary(
            profiles: profileManager.profiles,
            activeProfileId: profileManager.activeProfileId,
            isImportExpanded: isImportExpanded,
            importText: urlText,
            vpnState: vpn.state,
            language: lang.language
        )
    }

    var body: some View {
        DetailSurface {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.t("Профили", "Profiles"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(lang.t(
                        "Управляйте профилями: добавляйте, переименовывайте, удаляйте и переключайтесь между ними.",
                        "Manage profiles: add, rename, delete, and switch between them."
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isImportExpanded.toggle()
                    }
                } label: {
                    Label(summary.importButtonTitle, systemImage: summary.importButtonIcon)
                }
                .buttonStyle(.borderedProminent)
            }

            if summary.isEmpty {
                PlaceholderPanel(
                    title: summary.emptyTitle,
                    subtitle: summary.emptySubtitle,
                    icon: "link.badge.plus"
                )
            } else {
                ForEach(profileManager.profiles) { profile in
                    let row = summary.rows.first { $0.id == profile.id }
                    profileRowCard(profile, row: row)
                }
            }

            if summary.shouldShowImportPanel {
                importPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func profileRowCard(_ cfg: ProxyConfig, row: ProfilesSummary.Row?) -> some View {
        let row = row ?? ProfilesSummary.Row(
            id: cfg.id,
            displayName: cfg.name.isEmpty ? cfg.server : cfg.name,
            protocolName: cfg.protoName,
            route: "\(cfg.server):\(cfg.port)",
            isActive: profileManager.activeProfileId == cfg.id,
            activeBadge: lang.t("активный", "active"),
            isDeleteDisabled: false,
            deleteHelp: ""
        )

        return VStack(spacing: 0) {
            Button {
                profileManager.selectProfile(id: cfg.id)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: row.isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(row.isActive ? connectedAccent : .secondary.opacity(0.5))

                    VStack(alignment: .leading, spacing: 6) {
                        if renamingProfileId == cfg.id {
                            TextField(lang.t("Имя профиля", "Profile name"), text: $renameText, onCommit: {
                                profileManager.renameProfile(id: cfg.id, name: renameText)
                                renamingProfileId = nil
                            })
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: 220)
                            .onExitCommand {
                                renamingProfileId = nil
                            }
                        } else {
                            Text(row.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        HStack(spacing: 8) {
                            Text(row.protocolName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(protocolColor(cfg.proto))

                            Text("·")
                                .foregroundStyle(.secondary)

                            Text(row.route)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)

                            if row.isActive {
                                Text(row.activeBadge)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(connectedAccent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(connectedAccent)
                            }
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cfg.toURL(), forType: .string)
                    toastManager.show(lang.t("Ссылка скопирована", "Link copied"), style: .success)
                } label: {
                    Label(lang.t("Копировать", "Copy"), systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Text("·").foregroundStyle(.quaternary)

                Button {
                    renameText = cfg.name
                    renamingProfileId = cfg.id
                } label: {
                    Label(lang.t("Переименовать", "Rename"), systemImage: "pencil")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Text("·").foregroundStyle(.quaternary)

                Button {
                    profileManager.deleteProfile(id: cfg.id)
                } label: {
                    Label(lang.t("Удалить", "Delete"), systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.6))
                .disabled(row.isDeleteDisabled)
                .help(row.deleteHelp)
            }
            .padding(.top, 10)
        }
        .padding(18)
        .background(
            row.isActive
                ? connectedAccent.opacity(0.06)
                : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    row.isActive ? connectedAccent.opacity(0.3) : Color.primary.opacity(0.08),
                    lineWidth: row.isActive ? 1.5 : 1
                )
        )
    }

    private var importPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderText(title: lang.t("Импорт профилей", "Import profiles"), icon: "link")

            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    lang.t("HTTPS ссылка подписки", "HTTPS subscription URL"),
                    text: $subscriptionURLText
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))

                HStack(spacing: 10) {
                    Button {
                        importSubscription()
                    } label: {
                        HStack(spacing: 6) {
                            if isImportingSubscription {
                                ProgressView()
                                    .controlSize(.small)
                                Text(lang.t("Импорт...", "Importing..."))
                            } else {
                                Label(lang.t("Импорт подписки", "Import subscription"), systemImage: "arrow.down.doc")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(subscriptionURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImportingSubscription)

                    Button {
                        importQRCodeFromClipboard()
                    } label: {
                        Label(lang.t("QR из буфера", "QR from clipboard"), systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
            }

            ZStack(alignment: .topLeading) {
                if urlText.isEmpty {
                    Text(lang.t(
                        "vless://  vmess://  ss://  trojan://  текст подписки",
                        "vless://  vmess://  ss://  trojan://  subscription body"
                    ))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $urlText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 98)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        trimmed.isEmpty ? Color.secondary.opacity(0.22) : Color.accentColor.opacity(0.45),
                        lineWidth: trimmed.isEmpty ? 1 : 1.4
                    )
            )

            if !parseInfo.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: parseOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(
                        parseInfo
                            .replacingOccurrences(of: "✅ ", with: "")
                            .replacingOccurrences(of: "❌ ", with: "")
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(parseOK ? connectedAccent : .red)
            }

            if parseOK {
                if isBulkImport {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                        Text(lang.t(
                            "Будет сохранено профилей: \(draftImport.validCount)",
                            "Profiles ready to save: \(draftImport.validCount)"
                        ))
                        .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Text(lang.t("Название:", "Name:"))
                            .font(.system(size: 13, weight: .medium))
                        TextField(
                            draftConfig?.name ?? lang.t("Название профиля", "Profile name"),
                            text: $profileNameText
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    checkURL()
                } label: {
                    Label(lang.t("Проверить", "Check"), systemImage: "checkmark.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(trimmed.isEmpty)

                Button {
                    saveProfile()
                } label: {
                    Label(
                        isBulkImport ? lang.t("Сохранить все", "Save all") : lang.t("Сохранить", "Save"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftImport.profiles.isEmpty || !parseOK)
                .help(!parseOK && !trimmed.isEmpty
                      ? lang.t("Сначала нажмите «Проверить»", "Press «Check» first")
                      : "")

                Button {
                    pasteFromClipboard()
                } label: {
                    Label(lang.t("Вставить", "Paste"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    openStatus()
                } label: {
                    Text(lang.t("Открыть статус", "Open status"))
                }
                .buttonStyle(.bordered)
                .disabled(displayConfig == nil)
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: urlText) { _ in
            parseInfo = ""
            parseOK = false
            profileNameText = ""
        }
    }

    private func protocolColor(_ proto: ProxyProtocol) -> Color {
        switch proto {
        case .vless:
            return .blue
        case .vmess:
            return .indigo
        case .shadowsocks:
            return .teal
        case .trojan:
            return .orange
        }
    }
}
