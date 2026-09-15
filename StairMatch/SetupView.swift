import SwiftUI

struct SetupView: View {
    var firstRun: Bool
    @Environment(\.dismiss) private var dismiss
    @Bindable private var identity = Identity.shared
    @State private var draftName = Identity.shared.name

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $draftName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                } header: { Text("What the pack calls you") }
                footer: { Text("Just a first name. No usernames, no profiles.") }

                Section {
                    Toggle("Show my city", isOn: $identity.shareCity)
                    if identity.shareCity {
                        LabeledContent("City", value: identity.city ?? "Locating…")
                    }
                } footer: {
                    Text("City only — never your gym or address. Off means you show up as \"Somewhere\".")
                }

                Section {
                    Stepper("Age: \(identity.age)", value: $identity.age, in: 13...90)
                    Stepper("Weight: \(Int(identity.weightKg)) kg", value: $identity.weightKg, in: 35...200, step: 1)
                } header: { Text("For effort and calories") }
                footer: { Text("Effort = 60% heart-rate reserve + 40% cadence. Age sets your max heart rate; weight only affects the calorie estimate. Stored on this phone only.") }

                Section {
                    LabeledContent("Relay", value: RelayConfig.baseURL.host() ?? "—")
                } footer: { Text("Override with `defaults write com.assiamah.stairmatcher relayURL <url>` for local testing.") }
            }
            .navigationTitle(firstRun ? "Welcome" : "You")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(firstRun ? "Start" : "Done") {
                        identity.name = draftName.trimmingCharacters(in: .whitespaces)
                        if identity.shareCity { identity.requestCity() }
                        dismiss()
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(firstRun)
    }
}
