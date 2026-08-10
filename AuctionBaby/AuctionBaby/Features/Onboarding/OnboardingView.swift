import SwiftUI
import UIKit

/// Two-phase onboarding: choose your side of the floor, then build the profile.
struct OnboardingView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var push: PushService

    @State private var role: Role?
    @State private var name = ""
    /// Date of birth — a picker replaces the free-text age field. Server-side
    /// truth (users.date_of_birth on the auth Worker) is set from this after
    /// a successful sign-in; client-side we age-gate the "Step onto the
    /// floor" button so an underage user can't even submit.
    @State private var dob: Date = Calendar.current.date(byAdding: .year, value: -27, to: Date()) ?? Date()
    @State private var location = ""
    @State private var bio = ""
    @State private var hue: Double = 0.6
    @State private var startingBidOn = false
    @State private var startingBidText = "250"
    @State private var promptAnswers: [String] = ["", ""]
    @State private var selectedInterests: Set<String> = []
    @State private var primaryPhoto: Data? = nil
    @State private var photoGallery: [Data] = []

    @State private var promptQuestions = ["The way to win me over is", "My simple pleasures"]
    private let promptPool = ["The way to win me over is", "My simple pleasures",
                              "I geek out on", "Together we could", "Dating me is like",
                              "My most controversial opinion", "Green flags I look for",
                              "Best travel story", "I'm weirdly good at", "My love language"]
    private let interestPool = ["Art", "Travel", "Food", "Fitness", "Music", "Startups",
                                "Wine", "Film", "Reading", "Dogs", "Nightlife", "Design"]

    var body: some View {
        ZStack {
            AppBackground().ignoresSafeArea()
            if role == nil {
                rolePicker.transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                profileForm.transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .motion(Motion.spring, value: role)
    }

    // MARK: Phase 1 — role

    private var rolePicker: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 30)
            BrandMark(size: 86)
            Wordmark(size: 30)
            Text("Find a high value man,\nfind out what you're worth.")
                .font(.system(size: 14, weight: .semibold, design: .serif)).italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSoft)

            Text("Choose your side of the floor")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 6)

            VStack(spacing: 14) {
                roleCard(.woman, tint: Theme.rose,
                         caption: "Get bids. Set your floor. Accept when it's right.")
                roleCard(.man, tint: Theme.gold,
                         caption: "Browse the floor. Bid what a date's worth. Build credit.")
            }
            // House rules — the up-front disclosure that makes the Copycat
            // game fair: fakes exist, you're told the instant you bid on one.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.copycat).padding(.top, 1)
                Text("House rules: AI “Copycat” profiles walk the floor unlabelled. Bid on one and you're told instantly — it costs you reputation, never money. Spot the fakes.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
            .padding(.top, 8)

            Spacer()
            Text("Demo only · play money · fictional profiles")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 12)
        }
        .screenPadding()
    }

    private func roleCard(_ r: Role, tint: Color, caption: String) -> some View {
        Button {
            Haptics.commit()
            Motion.run(Motion.spring) {
                role = r
                if r == .woman { hue = 0.92; startingBidOn = true } else { hue = 0.6 }
            }
        } label: {
            GlassSurface {
                HStack(spacing: 16) {
                    Image(systemName: r.systemImage)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(tint.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.sideTitle)
                            .font(.system(size: 20, weight: .heavy, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(caption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.inkFaint)
                }
                .padding(18)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(r == .man ? "role_bidder" : "role_lot")
    }

    // MARK: Phase 2 — profile

    private var profileForm: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Button { Motion.run(Motion.spring) { role = nil } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Text("Build your \(role == .woman ? "lot" : "bidder card")")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Image(systemName: "chevron.left").opacity(0)
                }
                .padding(.top, 8)

                AvatarView(name: name.isEmpty ? "You" : name, hue: hue, photoData: primaryPhoto)
                    .frame(height: 150)
                    .overlay(alignment: .bottomLeading) {
                        if role == .woman {
                            HStack { Chip(text: "Always visible", systemImage: "eye.fill", color: Theme.rose) }
                                .padding(10)
                        } else {
                            HStack { Chip(text: "Hidden until accepted", systemImage: "lock.fill", color: Theme.gold) }
                                .padding(10)
                        }
                    }

                SaveAccountCard(onSignedIn: onSignedInWithApple)

                GlassCard(title: "Photos", icon: "photo.on.rectangle.angled", tint: Theme.gold) {
                    PhotoUploadStep(primary: $primaryPhoto, gallery: $photoGallery)
                }

                GlassCard(title: "Basics", icon: "person.text.rectangle.fill") {
                    field("Name", text: $name, placeholder: "Your name")
                    dobField
                    field("City", text: $location, placeholder: "Where you're based")
                    VStack(alignment: .leading, spacing: 6) {
                        label("Portrait tone")
                        Slider(value: $hue, in: 0...1).tint(Color(hue: hue, saturation: 0.6, brightness: 0.8))
                    }
                }

                GlassCard(title: "About you", icon: "text.quote") {
                    field("Bio", text: $bio, placeholder: "One line that makes them lean in", axis: true)
                    ForEach(0..<promptQuestions.count, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            Menu {
                                ForEach(promptPool, id: \.self) { q in
                                    Button(q) { promptQuestions[i] = q }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    label(promptQuestions[i])
                                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.gold)
                                    Spacer()
                                }
                            }
                            TextField("", text: $promptAnswers[i], prompt: Text("Your answer").foregroundStyle(Theme.inkFaint), axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.05)))
                        }
                    }
                }

                GlassCard(title: "Interests", icon: "sparkles") {
                    FlowChips(items: interestPool, selected: $selectedInterests)
                }

                if role == .woman {
                    GlassCard(title: "Starting bid", icon: "dollarsign.circle.fill", tint: Theme.gold) {
                        Toggle(isOn: $startingBidOn.animation(Motion.snap)) {
                            Text("Set a floor")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                        }
                        .tint(Theme.gold)
                        if startingBidOn {
                            field("Minimum bid (USD)", text: $startingBidText, placeholder: "250", keyboard: .numberPad)
                            Text("Bidders see your floor. You can still accept above it, anytime.")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                        } else {
                            Text("No floor — open the bidding to anything.")
                                .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                        }
                    }
                }

                PrimaryButton(title: "Step onto the floor", systemImage: "sparkles",
                              gradient: role == .woman ? Theme.roseGradient : Theme.goldGradient,
                              enabled: canSubmit) {
                    submit()
                }
                .padding(.top, 4)
                Spacer(minLength: 30)
            }
            .screenPadding()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Whole years elapsed from `dob` until today, computed via `Calendar`
    /// (respects month/day, doesn't drift on leap years). Matches the
    /// Worker's UTC calc as closely as `Calendar` allows.
    private var ageFromDob: Int {
        Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && ageFromDob >= 18
    }

    /// DOB picker with a visible age readout. The picker is capped at "today
    /// minus 18 years" via `in:` so an underage date isn't selectable — the
    /// server still enforces the gate as truth (client checks are advisory).
    @ViewBuilder
    private var dobField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Date of birth")
            HStack {
                DatePicker("", selection: $dob,
                           in: ...Calendar.current.date(byAdding: .year, value: -18, to: Date())!,
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Theme.gold)
                Spacer()
                Text("\(ageFromDob)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.gold.opacity(0.12)))
            }
            if ageFromDob < 18 {
                Label("You must be 18 or older to use Auction Baby.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private func submit() {
        let prompts = zip(promptQuestions, promptAnswers)
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Prompt(question: $0.0, answer: $0.1) }
        let bid = (role == .woman && startingBidOn) ? Int(startingBidText) : nil
        let iso = Self.dobFormatter.string(from: dob)
        // Order matters for signed-in users: the auth Worker's slice-8 DOB
        // gate rejects `PUT /me/profile` with 403 when `date_of_birth` is
        // null. `store.register` fires `onProfileChanged` synchronously,
        // which spawns the profile upload — so DOB must be set on the
        // server FIRST. For local-only sessions we just run register.
        Task { @MainActor in
            if auth.isSignedIn {
                _ = await auth.setDateOfBirth(iso)
            }
            store.register(role: role!, name: name, age: ageFromDob, location: location,
                           bio: bio, hue: hue, startingBid: bid, prompts: prompts,
                           interests: Array(selectedInterests),
                           photoData: primaryPhoto, photoGallery: photoGallery)
            // Now the user is a real user — this is the right moment for the
            // iOS notifications modal. Firing it earlier (mid-onboarding,
            // before role choice) trips App Review's "premature prompt"
            // guidance and users decline more often. Silent no-op for
            // local-only sessions (no auth token → no server registration).
            //
            // Under UI tests, skip it: the system permission alert is a
            // springboard modal that would otherwise consume the next tap
            // (it masked the Floor-Bid check). Gated on the UI-test arg only.
            #if DEBUG
            let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTestReset")
            #else
            let uiTesting = false
            #endif
            if !uiTesting {
                await push.requestAuthorizationIfNeeded()
            }
            if auth.isSignedIn { await push.onSignedIn() }
        }
    }

    /// YYYY-MM-DD in POSIX locale — matches the Worker's strict-regex parse
    /// (any locale-specific formatter would silently produce dd/mm/yyyy on
    /// non-US devices).
    private static let dobFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Post-sign-in wiring: seed the name Apple returned (if any + field is
    /// empty). The push authorization prompt has moved to `submit()` — firing
    /// it here (mid-onboarding, before role choice) trips App Review's
    /// premature-prompt guidance. Push registration handshake still runs
    /// after submit for signed-in users.
    private func onSignedInWithApple(_ user: RemoteUser) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty,
           let n = user.name, !n.isEmpty {
            name = n
        }
    }

    // MARK: Field helpers

    private func label(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
            .foregroundStyle(Theme.inkFaint)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType = .default, axis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            TextField("", text: text,
                      prompt: Text(placeholder).foregroundStyle(Theme.inkFaint),
                      axis: axis ? .vertical : .horizontal)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(title)   // stable hook for UI tests (e.g. "Name")
                .keyboardType(keyboard)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.05)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wrapping selectable interest chips.
struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        FlexLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    Haptics.selection()
                    if on { selected.remove(item) } else { selected.insert(item) }
                } label: {
                    Chip(text: item, color: on ? Theme.gold : .white, filled: on)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
