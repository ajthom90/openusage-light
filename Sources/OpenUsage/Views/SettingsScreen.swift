import SwiftUI

struct SettingsScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(LayoutStore.self) private var layout
    @AppStorage(AppearanceSetting.key) private var appearance = AppearanceSetting.system
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @AppStorage(TimeFormatSetting.key) private var timeFormat = TimeFormatSetting.auto
    @State private var launchAtLogin = LaunchAtLoginSetting()
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        PopoverScrollView {
            VStack(alignment: .leading, spacing: density.sectionSpacing) {
                section("General") {
                    row("Launch at Login") {
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.update(to: $0) }
                        ))
                        .settingsSwitchStyle()
                    }
                    row("Global Shortcut") {
                        ShortcutRecorderField(name: .togglePopover, isVisible: layout.screen == .settings)
                    }
                }
                section("Appearance") {
                    row("Icon Style") {
                        @Bindable var layout = container.layout
                        picker($layout.menuBarStyle, options: MenuBarStyle.allCases, label: \.label)
                    }
                    row("Theme") {
                        picker($appearance, options: AppearanceSetting.allCases, label: \.label)
                            .onChange(of: appearance) { AppearanceSetting.applyCurrent() }
                    }
                    row("Density") {
                        picker($density, options: DensitySetting.allCases, label: \.label)
                    }
                    row("Time Format") {
                        picker($timeFormat, options: TimeFormatSetting.allCases, label: \.label)
                    }
                }
                notificationsSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scrollPosition($scrollPosition)
        .onChange(of: layout.screen) { _, screen in
            if screen == .settings {
                scrollPosition.scrollTo(edge: .top)
                launchAtLogin.refreshStatus()
            }
        }
    }

    private var notificationsSection: some View {
        @Bindable var notifications = container.notificationSettings
        return section("Notifications") {
            notificationRow("Under 10% Remaining", isOn: $notifications.underTenPercent)
            notificationRow("Healthy Pace Changes", isOn: $notifications.healthyToClose)
            notificationRow("Near-Limit Pace Changes", isOn: $notifications.closeToRunningOut)
        }
    }

    private func notificationRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row(title) {
            Toggle("", isOn: isOn)
                .settingsSwitchStyle()
                .onChange(of: isOn.wrappedValue) { _, enabled in
                    if enabled { AppNotifications.shared.requestAuthorization() }
                }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            VStack(spacing: 0, content: content)
                .cardSurface()
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density.controlRowPadding)
    }

    private func picker<Value: Hashable>(
        _ selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}
