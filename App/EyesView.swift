import SwiftUI
import MagnetEyesCore

/// Gaze always comes from the explicitly selected live or demo data source.
struct EyesView: View {
    @ObservedObject var model: MagnetometerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("showMagneticFieldDebug") private var showDebug = false
    @State private var showsSettings = false
    @State private var cameraMode = false
    @State private var selectedView: DisplayMode = .eyes

    private enum DisplayMode: String, CaseIterable { case eyes = "Eyes", field = "Field" }
    private var isDemo: Bool { model.source == .demo }
    private var hasNoSensor: Bool { !model.isAvailable && !isDemo }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                EyePalette.background.ignoresSafeArea()
                if cameraMode {
                    cameraStage(size: geometry.size)
                } else {
                    ScrollView {
                        controlsStage(size: geometry.size)
                            .frame(minHeight: geometry.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .foregroundStyle(EyePalette.ink)
            .sheet(isPresented: $showsSettings) {
                FieldSettings(model: model, showDebug: $showDebug)
            }
        }
        .tint(EyePalette.ink)
        .preferredColorScheme(.light)
    }

    private func controlsStage(size: CGSize) -> some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 14)

            viewSelector
                .padding(.top, 25)

            Spacer(minLength: 30)

            if selectedView == .eyes {
                EyePair(gazeX: model.gazeX, gazeY: model.gazeY)
                    .frame(height: min(size.width * 0.66, 300))
                    .accessibilityHidden(true)
            } else {
                MagneticFieldView(model: model)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 30)

