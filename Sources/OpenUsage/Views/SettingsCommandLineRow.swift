import SwiftUI
import OpenUsageCore

/// Settings → Command Line: installs or removes the `openusage` command on the user's `PATH`.
struct SettingsCommandLineRow: View {
    let installer: CommandLineInstaller
    @State private var status: CommandLineInstaller.Status
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(installer: CommandLineInstaller = .forRunningApp()) {
        self.installer = installer
        _status = State(initialValue: installer.status())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Terminal Command")
                Spacer(minLength: 8)
                Text(statusText)
                    .foregroundStyle(.secondary)
                Button(buttonTitle, action: perform)
                    .disabled(isWorking || status == .occupied)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, PanelMetrics.controlRowPadding)
        .onAppear { status = installer.status() }
    }

    private var statusText: String {
        switch status {
        case .installed: "Installed"
        case .notInstalled, .unavailable: "Not Installed"
        case .linkedElsewhere: "Another Copy"
        case .occupied: "In Use"
        }
    }

    private var buttonTitle: String {
        switch status {
        case .installed: "Uninstall…"
        case .linkedElsewhere: "Replace…"
        case .notInstalled, .unavailable, .occupied: "Install…"
        }
    }

    private var detail: String? {
        if let errorMessage { return errorMessage }
        switch status {
        case .installed: return "Run openusage in a new Terminal window."
        case .linkedElsewhere(let path): return "openusage currently points to \(path)."
        case .occupied: return "A file named openusage already exists in /usr/local/bin."
        case .notInstalled, .unavailable: return nil
        }
    }

    private func perform() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                if status == .installed {
                    try await installer.uninstall()
                } else {
                    try await installer.install()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            status = installer.status()
            isWorking = false
        }
    }
}
