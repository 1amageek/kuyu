import KuyuCore
import KuyuPhysics
import SwiftUI

struct KuyuSimulationPreviewView: View {
    @Bindable var model: SimulationViewModel
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                ZStack(alignment: .topLeading) {
                    previewCanvas
                    VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
                        PreviewStatusView(label: "Task", value: model.taskMode.rawValue)
                        PreviewStatusView(label: "z", value: String(format: "%.3f", position.z))
                        PreviewStatusView(label: "roll", value: String(format: "%.2f", roll))
                        PreviewStatusView(label: "pitch", value: String(format: "%.2f", pitch))
                    }
                    .padding(KuyuSpacing.sm)
                    .frame(width: 128)
                    .background(.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous))
                    .padding(KuyuSpacing.sm)
                }
                .frame(minHeight: 220)

                observationChips
            }
        } label: {
            HStack {
                Label("Kuyu Simulation", systemImage: "cube.transparent")
                Spacer()
                StatusPill(renderInfo == nil ? "proxy" : "mesh", tone: renderInfo == nil ? .warning : .info)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewCanvas: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: 0.025, green: 0.055, blue: 0.070)))
            drawGrid(context: &context, size: size)
            drawEnvelope(context: &context, size: size)
            drawRobot(context: &context, size: size)
        }
        .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KuyuRadius.medium, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    /// Canonical label for an observation channel index (8-channel lift/single-lift
    /// schema: ch0..5 IMU, ch6 altitude z, ch7 vertical velocity z).
    private func channelLabel(_ index: UInt32) -> String {
        switch index {
        case 0: "gyroX"
        case 1: "gyroY"
        case 2: "gyroZ"
        case 3: "accX"
        case 4: "accY"
        case 5: "accZ"
        case 6: "alt"
        case 7: "vz"
        default: "ch\(index)"
        }
    }

    private var observationChips: some View {
        // Render the real post-emulation sensor stream. No live samples → an explicit
        // "no data" placeholder rather than fabricated pose values.
        let samples = model.lastSensorSamples.sorted { $0.channelIndex < $1.channelIndex }
        return VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            Text("Sensor stream (post-emulation)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if samples.isEmpty {
                Text("No live sensor data — run a simulation to populate channels.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 56), spacing: KuyuSpacing.xs), count: 4),
                    spacing: KuyuSpacing.xs
                ) {
                    ForEach(samples, id: \.channelIndex) { sample in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channelLabel(sample.channelIndex))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.3f", sample.value))
                                .font(.system(.caption2, design: .monospaced))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, KuyuSpacing.sm)
                        .padding(.vertical, KuyuSpacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous))
                    }
                }
            }
        }
        .accessibilityLabel("sensor channel observation")
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        let step: CGFloat = 24
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 1)
    }

    private func drawEnvelope(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.72, y: size.height * 0.34)
        let target = CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
        context.stroke(Path(ellipseIn: target), with: .color(.green.opacity(0.9)), lineWidth: 3)
        context.stroke(Path(ellipseIn: target.insetBy(dx: 7, dy: 7)), with: .color(.green.opacity(0.5)), lineWidth: 2)

        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.72))
        path.addCurve(
            to: center,
            control1: CGPoint(x: size.width * 0.38, y: size.height * 0.50),
            control2: CGPoint(x: size.width * 0.58, y: size.height * 0.60)
        )
        context.stroke(path, with: .color(.cyan.opacity(0.85)), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
    }

    private func drawRobot(context: inout GraphicsContext, size: CGSize) {
        let x = size.width * 0.46 + CGFloat(position.x) * 16
        let y = size.height * 0.58 - CGFloat(position.z) * 30
        let center = CGPoint(x: x, y: y)
        let body = CGRect(x: center.x - 16, y: center.y - 12, width: 32, height: 24)
        context.fill(Path(roundedRect: body, cornerRadius: 8), with: .color(.white.opacity(0.82)))
        context.stroke(Path(roundedRect: body, cornerRadius: 8), with: .color(.cyan.opacity(0.55)), lineWidth: 2)

        var arm = Path()
        arm.move(to: CGPoint(x: center.x - 28, y: center.y))
        arm.addLine(to: CGPoint(x: center.x + 28, y: center.y))
        arm.move(to: CGPoint(x: center.x, y: center.y - 24))
        arm.addLine(to: CGPoint(x: center.x, y: center.y + 24))
        context.stroke(arm, with: .color(.white.opacity(0.44)), lineWidth: 5)
    }
}
