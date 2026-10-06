import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.soundKey) private var soundName = Notifier.chime
    @AppStorage(Settings.soundEnabledKey) private var soundEnabled = true
    @AppStorage(Settings.notifyKey) private var notificationsEnabled = true
    @AppStorage(Settings.menuBarModeKey) private var menuBarMode = MenuBarMode.tasks.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            group("When Claude finishes") {
                row("Play a sound") { toggle($soundEnabled) }
                row("Sound") {
                    HStack(spacing: 8) {
                        Picker("", selection: $soundName) {
                            ForEach(Notifier.allSounds, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: soundName) { _, name in Notifier.shared.playSound(name) }
                        IconButton(systemName: "play.fill", help: "Preview") { Notifier.shared.playSound(soundName) }
                    }
                    .disabled(!soundEnabled)
                    .opacity(soundEnabled ? 1 : 0.4)
                }
                row("Show a notification") { toggle($notificationsEnabled) }
            }

            group("Menu bar") {
                row("Beside the ring") {
                    Picker("", selection: $menuBarMode) {
                        ForEach(MenuBarMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            group("System") {
                row("Open at login") {
                    toggle($launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                                loginError = nil
                            } catch {
                                loginError = "Move the app to /Applications first, then try again."
                            }
                        }
                }
            }
            if let loginError {
                Text(loginError).font(.small).foregroundStyle(Palette.accent)
            }

            Text("Token counts come from Claude Code's local history. Plan limits use the same unofficial endpoint as /usage and may break if Anthropic changes it.")
                .font(.small)
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface))
        }
    }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).font(.body13).foregroundStyle(Palette.text)
            Spacer()
            control()
        }
        .frame(minHeight: 38)
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).controlSize(.mini).tint(Palette.accent).labelsHidden()
    }
}
