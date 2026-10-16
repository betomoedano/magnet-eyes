import Combine
import CoreMotion
import Foundation
import MagnetEyesCore

// Synthetic input is opt-in, including on Simulator. Never substitute it for live readings.
enum SensorSource { case live, demo }

@MainActor
final class MagnetometerModel: ObservableObject {
    @Published private(set) var gazeX = 0.0
    @Published private(set) var gazeY = 0.0
    @Published private(set) var rawField: FieldVector?
    @Published private(set) var fieldChange = 0.0
    /// Filtered change from the captured baseline, in µT. Nil until a valid baseline exists.
    @Published private(set) var deltaField: FieldVector?
    @Published private(set) var status = "Remove the magnet, keep the phone still, then recenter."
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var isReady = false
    @Published private(set) var isRunning = false
    @Published private(set) var source: SensorSource = .live
    @Published var sensitivity = 1.0
    @Published var invertX = false
    @Published var invertY = false
    @Published var axisPair: AxisPair = .xy

    private let motion = CMMotionManager()
    private var response = FieldResponse()
    private var capture: BaselineCapture?
    private var ticker: Timer?
    private var generation = UUID()
    private var latestSampleAt: TimeInterval = 0
    private var captureStartedAt: TimeInterval = 0
    private var demoTime = 0.0
    private var active = false
    private var demoReference = FieldVector(x: 18, y: -4, z: -38)

    var isAvailable: Bool { source == .demo || motion.isMagnetometerAvailable }

    init() {
        // An explicit launch argument is useful for automated visual testing; the DEMO label remains.
        if ProcessInfo.processInfo.arguments.contains("--demo") { source = .demo }
    }

    func start() {
        guard !active else { return }
        active = true
        generation = UUID()
        let session = generation
        response.reset()
        gazeX = 0; gazeY = 0; fieldChange = 0; rawField = nil; deltaField = nil
        isReady = false; isCalibrating = false; calibrationProgress = 0; capture = nil
        if source == .demo {
            response.setBaseline(demoReference)
            isReady = true
            isRunning = true
            demoTime = 0
            status = "Simulated field. No magnetometer readings."
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.active, self.generation == session, self.source == .demo else { return }
                    self.demoTick()
                }
            }
            return
        }
        guard motion.isMagnetometerAvailable else {
            isRunning = false
            #if targetEnvironment(simulator)
            status = "Simulator has no magnetometer. Choose Demo to preview the animation."
            #else
            status = "Magnetometer unavailable on this device. Demo is a separate simulated preview."
            #endif
            return
        }
        status = "Remove the magnet, keep the phone still, then recenter."
        motion.magnetometerUpdateInterval = 1.0 / 60
        latestSampleAt = ProcessInfo.processInfo.systemUptime
        isRunning = true
        motion.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            // Generation check prevents an old callback from crossing a stop/source change.
            let sample = data.map { FieldVector(x: $0.magneticField.x, y: $0.magneticField.y, z: $0.magneticField.z) }
            let timestamp = data?.timestamp
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.active, self.generation == session, self.source == .live else { return }
                if let failure { self.fail("Sensor stopped: \(failure). Check Motion access in Settings, then Retry."); return }
                guard let sample, let timestamp else { return }
                self.consume(sample, timestamp: timestamp)
            }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active, self.generation == session else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.latestSampleAt > 3 {
                    self.fail("No recent sensor readings. Check Motion access in Settings, then Retry.")
                } else if self.isCalibrating && now - self.captureStartedAt > 5 {
                    self.capture = nil; self.isCalibrating = false
                    self.status = "Too few samples to recenter. Hold still and try again."
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        active = false
        motion.stopMagnetometerUpdates()
        ticker?.invalidate(); ticker = nil
        capture = nil
        isRunning = false; isReady = false; isCalibrating = false
        calibrationProgress = 0
        gazeX = 0; gazeY = 0; fieldChange = 0; rawField = nil; deltaField = nil
        response.reset()
        status = "Paused. Recenter after returning to the app."
    }

    func useSource(_ newSource: SensorSource) {
        guard source != newSource else { return }
        stop(); source = newSource; start()
    }

    func retry() { stop(); start() }

    func recenter() {
        guard isRunning, rawField != nil, !isCalibrating else { return }
        // Invalidate the old baseline immediately so a failed calibration never looks ready.
        response.reset()
        isReady = false; gazeX = 0; gazeY = 0; fieldChange = 0; deltaField = nil
        capture = BaselineCapture()
        isCalibrating = true; calibrationProgress = 0
        captureStartedAt = ProcessInfo.processInfo.systemUptime
        status = source == .demo ? "Capturing a simulated baseline…" : "Hold still for one second. Keep the magnet away."
    }

    private func demoTick() {
        if !isCalibrating { demoTime += 1.0 / 60 }
        let input: FieldVector
        if isCalibrating {
            input = demoReference
        } else {
            input = demoReference + FieldVector(x: sin(demoTime * 0.82) * 36,
                                               y: sin(demoTime * 0.57) * 24,
                                               z: cos(demoTime * 0.63) * 12)
        }
        consume(input, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    private func consume(_ field: FieldVector, timestamp: Double) {
        guard field.isFinite else { return }
        response.sensitivity = sensitivity
        response.invertX = invertX; response.invertY = invertY; response.axisPair = axisPair
        guard response.ingest(field, timestamp: timestamp) else { return }
        latestSampleAt = ProcessInfo.processInfo.systemUptime
        rawField = field
        if var capture {
            let result = capture.ingest(field, timestamp: timestamp)
            self.capture = capture
            calibrationProgress = capture.progress
            switch result {
            case .collecting: break
            case .accepted(let baseline):
                response.setBaseline(baseline)
                self.capture = nil; isCalibrating = false; isReady = true
                status = source == .demo ? "Simulated field. No magnetometer readings." : "Baseline set. Keep the phone still and move a weak magnet nearby."
            case .unstable:
                self.capture = nil; isCalibrating = false; isReady = false
                status = "Field changed during recenter. Remove the magnet, hold still, and try again."
            }
        }
        gazeX = response.gazeX; gazeY = response.gazeY
        fieldChange = response.delta.magnitude
        deltaField = isReady ? response.delta : nil
    }

    private func fail(_ message: String) {
        stop()
        status = message
    }

    deinit {
        motion.stopMagnetometerUpdates()
        ticker?.invalidate()
    }
}
