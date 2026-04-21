import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsManager.idleTimeoutKey) private var idleTimeout: Double = 30.0
    @State private var requireAuth: Bool = SettingsManager.shared.requireAuth
    @State private var hotkeyDisplay: String = SettingsManager.shared.hotkeyDisplay
    @State private var isRecordingHotkey = false
    @State private var keyMonitor: Any?
    @State private var ignoredApps: [IgnoredApp] = Self.loadIgnoredApps()
    @State private var showAppPicker = false

    private let timeoutOptions: [(label: String, seconds: Double)] = [
        ("15s", 15), ("30s", 30), ("1m", 60), ("2m", 120), ("5m", 300), ("10m", 600),
    ]

    var body: some View {
        Form {
            Section("Idle Timeout") {
                Picker("", selection: $idleTimeout) {
                    ForEach(timeoutOptions, id: \.seconds) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: idleTimeout) { SettingsManager.shared.idleTimeout = $0 }
            }

            Section {
                Toggle("Require authentication to unlock", isOn: $requireAuth)
                    .onChange(of: requireAuth) { SettingsManager.shared.requireAuth = $0 }
            }

            Section("Instant Lock") {
                HStack {
                    Text("Hotkey")
                    Spacer()
                    Button(isRecordingHotkey ? "Press a combo…" : hotkeyDisplay) {
                        isRecordingHotkey = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(isRecordingHotkey ? .accentColor : .primary)
                    .frame(minWidth: 80)
                }
                Text("Press the hotkey anywhere to instantly lock the screen.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .onChange(of: isRecordingHotkey) { recording in
                recording ? startRecording() : stopRecording()
            }

            Section("Auto-Pause") {
                Text("BlurGuard pauses while any of these apps are running.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(ignoredApps) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                        Spacer()
                        Button {
                            removeApp(app.bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("+ Add Running App…") { showAppPicker = true }
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 460)
        .sheet(isPresented: $showAppPicker) {
            AppPickerView(existingIDs: Set(ignoredApps.map(\.bundleID))) { bundleID in
                addApp(bundleID)
            }
        }
    }

    // MARK: - Hotkey Recording

    private func startRecording() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [self] event in
            if event.keyCode == 53 { // Escape
                isRecordingHotkey = false
                return nil
            }
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

    // MARK: - Ignored Apps

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

// MARK: - Supporting types

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

// MARK: - App picker sheet

struct AppPickerView: View {
    let existingIDs: Set<String>
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var candidates: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { id in !(existingIDs.contains(id.bundleIdentifier ?? "")) }
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
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            }
                            Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Button("Cancel") { dismiss() }
                .padding(10)
        }
        .frame(width: 280, height: 340)
    }
}
