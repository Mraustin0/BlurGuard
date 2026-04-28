import AppKit
import SwiftUI

// MARK: - Glass background (NSVisualEffectView)

struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Live header (isolated so only it re-renders on state changes)

private struct LiveHeader: View {
    @ObservedObject private var state = BlurStateManager.shared
    @AppStorage(SettingsManager.cameraEnabledKey) private var cameraEnabled: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isEnabled
                      ? (cameraEnabled ? Color.green : Color.blue)
                      : Color(white: 0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("BlurGuard")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                Text("Monitoring · \(state.peekCount) peek\(state.peekCount == 1 ? "" : "s") today")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button { BlurStateManager.shared.triggerInstantBlur() } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13)).foregroundColor(.white.opacity(0.55))
            }
            .buttonStyle(.plain).help("Instant Lock")

            Toggle("", isOn: Binding(
                get: { state.isEnabled },
                set: { state.isEnabled = $0 }
            ))
            .labelsHidden().scaleEffect(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Live today count (isolated)

private struct LiveTodayRow: View {
    @ObservedObject private var state = BlurStateManager.shared
    var body: some View {
        HStack {
            Text("\(state.peekCount) peek\(state.peekCount == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .medium)).foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 9).padding(.bottom, 4)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage(SettingsManager.cameraEnabledKey)     private var cameraEnabled: Bool   = false
    @AppStorage(SettingsManager.cameraAwayDelayKey)   private var cameraAwayDelay: Int  = 8
    @AppStorage(SettingsManager.cameraSensitivityKey) private var sensitivity: Double   = 0.6
    @AppStorage(SettingsManager.idleTimeoutKey)       private var idleTimeout: Double   = 30.0
    @AppStorage(SettingsManager.peekResponseKey)      private var peekResponse: String  = "blur"
    @AppStorage(SettingsManager.awayResponseKey)      private var awayResponse: String  = "blur"
    @State private var requireAuth       = SettingsManager.shared.requireAuth
    @State private var hotkeyDisplay     = SettingsManager.shared.hotkeyDisplay
    @State private var isRecordingHotkey = false
    @State private var keyMonitor: Any?
    @State private var ignoredApps: [IgnoredApp] = Self.loadIgnoredApps()
    @State private var showAppPicker     = false

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                LiveHeader()
                divider

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // PEEK RESPONSE
                        sectionLabel("Peek Response")
                        pillRow(binding: $peekResponse, onChange: { SettingsManager.shared.peekResponse = $0 })
                        divider

                        // WALK-AWAY RESPONSE
                        sectionLabel("Walk-Away Response")
                        pillRow(binding: $awayResponse, onChange: { SettingsManager.shared.awayResponse = $0 })
                        divider

                        // DETECTION
                        sectionLabel("Detection")
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text("Camera Sensitivity").glText(); Spacer() }
                                Text("Higher = triggers more easily from further away")
                                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                            }
                            .padding(.horizontal, 14).padding(.top, 4)
                            Slider(value: $sensitivity, in: 0...1)
                                .padding(.horizontal, 14).padding(.bottom, 6)
                                .onChange(of: sensitivity) { SettingsManager.shared.cameraSensitivity = $0 }

                            insetDivider

                            row {
                                Image(systemName: "camera.fill").glIcon()
                                Text("Camera protection").glText()
                                Spacer()
                                Toggle("", isOn: $cameraEnabled).labelsHidden()
                                    .onChange(of: cameraEnabled) { SettingsManager.shared.cameraEnabled = $0 }
                            }
                            insetDivider
                            row {
                                Image(systemName: "figure.walk").glIcon()
                                Text("Walk-away delay").glText()
                                Spacer()
                                Picker("", selection: $cameraAwayDelay) {
                                    Text("3s").tag(3); Text("5s").tag(5)
                                    Text("8s").tag(8); Text("15s").tag(15)
                                }
                                .pickerStyle(.menu).frame(width: 66)
                                .onChange(of: cameraAwayDelay) { SettingsManager.shared.cameraAwayDelay = $0 }
                            }
                            insetDivider
                            row {
                                Image(systemName: "timer").glIcon()
                                Text("Idle lock after").glText()
                                Spacer()
                                Picker("", selection: $idleTimeout) {
                                    Text("15s").tag(15.0); Text("30s").tag(30.0)
                                    Text("1m").tag(60.0);  Text("2m").tag(120.0)
                                    Text("5m").tag(300.0); Text("10m").tag(600.0)
                                }
                                .pickerStyle(.menu).frame(width: 66)
                                .onChange(of: idleTimeout) { SettingsManager.shared.idleTimeout = $0 }
                            }
                            insetDivider
                            row {
                                Image(systemName: "faceid").glIcon()
                                Text("Require auth").glText()
                                Spacer()
                                Toggle("", isOn: $requireAuth).labelsHidden()
                                    .onChange(of: requireAuth) { SettingsManager.shared.requireAuth = $0 }
                            }
                            insetDivider
                            row {
                                Image(systemName: "keyboard").glIcon()
                                Text("Instant lock hotkey").glText()
                                Spacer()
                                Button(isRecordingHotkey ? "Press…" : hotkeyDisplay) {
                                    isRecordingHotkey = true
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(5).buttonStyle(.plain)
                            }
                            .onChange(of: isRecordingHotkey) { $0 ? startRecording() : stopRecording() }
                        }
                        divider

                        // AUTO-PAUSE
                        sectionLabel("Auto-Pause Apps")
                        autoPauseSection
                        divider

                        // TODAY
                        sectionLabel("Today")
                        LiveTodayRow()
                    }
                }

                divider
                footerRow
            }
        }
        .frame(width: 300, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(existingIDs: Set(ignoredApps.map(\.bundleID))) { addApp($0) }
        }
    }

    // MARK: - Pill row

    private func pillRow(binding: Binding<String>, onChange: @escaping (String) -> Void) -> some View {
        HStack {
            PillPicker(options: ["Blur", "Lock"], selection: binding)
                .onChange(of: binding.wrappedValue) { onChange($0) }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    // MARK: - Auto-pause

    private var autoPauseSection: some View {
        VStack(spacing: 0) {
            ForEach(ignoredApps) { app in
                row {
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                        } else {
                            Image(systemName: "app.fill").glIcon()
                        }
                    }
                    Text(app.name).glText()
                    Spacer()
                    Button { removeApp(app.bundleID) } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red.opacity(0.7)).font(.system(size: 14))
                    }.buttonStyle(.plain)
                }
                insetDivider
            }
            row {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor).font(.system(size: 14))
                Text("Add Running App…").font(.system(size: 13)).foregroundColor(.accentColor)
                Spacer()
            }
            .contentShape(Rectangle()).onTapGesture { showAppPicker = true }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            Button("Pause 1 hour") { BlurStateManager.shared.pause(for: 3600) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
            Spacer()
            Button("Quit") { BlurStateManager.shared.shutdown(); NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Shared UI helpers

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private var insetDivider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 40)
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    @ViewBuilder
    private func row<C: View>(@ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14).padding(.vertical, 9)
    }

    // MARK: - Hotkey recording

    private func startRecording() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            if event.keyCode == 53 { isRecordingHotkey = false; return nil }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else { return nil }
            let kc  = Int(event.keyCode)
            let cm  = HotkeyManager.carbonModifiers(from: flags)
            let ch  = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            let disp = HotkeyManager.displayString(carbonModifiers: cm, character: ch)
            SettingsManager.shared.hotkeyKeyCode  = kc
            SettingsManager.shared.hotkeyModifiers = Int(cm)
            SettingsManager.shared.hotkeyDisplay   = disp
            HotkeyManager.shared.update()
            hotkeyDisplay = disp
            isRecordingHotkey = false
            return nil
        }
    }

    private func stopRecording() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - App management

    private static func loadIgnoredApps() -> [IgnoredApp] {
        SettingsManager.shared.ignoredBundleIDs.map { IgnoredApp(bundleID: $0) }.sorted { $0.name < $1.name }
    }
    private func addApp(_ id: String) {
        var ids = SettingsManager.shared.ignoredBundleIDs; ids.insert(id)
        SettingsManager.shared.ignoredBundleIDs = ids; ignoredApps = Self.loadIgnoredApps()
    }
    private func removeApp(_ id: String) {
        var ids = SettingsManager.shared.ignoredBundleIDs; ids.remove(id)
        SettingsManager.shared.ignoredBundleIDs = ids; ignoredApps.removeAll { $0.bundleID == id }
    }
}

