import SwiftUI

/// Credentials gate in front of the admin console. The founder-name check
/// (`store.isAdmin`) only decides who *sees* the Settings row; this gate is
/// what actually grants god mode — roster edits and Stripe-touching Worker
/// calls — so it validates against the baked HMAC commitment in `Admin`.
struct AdminGateView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var unlocked = false
    @State private var username = ""
    @State private var password = ""
    @State private var failed = false
    @State private var attempts = 0

    var body: some View {
        if unlocked {
            AdminView()
        } else {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .font(.dynamicScaled(44, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 28)
                        Text("Founder sign-in")
                            .font(.dynamicScaled(22, weight: .heavy, design: .serif, relativeTo: .title2))
                            .foregroundStyle(Theme.ink)
                        Text("The admin console can move real money.\nCredentials required every time.\n\nUser & report actions ALSO require you to be signed in with an admin account (set `is_admin = 1` on your user row).")
                            .font(.dynamicScaled(13, relativeTo: .footnote)).foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)

                        VStack(spacing: 10) {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .onSubmit(attempt)
                        }
                        .font(.dynamicScaled(15, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(Theme.ink)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerL).fill(.white.opacity(0.06)))

                        if failed {
                            Text("Those credentials don't match.")
                                .font(.dynamicScaled(12, weight: .semibold, relativeTo: .caption1))
                                .foregroundStyle(Theme.danger)
                        }

                        Button(action: attempt) {
                            Text("Unlock")
                                .font(.dynamicScaled(15, weight: .heavy, design: .rounded, relativeTo: .subheadline))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Theme.gold))
                        }
                        .buttonStyle(.plain)
                        .disabled(username.isEmpty || password.isEmpty)

                        Spacer(minLength: 24)
                    }
                    .screenPadding()
                }
                .background(AppBackground())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.gold)
                    }
                }
            }
        }
    }

    private func attempt() {
        guard !username.isEmpty, !password.isEmpty else { return }
        if Admin.validate(username: username, password: password) {
            Haptics.success()
            unlocked = true
        } else {
            attempts += 1
            failed = true
            password = ""
            Haptics.error()
            // A dismiss-after-3 keeps a borrowed phone from brute-forcing.
            if attempts >= 3 { dismiss() }
        }
    }
}
