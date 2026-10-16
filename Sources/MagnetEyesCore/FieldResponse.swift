import Foundation

public struct FieldVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = FieldVector(x: 0, y: 0, z: 0)
    public var magnitude: Double { hypot(hypot(x, y), z) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public static func +(l: Self, r: Self) -> Self { .init(x: l.x+r.x, y: l.y+r.y, z: l.z+r.z) }
    public static func -(l: Self, r: Self) -> Self { .init(x: l.x-r.x, y: l.y-r.y, z: l.z-r.z) }
    public static func *(l: Self, r: Double) -> Self { .init(x: l.x*r, y: l.y*r, z: l.z*r) }
}

public enum AxisPair: String, CaseIterable, Identifiable, Sendable {
    case xy = "X / Y", xz = "X / Z", yz = "Y / Z"
    public var id: String { rawValue }
}

/// A bounded field-change animation, not a position or distance estimate.
public struct FieldResponse: Sendable {
    public private(set) var filtered: FieldVector?
    public private(set) var baseline: FieldVector?
    public private(set) var delta: FieldVector = .zero
    public private(set) var gazeX = 0.0
    public private(set) var gazeY = 0.0
    public var sensitivity = 1.0
    public var invertX = false
    public var invertY = false
    public var axisPair: AxisPair = .xy
    public let deadzone = 1.5 // µT, applied in the selected 2D plane before gain.
    private var previousTime: Double?

    public init() {}

    public mutating func reset() {
        filtered = nil; baseline = nil; delta = .zero
        gazeX = 0; gazeY = 0; previousTime = nil
    }

    public mutating func setBaseline(_ value: FieldVector) {
        guard value.isFinite else { return }
        baseline = value; filtered = value; delta = .zero
        gazeX = 0; gazeY = 0
    }

    /// Reject malformed or out-of-order samples. Time-based filters behave similarly at different rates.
    @discardableResult public mutating func ingest(_ field: FieldVector, timestamp: Double) -> Bool {
        guard field.isFinite, timestamp.isFinite,
              previousTime.map({ timestamp > $0 }) ?? true else { return false }
        let dt = min(max(previousTime.map { timestamp - $0 } ?? (1.0 / 60), 0.001), 0.1)
        let alpha = 1 - exp(-dt / 0.10)
        let smooth = filtered.map { $0 + (field - $0) * alpha } ?? field
        // Even finite input can overflow intermediate subtraction. Never commit poisoned state.
        guard smooth.isFinite else { return false }
        guard let baseline else {
            previousTime = timestamp; filtered = smooth
            gazeX = 0; gazeY = 0; return true
        }
        let change = smooth - baseline
        guard change.isFinite, change.magnitude.isFinite else { return false }
        let a: Double
        let b: Double
        switch axisPair {
        case .xy: a = change.x; b = change.y
        case .xz: a = change.x; b = change.z
        case .yz: a = change.y; b = change.z
        }
        let length = hypot(a, b)
        previousTime = timestamp; filtered = smooth; delta = change
        // Radial deadzone keeps the response continuous at its boundary.
        let finiteSensitivity = sensitivity.isFinite ? sensitivity : 1
        let amount = min(1, max(0, length - deadzone) * min(4, max(0.25, finiteSensitivity)) / 40)
        let targetX = length > 0 ? a / length * amount * (invertX ? -1 : 1) : 0
        // Core Motion +Y points toward the top of a portrait phone; SwiftUI +Y points down.
        let targetY = length > 0 ? -b / length * amount * (invertY ? -1 : 1) : 0
        let gazeAlpha = 1 - exp(-dt / 0.065)
        gazeX += (targetX - gazeX) * gazeAlpha
        gazeY += (targetY - gazeY) * gazeAlpha
        return true
    }
}

/// Collects one second of raw, stationary samples for a fixed local background reference.
/// Variance catches unstable fields; it cannot prove the magnet was removed or phone did not move.
public struct BaselineCapture: Sendable {
    private var samples: [FieldVector] = []
    private var start: Double?
    private var last: Double?
    public private(set) var progress = 0.0
    public init() {}
    public enum Result: Equatable { case collecting, accepted(FieldVector), unstable }
    public mutating func ingest(_ field: FieldVector, timestamp: Double) -> Result {
        guard field.isFinite, timestamp.isFinite,
              last.map({ timestamp > $0 }) ?? true else { return .collecting }
        if start == nil { start = timestamp }
        last = timestamp
        samples.append(field)
        progress = min(1, max(0, timestamp - (start ?? timestamp)))
        guard progress >= 1, samples.count >= 20 else { return .collecting }
        let mean = samples.reduce(.zero, +) * (1 / Double(samples.count))
        let variance = samples.reduce(0.0) { sum, sample in
            let distance = (sample - mean).magnitude
            return sum + distance * distance
        } / Double(samples.count)
        return sqrt(variance) <= 3 ? .accepted(mean) : .unstable
    }
}
