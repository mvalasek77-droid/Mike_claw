import SwiftUI
import UIKit

enum Keyboard {
    /// Hide the keyboard by resigning whatever is first responder. Works
    /// from anywhere — a button, a gesture — without a reference to the
    /// focused field.
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}

extension View {
    /// Puts a "Done" button in the bar above the keyboard.
    ///
    /// This is the one escape that always works, including for the
    /// multiline `TextEditor`, which has no return key to dismiss with
    /// and is where people get stuck. Apply once to a screen's scroll
    /// view or form; it shows whenever any field inside is focused.
    func keyboardDoneBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { Keyboard.dismiss() }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .accessibilityLabel("Dismiss keyboard")
            }
        }
    }
}
