import KuyuCore
import KuyuPhysics
import SwiftUI

struct KuyuSimulationPreviewView: View {
    private enum ProjectionMode: String, CaseIterable, Identifiable {
        case dual
        case side
        case top
        case front

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dual: return "Dual"
            case .side: return "Side"
            case .top: return "Top"
            case .front: return "Front"
            }
        }
    }

    private enum ProjectionPlane: String {
        case side
        case top
        case front

        var label: String {
            switch self {
            case .side: return "Side Y-Z"
            case .top: return "Top X-Y"
            case .front: return "Front X-Z"
            }
        }
    }

    @Bindable var model: SimulationViewModel
    let roll: Double
    let pitch: Double
    let yaw: Double
    let position: Axis3
    let renderInfo: RenderAssetInfo?
    let jointAngles: [Double]
    let jointValues: [String: Double]
    let sensorSamples: [ChannelSample]
    let stepIndex: UInt64?
    let snapshotTime: Double?
    @State private var projectionMode: ProjectionMode = .dual

    init(
        model: SimulationViewModel,
        roll: Double,
        pitch: Double,
        yaw: Double,
        position: Axis3,
        renderInfo: RenderAssetInfo?,
        jointAngles: [Double] = [],
        jointValues: [String: Double] = [:],
        sensorSamples: [ChannelSample] = [],
        stepIndex: UInt64? = nil,
        snapshotTime: Double? = nil
    ) {
        self.model = model
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.position = position
        self.renderInfo = renderInfo
        self.jointAngles = jointAngles
        self.jointValues = jointValues
        self.sensorSamples = sensorSamples
        self.stepIndex = stepIndex
        self.snapshotTime = snapshotTime
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: KuyuSpacing.md) {
                projectionControls
                snapshotHeader
                projectedPreview
                    .frame(height: projectionMode == .dual ? 320 : 260)
                if model.simulationShowsSensorReadouts {
                    observationChips
                }
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

    private var snapshotHeader: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xs) {
            HStack(spacing: KuyuSpacing.sm) {
                Text(model.currentRobotManifest()?.name ?? model.taskMode.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                if let stepIndex {
                    Text("step \(stepIndex)")
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let snapshotTime {
                    Text(String(format: "t %.2fs", snapshotTime))
                        .font(.system(.caption2, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            jointSnapshot
        }
    }

    @ViewBuilder
    private var jointSnapshot: some View {
        if !jointAngles.isEmpty {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 54), spacing: KuyuSpacing.xs), count: min(jointAngles.count, 5)),
                spacing: KuyuSpacing.xs
            ) {
                ForEach(Array(jointAngles.enumerated()), id: \.offset) { index, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(jointLabel(index))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(String(format: "%.2f", value))
                            .font(.system(.caption2, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, KuyuSpacing.sm)
                    .padding(.vertical, KuyuSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous))
                }
            }
        } else {
            HStack(spacing: KuyuSpacing.xs) {
                poseChip(label: "z", value: position.z)
                poseChip(label: "roll", value: roll)
                poseChip(label: "pitch", value: pitch)
            }
        }
    }

    private func poseChip(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(.caption2, design: .monospaced))
                .monospacedDigit()
        }
        .padding(.horizontal, KuyuSpacing.sm)
        .padding(.vertical, KuyuSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: KuyuRadius.small, style: .continuous))
    }

    private var projectionControls: some View {
        Picker("Projection", selection: $projectionMode) {
            ForEach(ProjectionMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("projection mode")
    }

    @ViewBuilder
    private var projectedPreview: some View {
        switch projectionMode {
        case .dual:
            VStack(spacing: KuyuSpacing.xs) {
                previewCanvas(plane: .side)
                previewCanvas(plane: .top)
            }
        case .side:
            previewCanvas(plane: .side)
        case .top:
            previewCanvas(plane: .top)
        case .front:
            previewCanvas(plane: .front)
        }
    }

    private func previewCanvas(plane: ProjectionPlane) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: 0.025, green: 0.055, blue: 0.070)))
            drawGrid(context: &context, size: size)
            drawPlaneLabel(context: &context, plane: plane, size: size)
            if model.simulationShowsTrajectoryOverlay {
                drawEnvelope(context: &context, size: size, plane: plane)
            }
            drawRobot(context: &context, size: size, plane: plane)
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
        if !jointAngles.isEmpty {
            return jointLabel(Int(index))
        }
        switch index {
        case 0: return "gyroX"
        case 1: return "gyroY"
        case 2: return "gyroZ"
        case 3: return "accX"
        case 4: return "accY"
        case 5: return "accZ"
        case 6: return "alt"
        case 7: return "vz"
        default: return "ch\(index)"
        }
    }

    private var observationChips: some View {
        // Render the real post-emulation sensor stream. No live samples → an explicit
        // "no data" placeholder rather than fabricated pose values.
        let samples = sensorSamples.sorted { $0.channelIndex < $1.channelIndex }
        let columnCount = !jointAngles.isEmpty ? min(max(samples.count, 1), 5) : 4
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
                    columns: Array(repeating: GridItem(.flexible(minimum: 48), spacing: KuyuSpacing.xs), count: columnCount),
                    spacing: KuyuSpacing.xs
                ) {
                    ForEach(samples, id: \.channelIndex) { sample in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channelLabel(sample.channelIndex))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(String(format: "%.3f", sample.value))
                                .font(.system(.caption2, design: .monospaced))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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

    private func drawPlaneLabel(context: inout GraphicsContext, plane: ProjectionPlane, size: CGSize) {
        let text = Text(plane.label)
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.62))
        context.draw(text, at: CGPoint(x: size.width - 12, y: 12), anchor: .topTrailing)
    }

    private func drawEnvelope(context: inout GraphicsContext, size: CGSize, plane: ProjectionPlane) {
        let center = envelopeCenter(size: size, plane: plane)
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

    private func drawRobot(context: inout GraphicsContext, size: CGSize, plane: ProjectionPlane) {
        if !jointAngles.isEmpty {
            drawJointChain(context: &context, size: size, plane: plane)
            return
        }
        let center = project(
            KuyuPreviewPoint3D(x: position.x, y: position.y, z: position.z),
            plane: plane,
            size: size,
            scale: 30
        )
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

    private func drawJointChain(context: inout GraphicsContext, size: CGSize, plane: ProjectionPlane) {
        let points3D = jointChainPoints()
        let scale = min(size.width, size.height) * (plane == .top ? 1.25 : 1.05)
        let points = points3D.map { project($0, plane: plane, size: size, scale: scale) }
        let base = points[0]

        let baseRect = CGRect(x: base.x - 18, y: base.y - 10, width: 36, height: 20)
        context.fill(Path(roundedRect: baseRect, cornerRadius: 6), with: .color(.white.opacity(0.82)))

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        context.stroke(path, with: .color(.cyan.opacity(0.9)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

        for point in points {
            let jointRect = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: jointRect), with: .color(.white.opacity(0.95)))
            context.stroke(Path(ellipseIn: jointRect), with: .color(.black.opacity(0.45)), lineWidth: 1)
        }

        drawGripper(context: &context, points3D: points3D, plane: plane, size: size, scale: scale)
    }

    private func drawGripper(
        context: inout GraphicsContext,
        points3D: [KuyuPreviewPoint3D],
        plane: ProjectionPlane,
        size: CGSize,
        scale: CGFloat
    ) {
        guard let wrist = points3D.last else { return }
        let opening = max(0.02, min(0.08, 0.02 + abs(jointValue(4)) * 0.035))
        let yawValue = jointValue(0)
        let radial = KuyuPreviewPoint3D(x: sin(yawValue), y: cos(yawValue), z: 0)
        let left = KuyuPreviewPoint3D(
            x: wrist.x + radial.x * opening,
            y: wrist.y + radial.y * opening,
            z: wrist.z + 0.018
        )
        let right = KuyuPreviewPoint3D(
            x: wrist.x - radial.x * opening,
            y: wrist.y - radial.y * opening,
            z: wrist.z - 0.018
        )
        let wrist2D = project(wrist, plane: plane, size: size, scale: scale)
        let left2D = project(left, plane: plane, size: size, scale: scale)
        let right2D = project(right, plane: plane, size: size, scale: scale)
        var gripper = Path()
        gripper.move(to: wrist2D)
        gripper.addLine(to: left2D)
        gripper.move(to: wrist2D)
        gripper.addLine(to: right2D)
        context.stroke(gripper, with: .color(.white.opacity(0.76)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    private func jointChainPoints() -> [KuyuPreviewPoint3D] {
        let yawValue = jointValue(0)
        let radialX = sin(yawValue)
        let radialY = cos(yawValue)
        var radialDistance = 0.0
        var z = 0.062
        var points = [KuyuPreviewPoint3D(x: 0, y: 0, z: 0), point(radialDistance, z, radialX, radialY)]

        var pitchAngle = Double.pi * 0.25 + jointValue(1)
        let segments: [(length: Double, jointIndex: Int?)] = [
            (0.169, 2),
            (0.128, 3),
            (0.069, nil)
        ]
        for segment in segments {
            if let jointIndex = segment.jointIndex {
                pitchAngle += jointValue(jointIndex)
            }
            radialDistance += cos(pitchAngle) * segment.length
            z += sin(pitchAngle) * segment.length
            points.append(point(radialDistance, z, radialX, radialY))
        }
        return points
    }

    private func point(_ radialDistance: Double, _ z: Double, _ radialX: Double, _ radialY: Double) -> KuyuPreviewPoint3D {
        KuyuPreviewPoint3D(x: radialX * radialDistance, y: radialY * radialDistance, z: z)
    }

    private func project(
        _ point: KuyuPreviewPoint3D,
        plane: ProjectionPlane,
        size: CGSize,
        scale: CGFloat
    ) -> CGPoint {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.58)
        let projected: (horizontal: Double, vertical: Double)
        switch plane {
        case .side:
            projected = (point.y, point.z)
        case .top:
            projected = (point.x, point.y)
        case .front:
            projected = (point.x, point.z)
        }
        return CGPoint(
            x: center.x + CGFloat(projected.horizontal) * scale,
            y: center.y - CGFloat(projected.vertical) * scale
        )
    }

    private func envelopeCenter(size: CGSize, plane: ProjectionPlane) -> CGPoint {
        switch plane {
        case .side:
            return CGPoint(x: size.width * 0.72, y: size.height * 0.34)
        case .top:
            return CGPoint(x: size.width * 0.60, y: size.height * 0.32)
        case .front:
            return CGPoint(x: size.width * 0.68, y: size.height * 0.36)
        }
    }

    private func jointValue(_ index: Int) -> Double {
        jointAngles.indices.contains(index) ? jointAngles[index] : 0.0
    }

    private func jointLabel(_ index: Int) -> String {
        "J\(index + 1)"
    }
}

private struct KuyuPreviewPoint3D: Sendable, Equatable {
    let x: Double
    let y: Double
    let z: Double
}
