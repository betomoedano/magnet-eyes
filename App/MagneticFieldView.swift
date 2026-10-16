import SwiftUI
import MagnetEyesCore

/// One measured field-change vector. A magnetometer does not identify individual magnets.
struct MagneticFieldView: View {
    @ObservedObject var model: MagnetometerModel
    @State private var range = 50.0

    private let ink = Color(red: 0.16, green: 0.21, blue: 0.21)
    private let accent = Color(red: 0.18, green: 0.43, blue: 0.41)
    private let muted = Color(red: 0.45, green: 0.50, blue: 0.50)

    private var axes: (horizontal: String, vertical: String) {
        switch model.axisPair {
        case .xy: return ("X", "Y")
        case .xz: return ("X", "Z")
        case .yz: return ("Y", "Z")
        }
    }

    private var components: (horizontal: Double, vertical: Double)? {
        guard let delta = model.deltaField else { return nil }
        switch model.axisPair {
        case .xy: return (delta.x, delta.y)
        case .xz: return (delta.x, delta.z)
        case .yz: return (delta.y, delta.z)
        }
    }

    private var isOutOfRange: Bool {
        guard let components else { return false }
        return abs(components.horizontal) > range || abs(components.vertical) > range
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Field change")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(model.deltaField.map { "Δ \(number($0.magnitude)) µT" } ?? "Δ — µT")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(ink)

            plot

            HStack(spacing: 10) {
                Text("Range · µT")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(muted)
                Picker("Field range in microteslas", selection: $range) {
                    Text("±50").tag(50.0)
                    Text("±200").tag(200.0)
                    Text("±1000").tag(1000.0)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("field-range")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Δ\(axes.horizontal) \(components.map { number($0.horizontal) } ?? "—") µT")
                Spacer(minLength: 0)
                Text("Δ\(axes.vertical) \(components.map { number($0.vertical) } ?? "—") µT")
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(ink)
            .minimumScaleFactor(0.75)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("field-measurement")

            VStack(spacing: 7) {
                if let raw = model.rawField {
                    Text("Raw  X \(number(raw.x))  Y \(number(raw.y))  Z \(number(raw.z)) µT")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .foregroundStyle(muted)
                        .accessibilityLabel("Raw magnetic field. X \(number(raw.x)), Y \(number(raw.y)), Z \(number(raw.z)) microteslas")
                } else {
                    Text("Raw X —  Y —  Z — µT")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(muted)
                }
                Text("Combined field change · not magnet positions")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                if model.source == .demo {
                    Text("SIMULATED READINGS · no sensor data")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.56, green: 0.35, blue: 0.12))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(ink.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("field-view")
    }

    private var plot: some View {
        GeometryReader { geometry in
            let rect = plotRect(in: geometry.size)
            let point = components.map { plotPoint(horizontal: $0.horizontal, vertical: $0.vertical, in: rect) }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.97, green: 0.98, blue: 0.97))

                Canvas { context, _ in
                    drawGrid(in: rect, context: &context)
                    if let point {
                        drawVector(to: point, in: rect, context: &context)
                    }
                }
                .accessibilityHidden(true)

                if let point {
                    ZStack {
                        Circle().fill(accent.opacity(0.12)).frame(width: 28, height: 28)
                        Circle().fill(accent).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                    .position(point)
                    .accessibilityElement()
                    .accessibilityLabel("Combined field-change vector")
                    .accessibilityValue("Delta \(axes.horizontal) \(number(components?.horizontal ?? 0)), delta \(axes.vertical) \(number(components?.vertical ?? 0)) microteslas\(isOutOfRange ? ", outside plot range" : "")")
                    .accessibilityIdentifier("field-marker")
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 24, weight: .light))
                        Text(model.isCalibrating ? "Setting baseline…" : "Recenter to plot the field")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
                    .position(x: rect.midX, y: rect.midY)
                }

                if isOutOfRange {
                    Text("Out of range · marker clipped")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(red: 0.56, green: 0.35, blue: 0.12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.96), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 38)
                }
            }
        }
        .frame(height: 240)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Field-change plot, horizontal delta \(axes.horizontal), vertical delta \(axes.vertical), range minus \(Int(range)) to plus \(Int(range)) microteslas")
        .accessibilityIdentifier("field-grid")
    }

    private func plotRect(in size: CGSize) -> CGRect {
        // Leave real space for signed tick labels, including the ±1000 µT range.
        let availableWidth = max(1, size.width - 62)
        let availableHeight = max(1, size.height - 56)
        let side = min(availableWidth, availableHeight)
        return CGRect(x: 42 + (availableWidth - side) / 2,
                      y: 24 + (availableHeight - side) / 2,
                      width: side, height: side)
    }

    private func plotPoint(horizontal: Double, vertical: Double, in rect: CGRect) -> CGPoint {
        // Scale both components together when clipped, preserving the measured direction.
        let scale = max(range, max(abs(horizontal), abs(vertical)))
        return CGPoint(x: rect.midX + horizontal / scale * rect.width / 2,
                       y: rect.midY - vertical / scale * rect.height / 2)
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext) {
        var fineGrid = Path()
        for index in 0...8 {
            let fraction = Double(index) / 8
            let x = rect.minX + fraction * rect.width
            let y = rect.minY + fraction * rect.height
            fineGrid.move(to: CGPoint(x: x, y: rect.minY))
            fineGrid.addLine(to: CGPoint(x: x, y: rect.maxY))
            fineGrid.move(to: CGPoint(x: rect.minX, y: y))
            fineGrid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(fineGrid, with: .color(ink.opacity(0.07)), lineWidth: 0.75)

        var axesPath = Path()
        axesPath.move(to: CGPoint(x: rect.minX, y: rect.midY))
        axesPath.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        axesPath.move(to: CGPoint(x: rect.midX, y: rect.minY))
        axesPath.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.stroke(axesPath, with: .color(ink.opacity(0.23)), lineWidth: 1)

        for fraction in [-1.0, 0, 1.0] {
            let value = Int(fraction * range)
            let label = value > 0 ? "+\(value)" : "\(value)"
            let tick = Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
            context.draw(tick, at: CGPoint(x: rect.midX + fraction * rect.width / 2, y: rect.maxY + 12))
            context.draw(tick, at: CGPoint(x: rect.minX - 7, y: rect.midY - fraction * rect.height / 2), anchor: .trailing)
        }

        context.draw(Text("Δ\(axes.vertical) · µT").font(.system(size: 10, weight: .medium)).foregroundStyle(muted),
                     at: CGPoint(x: rect.midX, y: 10))
        context.draw(Text("Δ\(axes.horizontal) · µT").font(.system(size: 10, weight: .medium)).foregroundStyle(muted),
                     at: CGPoint(x: rect.midX, y: rect.maxY + 25))
    }

    private func drawVector(to point: CGPoint, in rect: CGRect, context: inout GraphicsContext) {
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        var line = Path()
        line.move(to: origin)
        line.addLine(to: point)
        context.stroke(line, with: .color(accent.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let length = hypot(dx, dy)
        if length > 16 {
            let unitX = dx / length
            let unitY = dy / length
            let tip = CGPoint(x: point.x - unitX * 6, y: point.y - unitY * 6)
            var arrow = Path()
            arrow.move(to: CGPoint(x: tip.x - unitX * 7 + unitY * 4, y: tip.y - unitY * 7 - unitX * 4))
            arrow.addLine(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - unitX * 7 - unitY * 4, y: tip.y - unitY * 7 + unitX * 4))
            context.stroke(arrow, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        context.fill(Path(ellipseIn: CGRect(x: origin.x - 2.5, y: origin.y - 2.5, width: 5, height: 5)),
                     with: .color(ink.opacity(0.35)))
    }

    private func number(_ value: Double) -> String {
        // Suppress a visually confusing negative zero in the stationary readout.
        String(format: "%.1f", abs(value) < 0.05 ? 0 : value)
    }
}