            VStack(spacing: 18) {
                if showDebug && selectedView == .eyes {
                    FieldReadout(model: model)
                }
                statusMessage
                bottomControls
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 25)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Magnet Eyes")
                .font(.headline)
            Spacer(minLength: 0)
            SourceBadge(model: model)
        }
    }

    private var viewSelector: some View {
        HStack(spacing: 3) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                Button {
                    selectedView = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .foregroundStyle(selectedView == mode ? EyePalette.ink : EyePalette.secondary)
                        .background {
                            if selectedView == mode {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(mode == .eyes ? "view-eyes" : "view-field")
                .accessibilityAddTraits(selectedView == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(EyePalette.control, in: RoundedRectangle(cornerRadius: 13))
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 230)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visualization")
    }

    private var statusMessage: some View {
        VStack(spacing: 10) {
            Text(statusDetail)
                .font(.footnote)
                .foregroundStyle(EyePalette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if model.isCalibrating {
                ProgressView(value: model.calibrationProgress)
                    .tint(EyePalette.ink)
                    .frame(maxWidth: 180)
                    .accessibilityLabel("Baseline calibration")
            }

            if hasNoSensor {
                Button("Try demo") { model.useSource(.demo) }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 36)
                    .accessibilityIdentifier("demo-mode")
            } else if !model.isRunning && !model.isCalibrating {
                Button("Retry sensor", action: model.retry)
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 36)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusDetail: String {
        if hasNoSensor { return model.status }
        if model.isCalibrating {
            return isDemo ? "Capturing a simulated baseline…" : "Keep still with the magnet removed."
        }
        if !model.isRunning || !model.isReady { return model.status }
        if isDemo { return "Simulated field · no live sensor data" }
        return "Keep the phone still. Move a small magnet nearby."
    }

    private var bottomControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Button(action: model.recenter) {
                    Label(model.isCalibrating ? "Centering…" : "Recenter", systemImage: "scope")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .foregroundStyle(.white)
                        .background(EyePalette.ink, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(hasNoSensor || model.isCalibrating || !model.isRunning)
                .opacity(hasNoSensor || model.isCalibrating || !model.isRunning ? 0.35 : 1)
                .accessibilityIdentifier("recenter")
                .accessibilityHint("Keep the phone still with the magnet removed while a baseline is captured.")

                Button { showsSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.medium))
                        .frame(width: 50, height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(EyePalette.stroke, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Field controls")
                .accessibilityIdentifier("settings")
            }

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    cameraMode = true
                }
            } label: {
                Label("Camera mode", systemImage: "viewfinder")
                    .font(.footnote)
                    .foregroundStyle(EyePalette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 38)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("camera-mode")
        }
    }

    private func cameraStage(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack {
                if isDemo || hasNoSensor || !model.isReady || !model.isRunning {
                    SourceBadge(model: model)
                }
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        cameraMode = false
                    }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.body)
                        .foregroundStyle(EyePalette.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Exit camera mode")
                .accessibilityIdentifier("exit-camera-mode")
            }
            .padding(.top, 8)

            if selectedView == .eyes {
                EyePair(gazeX: model.gazeX, gazeY: model.gazeY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                ScrollView {
                    MagneticFieldView(model: model)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: max(0, size.height - 64))
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .padding(.horizontal, 25)
    }
}

private struct EyePair: View {
    let gazeX: Double
    let gazeY: Double

    var body: some View {
        GeometryReader { geometry in
            let width = min((geometry.size.width - 20) / 2, geometry.size.height / 1.36, 184)
            HStack(spacing: 20) {
                EyeArtwork(gazeX: gazeX, gazeY: gazeY)
                EyeArtwork(gazeX: gazeX, gazeY: gazeY)
            }
            .frame(width: width * 2 + 20, height: width * 1.36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EyeArtwork: View {
    let gazeX: Double
    let gazeY: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pupilWidth = size.width * 0.43
            let pupilHeight = size.height * 0.35
            let horizontalTravel = (size.width - pupilWidth) * 0.35
            let verticalTravel = (size.height - pupilHeight) * 0.33
            let shape = RoundedRectangle(cornerRadius: size.width * 0.5, style: .continuous)

            ZStack {
                shape.fill(.white)
                shape.strokeBorder(EyePalette.ink, lineWidth: 2)
                Ellipse()
                    .fill(EyePalette.ink)
                    .frame(width: pupilWidth, height: pupilHeight)
                    .offset(
                        x: min(1, max(-1, gazeX)) * horizontalTravel,
                        y: min(1, max(-1, gazeY)) * verticalTravel
                    )
            }
            .clipShape(shape)
        }
    }
}

private struct SourceBadge: View {
    @ObservedObject var model: MagnetometerModel

    private var isDemo: Bool { model.source == .demo }
    private var label: String {
        if isDemo { return "DEMO" }
        if !model.isAvailable { return "NO SENSOR" }
        if !model.isRunning { return "PAUSED" }
        return model.isReady ? "LIVE" : "RECENTER"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isDemo ? EyePalette.amber : EyePalette.secondary)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(isDemo ? EyePalette.amber : EyePalette.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(Capsule().strokeBorder(EyePalette.stroke, lineWidth: 1))
        .accessibilityLabel(isDemo ? "DEMO. Simulated sensor data." : label)
    }
}

private struct FieldReadout: View {
    @ObservedObject var model: MagnetometerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.source == .demo ? "Simulated field · µT" : "Magnetometer · µT")
                .font(.caption)
                .foregroundStyle(EyePalette.secondary)
            HStack(spacing: 4) {
                reading("X", model.rawField?.x)
                reading("Y", model.rawField?.y)
                reading("Z", model.rawField?.z)
                reading("Δ", model.isReady ? model.fieldChange : nil)
            }
        }
    }

    private func reading(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(EyePalette.secondary)
            Text(value.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(.subheadline, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.identity)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { String(format: "%.1f microteslas", $0) } ?? "No reading")
    }
}

private struct FieldSettings: View {
    @ObservedObject var model: MagnetometerModel
    @Binding var showDebug: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                responseSection
                calibrationSection
                debugSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(EyePalette.background)
            .navigationTitle("Field controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .foregroundStyle(EyePalette.ink)
        .tint(EyePalette.ink)
        .preferredColorScheme(.light)
    }

    private var sourceSection: some View {
        Section {
            HStack(spacing: 8) {
                sourceButton("Live sensor", source: .live, identifier: "live-mode")
                sourceButton("Demo", source: .demo, identifier: "demo-mode")
            }
            .listRowInsets(EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12))
        } header: {
            Text("Source")
        } footer: {
            Text(model.status)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourceButton(_ title: String, source: SensorSource, identifier: String) -> some View {
        let selected = model.source == source
        return Button {
            model.useSource(source)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .foregroundStyle(selected ? .white : EyePalette.ink)
                .background(selected ? EyePalette.ink : EyePalette.control, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var responseSection: some View {
        Section {
            VStack(spacing: 8) {
                HStack {
                    Text("Sensitivity")
                    Spacer()
                    Text(String(format: "%.2f×", model.sensitivity))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(EyePalette.secondary)
                }
                Slider(value: $model.sensitivity, in: 0.25...4)
                    .accessibilityLabel("Sensitivity")
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text("Field axes")
                Picker("Field axes", selection: $model.axisPair) {
                    ForEach(AxisPair.allCases) { pair in
                        Text(pair.rawValue).tag(pair)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            Toggle("Invert horizontal", isOn: $model.invertX)
            Toggle("Invert vertical", isOn: $model.invertY)
        } header: {
            Text("Response")
        } footer: {
            Text("For the eyes, the first axis moves left–right; the second moves up–down. Field view shows the selected field components in µT, without display gain or inversion.")
        }
    }

    private var calibrationSection: some View {
        Section {
            Button {
                model.recenter()
            } label: {
                Label(model.isCalibrating ? "Centering…" : "Capture baseline", systemImage: "scope")
            }
            .disabled(!model.isRunning || model.isCalibrating)
            if model.isCalibrating {
                ProgressView(value: model.calibrationProgress)
            }
        } header: {
            Text("Baseline")
        } footer: {
            Text("Keep the phone still with the magnet removed. Moving or rotating the phone changes the field reading too.")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle("Show field readings", isOn: $showDebug)
            if showDebug {
                FieldReadout(model: model)
                    .padding(.vertical, 6)
            }
        } header: {
            Text("Readings")
        } footer: {
            Text("Δ is the field change from the baseline, in microteslas (µT). Demo uses simulated readings and always displays a DEMO label, including in camera mode.")
        }
    }

    private var aboutSection: some View {
        Section("About this experiment") {
            Text("One sensor measures the combined magnetic field. It cannot count, separate, or locate nearby magnets. The grid plots field change, not magnet positions.")
            Text("The eyes use a calibrated field-change heuristic. A convincing response toward a magnet needs a stationary phone, consistent magnet orientation, and tuned axes.")
            Text("Use a small, weak fridge magnet. Avoid powerful magnets and magnetic phone accessories.")
        }
        .font(.footnote)
        .foregroundStyle(EyePalette.secondary)
    }
}

private enum EyePalette {
    static let background = Color(red: 0.975, green: 0.973, blue: 0.963)
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.18)
    static let secondary = Color(red: 0.44, green: 0.45, blue: 0.45)
    static let stroke = Color(red: 0.83, green: 0.84, blue: 0.82)
    static let control = Color(red: 0.92, green: 0.925, blue: 0.91)
    static let amber = Color(red: 0.53, green: 0.35, blue: 0.10)
}
