import Foundation

/// Produces friendly, deterministic aliases for a single privacy-mode session.
/// The seed changes each time the mode is enabled, while the UUID keeps every
/// row's alias stable for as long as that session remains active.
enum ScreenSharePrivacyAlias {
    enum Kind: UInt64 {
        case item = 0x4954_454D
        case folder = 0x464F_4C44
    }

    private static let adjectives = [
        "Amber", "Brisk", "Calm", "Clear", "Clever", "Cool", "Cozy", "Crisp",
        "Daring", "Gentle", "Golden", "Grand", "Happy", "Hidden", "Kind", "Light",
        "Lively", "Lucky", "Mellow", "Misty", "Modern", "Nimble", "Noble", "Quiet",
        "Rapid", "Silver", "Soft", "Sunny", "Swift", "Vivid", "Warm", "Wild",
    ]

    private static let natureWords = [
        "Aspen", "Birch", "Brook", "Canyon", "Cedar", "Cloud", "Coral", "Dawn",
        "Delta", "Fern", "Flint", "Forest", "Grove", "Harbor", "Hazel", "Iris",
        "Juniper", "Lake", "Laurel", "Maple", "Meadow", "Moon", "Ocean", "Orchid",
        "Pebble", "Pine", "River", "Sage", "Sky", "Spruce", "Willow", "Zephyr",
    ]

    private static let endingWords = [
        "Beacon", "Bridge", "Corner", "Field", "Garden", "Haven", "Hill", "House",
        "Island", "Lane", "Landing", "Light", "Nest", "Path", "Peak", "Place",
        "Point", "Port", "Ridge", "Road", "Shore", "Spring", "Station", "Stone",
        "Studio", "Summit", "Terrace", "Trail", "Vale", "View", "Way", "Yard",
    ]

    static func title(for id: UUID, seed: UInt64, kind: Kind) -> String {
        var state = seed ^ kind.rawValue
        for byte in id.uuidString.utf8 {
            state ^= UInt64(byte)
            state &*= 1_099_511_628_211
        }

        let adjectiveIndex = Int(next(&state) % UInt64(adjectives.count))
        let natureIndex = Int(next(&state) % UInt64(natureWords.count))
        let endingIndex = Int(next(&state) % UInt64(endingWords.count))
        return "\(adjectives[adjectiveIndex]) \(natureWords[natureIndex]) \(endingWords[endingIndex])"
    }

    /// SplitMix64 gives each word a well-distributed draw even when nearby
    /// seeds or UUID bytes produce similar accumulator values.
    private static func next(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
