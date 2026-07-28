import Foundation

struct CameraAim: Codable, Equatable, Sendable {
    var pan: Double
    var tilt: Double
}

enum CameraPresetSlot: Int, CaseIterable, Codable, Identifiable, Sendable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }
    var title: String { "Position \(rawValue)" }
    var icon: String { "\(rawValue).circle" }
    fileprivate var storageKey: String { String(rawValue) }
}

struct CameraPreset: Codable, Equatable, Sendable {
    var pan: Double
    var tilt: Double
    /// The camera's native zoom units, where 100 is 1x. Nil means the camera
    /// exposed no zoom control when the preset was saved.
    var zoom: Double?

    var aim: CameraAim { CameraAim(pan: pan, tilt: tilt) }
}

struct CameraPresetState: Codable, Equatable, Sendable {
    private var slots: [String: CameraPreset] = [:]
    var selectedSlot: CameraPresetSlot?

    static let empty = Self()

    func preset(in slot: CameraPresetSlot) -> CameraPreset? {
        slots[slot.storageKey]
    }

    mutating func setPreset(_ preset: CameraPreset, in slot: CameraPresetSlot) {
        slots[slot.storageKey] = preset
        selectedSlot = slot
    }

    mutating func select(_ slot: CameraPresetSlot) {
        guard preset(in: slot) != nil else { return }
        selectedSlot = slot
    }

    var presetsBySlot: [CameraPresetSlot: CameraPreset] {
        Dictionary(uniqueKeysWithValues: CameraPresetSlot.allCases.compactMap { slot in
            preset(in: slot).map { (slot, $0) }
        })
    }
}

/// Persists the framing chosen in the mirror independently for each physical
/// camera. A single Codable payload keeps arbitrary device UIDs out of the
/// UserDefaults key namespace and lets an unreadable value fail closed.
@MainActor
final class CameraAimStore {
    static let defaultsKey = "cameraAimByDevice"

    private let defaults: UserDefaults
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func aim(for deviceUID: String) -> CameraAim? {
        aims()[deviceUID]
    }

    func setAim(_ aim: CameraAim, for deviceUID: String) {
        var stored = aims()
        stored[deviceUID] = aim
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func aims() -> [String: CameraAim] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let stored = try? decoder.decode([String: CameraAim].self, from: data) else {
            return [:]
        }
        return stored
    }
}

/// Three explicit framing memories for each physical camera. This is separate
/// from `CameraAimStore`: the latter remains the automatic no-preset fallback
/// and continues to preserve behavior for existing installations.
@MainActor
final class CameraPresetStore {
    static let defaultsKey = "cameraPresetsByDevice"

    private let defaults: UserDefaults
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(for deviceUID: String) -> CameraPresetState {
        states()[deviceUID] ?? .empty
    }

    @discardableResult
    func setPreset(
        _ preset: CameraPreset,
        in slot: CameraPresetSlot,
        for deviceUID: String
    ) -> CameraPresetState {
        var stored = states()
        var state = stored[deviceUID] ?? .empty
        state.setPreset(preset, in: slot)
        stored[deviceUID] = state
        save(stored)
        return state
    }

    @discardableResult
    func select(
        _ slot: CameraPresetSlot,
        for deviceUID: String
    ) -> CameraPresetState {
        var stored = states()
        var state = stored[deviceUID] ?? .empty
        state.select(slot)
        stored[deviceUID] = state
        save(stored)
        return state
    }

    private func states() -> [String: CameraPresetState] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let stored = try? decoder.decode([String: CameraPresetState].self, from: data) else {
            return [:]
        }
        return stored
    }

    private func save(_ states: [String: CameraPresetState]) {
        guard let data = try? encoder.encode(states) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
