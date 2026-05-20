import SwiftUI
import AppKit

struct LogScreen: View {
    @EnvironmentObject var vpn: VPNManager
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var toastManager: ToastManager

    @Binding var logSearchText: String
    @Binding var logFilter: LogFilter

    private var filteredLogs: [(offset: Int, element: String)] {
        Array(vpn.logs.enumerated()).filter { _, line in
            let lower = line.lowercased()
            let matchesFilter: Bool
            switch logFilter {
            case .all:
                matchesFilter = true
            case .error:
                matchesFilter = lower.contains("error")
                    || lower.contains("fail")
                    || lower.contains("fatal")
                    || lower.contains("ошибка")
            case .warning:
                matchesFilter = lower.contains("warn") || lower.contains("⚠")
            case .info:
                matchesFilter = !lower.contains("error")
                    && !lower.contains("fail")
                    && !lower.contains("warn")
                    && !lower.contains("⚠")
            }
            let matchesSearch = logSearchText.isEmpty || lower.contains(logSearchText.lowercased())
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.t("Лог", "Log"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(lang.t(
                            "Диагностика и события подключения.",
                            "Diagnostics and connection events."
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(lang.t("Копировать", "Copy")) {
                        let text = filteredLogs.map(\.element).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        toastManager.show(lang.t("Лог скопирован", "Log copied"), style: .info)
                    }
                    .buttonStyle(.bordered)
                    .disabled(filteredLogs.isEmpty)

                    Button(lang.t("Очистить", "Clear")) {
                        vpn.clearLog()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vpn.logs.isEmpty)
                }

                HStack(spacing: 10) {
                    TextField(lang.t("Поиск…", "Search…"), text: $logSearchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("", selection: $logFilter) {
                        Text(lang.t("Все", "All")).tag(LogFilter.all)
                        Text(lang.t("Ошибки", "Errors")).tag(LogFilter.error)
                        Text(lang.t("Пред.", "Warn")).tag(LogFilter.warning)
                        Text("Info").tag(LogFilter.info)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }
            .padding(22)

            Divider()

            Group {
                if filteredLogs.isEmpty {
                    PlaceholderPanel(
                        title: lang.t("Лог пуст", "Log is empty"),
                        subtitle: lang.t(
                            "Как только появятся события подключения или ошибки, они будут видны здесь.",
                            "Connection events and errors will appear here as soon as they happen."
                        ),
                        icon: "terminal"
                    )
                    .padding(22)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(filteredLogs, id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(logLineColor(line))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .id(index)
                                }
                            }
                            .padding(.vertical, 18)
                        }
                        .background(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                        .onChange(of: vpn.logs.count) { _ in
                            if logFilter == .all && logSearchText.isEmpty,
                               let lastIndex = vpn.logs.indices.last {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    proxy.scrollTo(lastIndex, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func logLineColor(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("ошибка") || lower.contains("error") || lower.contains("fail") {
            return .red.opacity(0.85)
        }
        if lower.contains("подключено") || lower.contains("connected") || lower.contains("sha256 ✓") {
            return connectedAccent
        }
        if lower.contains("⚠") || lower.contains("warn") {
            return .orange.opacity(0.85)
        }
        return .secondary
    }
}
