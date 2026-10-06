import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.soundKey) private var soundName = Notifier.chime
    @AppStorage(Settings.soundEnabledKey) private var soundEnabled = true
    @AppStorage(Settings.notifyKey) private var notificationsEnabled = true
    @AppStorage(Settings.menuBarModeKey) private var menuBarMode = MenuBarMode.tasks.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var previewBounce = 0

    var body: some View {
        VStack(spacing: 12) {
            section("When Claude finishes", symbol: "bell.fill", color: Palette.coral) {
                row("Play a sound") { toggle($soundEnabled) }
                row("Sound") {
                    HStack(spacing: 6) {
                        Picker("", selection: $soundName) {
                            ForEach(Notifier.allSounds, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: soundName) { _, name in Notifier.shared.playSound(name) }
                        Button {
                            previewBounce += 1
                            Notifier.shared.playSound(soundName)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(Palette.coral)
                                .symbolEffect(.bounce, value: previewBounce)
                        }
                        .buttonStyle(.plain)
                        .help("Preview")
                    }
                    .disabled(!soundEnabled)
                    .opacity(soundEnabled ? 1 : 0.4)
                }
                row("Show a notification") { toggle($notificationsEnabled) }
            }

            section("Menu bar", symbol: "menubar.rectangle", color: Palette.blue) {
                row("Next to the icon") {
                    Picker("", selection: $menuBarMode) {
                        ForEach(MenuBarMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            section("System", symbol: "power.circle.fill", color: Palette.mint) {
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
                if let loginError {
                    Text(loginError).font(.rounded(11)).foregroundStyle(Palette.coral).padding(.bottom, 8)
                }
            }

            Text("Token counts come from Claude Code's local history. Plan limits use the same unofficial endpoint as /usage, so they may stop working if Anthropic changes it.")
                .font(.rounded(11))
                .foregroundStyle(Palette.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, color: Color,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(color.opacity(0.15)))
                Text(title).font(.rounded(14, .bold)).foregroundStyle(Palette.text)
            }
            .padding(.bottom, 4)
            content()
        }
        .card()
    }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label).font(.rounded(13)).foregroundStyle(Palette.text)
            Spacer()
            control()
        }
        .frame(minHeight: 32)
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).toggleStyle(.switch).controlSize(.mini).tint(Palette.blue).labelsHidden()
    }
}
