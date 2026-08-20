import SwiftUI

/// One-time age confirmation. BoxCall is 13+ (feed / user-generated
/// content); adults can pass immediately. Stored via @AppStorage so
/// it never re-fires.
struct AgeGateView: View {
    @Binding var passed: Bool
    @State private var birthYear: String = ""
    @State private var err: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Quick check")
                .font(.title.bold())
            Text("BoxCall has a public feed, so you need to be at least 13 years old. What year were you born?")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            TextField("Birth year (e.g. 1998)", text: $birthYear)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 60)
                .frame(maxWidth: 320)
            if let err {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            Button {
                confirm()
            } label: {
                Text("Confirm").frame(maxWidth: 240).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            Spacer()
            Text("You can't change your birth year later without contacting support.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
    }

    private func confirm() {
        guard let year = Int(birthYear.trimmingCharacters(in: .whitespaces)) else {
            err = "Enter a valid year."; return
        }
        let thisYear = Calendar.current.component(.year, from: Date())
        let age = thisYear - year
        guard year > 1900, age >= 0, age < 130 else {
            err = "Enter a valid year."; return
        }
        guard age >= 13 else {
            err = "You must be at least 13 to use BoxCall."; return
        }
        passed = true
    }
}
