import Foundation

/// Legal URLs required in the subscription purchase flow and App Store metadata.
///
/// `termsOfUse` points at Apple's Standard EULA. If you host a custom EULA,
/// replace it and add it in App Store Connect. **`privacyPolicy` is a
/// placeholder — replace it with your hosted policy URL** and set the same URL
/// in App Store Connect's Privacy Policy field.
enum Legal {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://mvalasek77-droid.github.io/screenshotstudio-privacy/")!
}
