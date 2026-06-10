import SwiftUI

/// Demo-mode Stripe setup screen. Shown to App Review reviewers (or any
/// user with `demoMode == true`) instead of opening Safari to Stripe's
/// real onboarding. Accepts any input — none of it is stored, validated,
/// or sent anywhere. Tapping "Complete demo setup" marks the local
/// `payoutConnected` flag true with a believable-shaped fake
/// `connectAccountID`.
///
/// The point is that the reviewer can see and exercise the Stripe Connect
/// onboarding flow's outcome without entering real bank info or relying
/// on a live Worker / Stripe sandbox account.
struct DemoStripeView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var country = "United States"
    @State private var routing = ""
    @State private var account = ""
    @State private var dob = ""
    @State private var taxID = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                        Text("Demo mode — these fields are NOT saved or sent anywhere. Type any numbers; tap Complete to mark your payout setup connected.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Section("Bank") {
                    TextField("Country", text: $country)
                    TextField("Routing number", text: $routing).keyboardType(.numberPad)
                    TextField("Account number", text: $account).keyboardType(.numberPad)
                }
                Section("Identity") {
                    TextField("Date of birth (MM/DD/YYYY)", text: $dob).keyboardType(.numbersAndPunctuation)
                    TextField("Tax ID / SSN last 4", text: $taxID).keyboardType(.numberPad)
                }
                Section {
                    Button {
                        store.completeDemoStripeSetup()
                        Haptics.success()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Complete demo setup")
                                .fontWeight(.heavy)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Demo Stripe setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
