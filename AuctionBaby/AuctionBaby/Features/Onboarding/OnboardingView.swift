import SwiftUI
import UIKit
import AuthenticationServices

/// Two-phase onboarding: choose your side of the floor, then build the profile.
struct OnboardingView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var auth: AuthService

    @State private var role: Role?
    @State private var name = ""
    @State private var ageText = "27"
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

                signInCard

                GlassCard(title: "Photos", icon: "photo.on.rectangle.angled", tint: Theme.gold) {
                    PhotoUploadStep(primary: $primaryPhoto, gallery: $photoGallery)
                }

                GlassCard(title: "Basics", icon: "person.text.rectangle.fill") {
                    field("Name", text: $name, placeholder: "Your name")
                    HStack(spacing: 12) {
                        field("Age", text: $ageText, placeholder: "27", keyboard: .numberPad)
                        field("City", text: $location, placeholder: "Where you're based")
                    }
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

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Int(ageText) ?? 0) >= 18
    }

    private func submit() {
        let prompts = zip(promptQuestions, promptAnswers)
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { Prompt(question: $0.0, answer: $0.1) }
        let bid = (role == .woman && startingBidOn) ? Int(startingBidText) : nil
        store.register(role: role!, name: name, age: Int(ageText) ?? 25, location: location,
                       bio: bio, hue: hue, startingBid: bid, prompts: prompts,
                       interests: Array(selectedInterests),
                       photoData: primaryPhoto, photoGallery: photoGallery)
    }

    // MARK: Sign in with Apple (Slice 1 of the spine — see SPINE_ROADMAP.md)

    /// The account-persistence card. Hidden entirely when the auth Worker
    /// isn't configured — the app then stays local-only exactly as it does
    /// today (which is also what Demo Mode always uses).
    @ViewBuilder
    private var signInCard: some View {
        if auth.isEnabled {
            GlassCard(title: "Save your account",
                      icon: "person.crop.circle.badge.checkmark",
                      tint: Theme.gold) {
                if auth.isSignedIn {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.verify)
                            .font(.system(size: 18, weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in with Apple")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            if let email = auth.user?.email, !email.isEmpty {
                                Text(email)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkFaint)
                                    .lineLimit(1)
                            } else {
                                Text("Your account will survive a reinstall.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                        }
                        Spacer()
                    }
                } else {
                    Text("Optional. Sign in so your profile and matches survive a phone reset or reinstall. You still fill everything below.")
                        .font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleSIWA(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerS))
                    .disabled(auth.inFlight)
                    .opacity(auth.inFlight ? 0.6 : 1)
                    if let error = auth.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
        }
    }

    private func handleSIWA(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                let outcome = await auth.signInWithApple(credential)
                if case .success(_, let user) = outcome {
                    // Apple returns the full name only on the FIRST sign-in.
                    // If they gave us one and the field is empty, seed it —
                    // never overwrite what the user has already typed.
                    if name.trimmingCharacters(in: .whitespaces).isEmpty,
                       let n = user.name, !n.isEmpty {
                        name = n
                    }
                }
            }
        case .failure(let error):
            // User-canceled = silent; anything else is an error worth surfacing.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled { return }
            auth.lastError = "Sign in with Apple failed. Try again, or continue without it."
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
