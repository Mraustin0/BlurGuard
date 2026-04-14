import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsManager.idleTimeoutKey) private var idleTimeout: Double = 30.0
    @State private var requireAuth: Bool = SettingsManager.shared.requireAuth

    private let options: [(label: String, seconds: Double)] = [
        ("15 sec", 15),
        ("30 sec", 30),
        ("1 min",  60),
        ("2 min",  120),
        ("5 min",  300),
        ("10 min", 600),
    ]

    var body: some View {
        Form {
            Section("Idle timeout") {
                Picker("", selection: $idleTimeout) {
                    ForEach(options, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: idleTimeout) { newValue in
                    SettingsManager.shared.idleTimeout = newValue
                }
            }

            Section {
                Toggle("Require authentication to unlock", isOn: $requireAuth)
                    .onChange(of: requireAuth) { newValue in
                        SettingsManager.shared.requireAuth = newValue
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 140)
    }
}