// MARK: - Pill Picker

struct PillPicker: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection = opt.lowercased() }
                    .buttonStyle(PillStyle(isSelected: selection == opt.lowercased()))
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct PillStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isSelected ? Color(white: 0.1) : .white.opacity(0.65))
            .padding(.horizontal, 16).padding(.vertical, 5)
            .background(isSelected ? Color.white : Color.clear)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Modifiers

extension Text {
    func glText() -> some View { self.font(.system(size: 13)).foregroundColor(.white) }
}
extension Image {
    func glIcon() -> some View {
        self.font(.system(size: 12)).foregroundColor(.white.opacity(0.5)).frame(width: 16)
    }
}

// MARK: - IgnoredApp + AppPickerView

struct IgnoredApp: Identifiable {
    let bundleID: String
    var id: String { bundleID }
    var name: String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
    var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct AppPickerView: View {
    let existingIDs: Set<String>
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var candidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { !(existingIDs.contains($0.bundleIdentifier ?? "")) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Choose an App to Pause For").font(.headline).padding()
            Divider()
            if candidates.isEmpty {
                Text("No other apps running").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(candidates, id: \.bundleIdentifier) { app in
                    Button {
                        if let id = app.bundleIdentifier { onSelect(id) }
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            }
                            Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            Button("Cancel") { dismiss() }.padding(10)
        }
        .frame(width: 280, height: 340)
    }
}
