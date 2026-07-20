import SwiftUI
import AppKit

struct SettingsScreen: View {
    @EnvironmentObject var vpn: VPNManager
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var loginItem: LoginItemManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @ObservedObject private var themeManager = ThemeManager.shared

    let chooseSingBoxBinary: () -> Void

    private var summary: SettingsSummary {
        SettingsSummary(
            state: vpn.state,
            customSingBoxPath: vpn.customSingBoxPath,
            language: lang.language,
            isResettingSystemProxy: vpn.isResettingSystemProxy
        )
    }

    var body: some View {
        DetailSurface {
            Text(lang.t("Настройки", "Settings"))
                .font(.system(size: 28, weight: .bold, design: .rounded))

            SettingsGroup(title: lang.t("Прокси", "Proxy"), icon: "network") {
                SettingsRow(
                    title: "SOCKS5",
                    subtitle: lang.t("Локальный порт для приложений", "Local port for apps")
                ) {
                    Text(summary.socksEndpoint)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                }

                Divider()
                    .padding(.leading, 16)

                SettingsRow(
                    title: lang.t("Системный прокси", "System proxy"),
                    subtitle: summary.proxyResetDescription
                ) {
                    HStack(spacing: 10) {
                        Text(summary.systemProxyStatus)
                            .foregroundStyle(summary.isSystemProxyActive ? connectedAccent : .secondary)

                        Button {
                            vpn.resetSystemProxySettings()
                        } label: {
                            Label(summary.proxyResetButtonTitle, systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!summary.canResetSystemProxy)
                        .help(lang.t(
                            "Отключить SOCKS proxy для всех активных сетевых служб",
                            "Disable SOCKS proxy for all active network services"
                        ))
                    }
                }
            }

            SettingsGroup(title: lang.t("Защита", "Protection"), icon: "shield") {
                SettingsRow(
                    title: lang.t("Прокси-защита", "Proxy Guard"),
                    subtitle: lang.t(
                        "Оставляет системный SOCKS-прокси включённым при обрыве VPN (приложения, использующие системный прокси, потеряют доступ в сеть до переподключения)",
                        "Keeps system SOCKS proxy active when VPN drops (apps that honour system proxy will lose network access until you reconnect)"
                    )
                ) {
                    Toggle("", isOn: $vpn.killSwitchEnabled)
                        .labelsHidden()
                }
            }

            SettingsGroup(title: lang.t("Подключение", "Connection"), icon: "bolt.horizontal") {
                SettingsRow(
                    title: lang.t("Запуск при входе", "Launch at login"),
                    subtitle: loginItem.statusDescription.resolved(lang.language)
                ) {
                    Toggle("", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .disabled(!loginItem.isToggleEnabled)
                }

                Divider()
                    .padding(.leading, 16)

                SettingsRow(
                    title: lang.t("Автоподключение", "Auto-connect"),
                    subtitle: lang.t(
                        "Подключаться при запуске, если есть активный профиль",
                        "Connect on launch if an active profile exists"
                    )
                ) {
                    Toggle("", isOn: $vpn.autoConnectEnabled)
                        .labelsHidden()
                }

                Divider()
                    .padding(.leading, 16)

                SettingsRow(
                    title: lang.t("Автопереподключение", "Auto-reconnect"),
                    subtitle: lang.t(
                        "Повторять подключение, если соединение оборвалось само (с растущей паузой, до 6 попыток)",
                        "Retry when an established connection drops on its own (backing off, up to 6 attempts)"
                    )
                ) {
                    Toggle("", isOn: $vpn.autoReconnectEnabled)
                        .labelsHidden()
                }

                Divider()
                    .padding(.leading, 16)

                SettingsRow(
                    title: lang.t("Автообновление подписок", "Auto-refresh subscriptions"),
                    subtitle: lang.t(
                        "Перечитывать сохранённые подписки раз в 6 часов. Обращается к серверу провайдера; если подписок нет, ничего не происходит",
                        "Re-fetch saved subscriptions every 6 hours. Contacts your provider's server; does nothing if you have no subscriptions"
                    )
                ) {
                    Toggle("", isOn: $subscriptionManager.autoRefreshEnabled)
                        .labelsHidden()
                }

                Divider()
                    .padding(.leading, 16)

                SettingsRow(
                    title: "sing-box",
                    subtitle: summary.singBoxDescription
                ) {
                    HStack(spacing: 8) {
                        if !vpn.customSingBoxPath.isEmpty {
                            Button {
                                vpn.clearCustomSingBoxPath()
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(lang.t("Сбросить локальный путь", "Clear local path"))
                        }

                        Button {
                            chooseSingBoxBinary()
                        } label: {
                            Label(lang.t("Выбрать", "Choose"), systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            SettingsGroup(title: lang.t("Оформление", "Appearance"), icon: "paintbrush") {
                SettingsRow(
                    title: lang.t("Тема", "Theme"),
                    subtitle: nil
                ) {
                    Picker("", selection: $themeManager.theme) {
                        Text(lang.t("Система", "System")).tag(AppTheme.system)
                        Text(lang.t("Светлая", "Light")).tag(AppTheme.light)
                        Text(lang.t("Тёмная", "Dark")).tag(AppTheme.dark)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }

            SettingsGroup(title: lang.t("Система", "System"), icon: "gearshape.2") {
                SettingsRow(
                    title: lang.t("Язык интерфейса", "Interface language"),
                    subtitle: lang.t("Переключение применяется сразу", "Switches instantly")
                ) {
                    Button(summary.languageToggleTitle) {
                        lang.toggle()
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                    .padding(.leading, 16)

                SettingsRow(
                    title: lang.t("Приложение", "Application"),
                    subtitle: lang.t("Закрыть Rayline", "Quit Rayline")
                ) {
                    Button(lang.t("Выйти", "Quit")) {
                        quitApplication()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func quitApplication() {
        Task {
            if vpn.state.isConnected || vpn.state.isConnecting || vpn.state.isDisconnecting {
                await vpn.disconnectAndWait()
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
