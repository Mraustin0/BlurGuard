import AppKit
import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    @AppStorage(SettingsManager.cameraEnabledKey)   private var cameraEnabled: Bool   = true
    @AppStorage(SettingsManager.cameraAwayDelayKey) private var cameraAwayDelay: Int  = 8
    @AppStorage(SettingsManager.idleTimeoutKey)     private var idleTimeout: Double   = 30.0
    @State private var requireAuth:      Bool   = SettingsManager.shared.requireAuth
    @State private var hotkeyDisplay:    String = SettingsManager.shared.hotkeyDisplay
    @State private var isRecordingHotkey = false
    @State private var keyMonitor: Any?
    @State private var ignoredApps: [IgnoredApp] = Self.loadIgnoredApps()
    @State private var showAppPicker = false

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            glDivider

            ScrollView {
                VStack(spacing: 0) {
                    glSectionLabel("Camera Protection")
                    cameraSection
                    glDivider

                    glSectionLabel("Idle Lock")
                    glRow {
                        glIcon("timer")
                        Text("Blur after idle").glText()
                        Spacer()
                        Picker("", selection: $idleTimeout) {
                            Text("15s").tag(15.0)
                            Text("30s").tag(30.0)
                            Text("1m").tag(60.0)
                            Text("2m").tag(120.0)
                            Text("5m").tag(300.0)
                            Text("10m").tag(600.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 70)
                        .onChange(of: idleTimeout) { SettingsManager.shared.idleTimeout = $0 }
                    }
                    glDivider

                    glSectionLabel("Security")
                    glRow {
                        glIcon("faceid")
                        Text("Require auth to unlock").glText()
                        Spacer()
                        Toggle("", isOn: $requireAuth)
                            .labelsHidden()
                            .onChange(of: requireAuth) { SettingsManager.shared.requireAuth = $0 }
                    }
                    glDivider

                    glSectionLabel("Instant Lock")
                    glRow {
                        glIcon("keyboard")
                        Text("Hotkey").glText()
                        Spacer()
                        Button(isRecordingHotkey ? "Press combo…" : hotkeyDisplay) {
                            isRecordingHotkey = true
                        }
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                    .onChange(of: isRecordingHotkey) { recording in
                        recording ? startRecording() : stopRecording()
                    }
                    glDivider

                    glSectionLabel("Auto-Pause Apps")
                    autoPauseSection
                }
            }

            glDivider
            footerRow
        }
        .frame(width: 300)
        .background(glBackground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(existingIDs: Set(ignoredApps.map(\.bundleID))) { addApp($0) }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraEnabled ? Color.green : Color.gray.opacity(0.6))
                .frame(width: 8, height: 8)
            Text("BlurGuard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text("· \(cameraEnabled ? "Camera Active" : "Idle Only")")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Camera section

    private var cameraSection: some View {
        VStack(spacing: 0) {
            glRow {
                glIcon("camera.fill")
                Text("Camera Protection").glText()
                Spacer()
                Toggle("", isOn: $cameraEnabled)
                    .labelsHidden()
                    .onChange(of: cameraEnabled) { SettingsManager.shared.cameraEnabled = $0 }
            }
            if cameraEnabled {
                glInsetDivider
                glRow {
                    glIcon("figure.walk")
                    Text("Blur when away for").glText()
                    Spacer()
                    Picker("", selection: $cameraAwayDelay) {
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("8s").tag(8)
                        Text("15s").tag(15)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70)
                    .onChange(of: cameraAwayDelay) { SettingsManager.shared.cameraAwayDelay = $0 }
                }
            }
        }
    }

    // MARK: - Auto-pause section

    private var autoPauseSection: some View {
        VStack(spacing: 0) {
            ForEach(ignoredApps) { app in
                glRow {
                    Group {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        } else {
                            glIcon("app.fill")
                        }
                    }
                    Text(app.name).glText()
                    Spacer()
                    Button { removeApp(app.bundleID) } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red.opacity(0.75))
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                }
                glInsetDivider
            }
            glRow {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 15))
                Text("Add Running App…")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { showAppPicker = true }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            Button("Pause 1 hour") { BlurStateManager.shared.pause(for: 3600) }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
            Button("Quit") {
                BlurStateManager.shared.shutdown()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Shared components

    private var glDivider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }

    private var glInsetDivider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.leading, 42)
    }

    private func glSectionLabel(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func glRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func glIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.55))
            .frame(width: 18)
    }

    private var glBackground: some View {
        Color(red: 0.10, green: 0.12, blue: 0.20)
    }

    // MARK: - Hotkey recording

    private func startRecording() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            if event.keyCode == 53 { isRecordingHotkey = false; return nil }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else { return nil }
            let kc = Int(event.keyCode)
            let cm = HotkeyManager.carbonModifiers(from: flags)
            let char = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            let display = HotkeyManager.displayString(carbonModifiers: cm, character: char)
            SettingsManager.shared.hotkeyKeyCode = kc
            SettingsManager.shared.hotkeyModifiers = Int(cm)
            SettingsManager.shared.hotkeyDisplay = display
            HotkeyManager.shared.update(keyCode: UInt32(kc), carbonModifiers: cm)
            hotkeyDisplay = display
            isRecordingHotkey = false
            return nil
        }
    }

    private func stopRecording() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    // MARK: - Ignored apps helpers

    private static func loadIgnoredApps() -> [IgnoredApp] {
        SettingsManager.shared.ignoredBundleIDs
            .map { IgnoredApp(bundleID: $0) }
            .sorted { $0.name < $1.name }
    }

    private func addApp(_ bundleID: String) {
        var ids = SettingsManager.shared.ignoredBundleIDs
        ids.insert(bundleID)
        SettingsManager.shared.ignoredBundleIDs = ids
        ignoredApps = Self.loadIgnoredApps()
    }

    private func removeApp(_ bundleID: String) {
        var ids = SettingsManager.shared.ignoredBundleIDs
        ids.remove(bundleID)
        SettingsManager.shared.ignoredBundleIDs = ids
        ignoredApps.removeAll { $0.bundleID == bundleID }
    }
}

// MARK: - Text modifier

extension Text {
    func glText() -> some View {
        self.font(.system(size: 13)).foregroundColor(.white)
    }
}

// MARK: - Supporting types (IgnoredApp, AppPickerView)

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
            Text("Choose an App to Pause For")
                .font(.headline)
                .padding()
            Divider()
            if candidates.isEmpty {
                Text("No other apps running")
                    .foregroundColor(.secondary)
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button("Cancel") { dismiss() }.padding(10)
        }
        .frame(width: 280, height: 340)
    }
}
