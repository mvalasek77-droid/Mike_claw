import Foundation

extension String {
    /// Returns nil when the string is empty, otherwise self. Useful for keeping
    /// optional model fields truly optional (e.g. a post title left blank).
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
