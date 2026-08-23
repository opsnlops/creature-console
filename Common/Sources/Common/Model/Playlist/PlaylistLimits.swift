import Foundation

/// Client-side mirror of the server's playlist validation caps (creature-server 3.45.0).
/// Keep in sync so the editor blocks an invalid save before the round-trip instead of
/// surfacing a 400.
public enum PlaylistLimits {
    /// Smallest weight the server accepts. Zero is rejected: an item that can never be picked
    /// has no business being in the playlist.
    public static let minimumItemWeight: UInt32 = 1
    /// Largest weight the server accepts.
    public static let maximumItemWeight: UInt32 = 999
    /// The accepted weight range, for validation and for `Stepper`/`TextField` bounds.
    public static let itemWeightRange: ClosedRange<UInt32> = minimumItemWeight...maximumItemWeight
    /// Maximum number of items in one playlist.
    public static let maximumItems = 256
    /// Maximum length, in bytes, of a playlist `name`.
    public static let maxNameBytes = 256

    /// Whether a weight is one the server will accept.
    public static func isValidWeight(_ weight: UInt32) -> Bool {
        itemWeightRange.contains(weight)
    }

    /// Parse user-entered text into an accepted weight, or `nil` when it isn't one.
    ///
    /// Deliberately strict about the whole string: "12x" is a typo, not the number 12.
    public static func weight(fromUserInput text: String) -> UInt32? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = UInt32(trimmed), isValidWeight(value) else { return nil }
        return value
    }
}
