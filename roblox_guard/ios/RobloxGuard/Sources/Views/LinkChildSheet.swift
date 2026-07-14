import SwiftUI

/// Links a child by public Roblox username only. There is deliberately no
/// password field: the app never touches the child's credentials.
struct LinkChildSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var parentName = ""
    @State private var attested = false
    @State private var isSubmitting = false

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !parentName.trimmingCharacters(in: .whitespaces).isEmpty
            && attested && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Roblox username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {    Text("Child's Roblox account")}  footer: {
                    Text("Just the public username — never a password.")
                }

                Section {
                    TextField("Your name", text: $parentName)
                } header: {    Text("Your details")}

                Section {
                    Toggle(isOn: $attested) {
                        Text("I confirm I am this child's parent or legal guardian and I consent to RobloxGuard monitoring this account's public information.")
                            .font(.subheadline)
                    }
                }

                if let message = store.errorMessage {
                    Section {
                        Text(message).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Link a child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task {
                            isSubmitting = true
                            let ok = await store.linkChild(
                                username: username.trimmingCharacters(in: .whitespaces),
                                parentName: parentName.trimmingCharacters(in: .whitespaces)
                            )
                            isSubmitting = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }
}
