import Foundation
import UIKit

/// Composes a `mailto:` URL for the in-app "Report a bug" flow. Zero auth,
/// zero backend — taps the OS Mail app with a pre-filled template plus the
/// device/build info we'd otherwise have to ask for.
enum BugReport {
    static let recipient = "mv19770601@gmail.com"

    static func mailtoURL(recipient: String = recipient) -> URL? {
        let subject = "Auction Baby bug report"

        let device = UIDevice.current
        let iosVersion = device.systemVersion
        let deviceModel = deviceIdentifier()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let body = """
        (Please describe the bug here — what you did, what you saw, what you expected.)


        Steps to reproduce:
        1.
        2.
        3.


        —
        Do not delete the lines below — they help us reproduce.

        App: Auction Baby \(appVersion) (build \(buildNumber))
        iOS: \(iosVersion)
        Device: \(deviceModel)
        Locale: \(Locale.current.identifier)
        """

        // mailto: bodies need CRLF between lines and full RFC 3986 encoding of
        // both the subject and body — including reserved characters like `#`,
        // `&`, `?`. `.urlQueryAllowed` is too permissive; strip those manually.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&?#=+")

        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: allowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }

        let raw = "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"
        return URL(string: raw)
    }

    /// The raw model identifier ("iPhone16,2") so the reporter doesn't have to
    /// know what phone they own. Falls back to the marketing model on
    /// simulators, where the sysctl reads "arm64" and isn't useful.
    private static func deviceIdentifier() -> String {
        #if targetEnvironment(simulator)
        return "iOS Simulator (\(UIDevice.current.model))"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.compactMap { element -> String? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return String(UnicodeScalar(UInt8(value)))
        }.joined()
        return identifier.isEmpty ? UIDevice.current.model : identifier
        #endif
    }
}
