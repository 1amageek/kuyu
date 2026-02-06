import SwiftUI

public struct AttitudeIndicatorView: View {
    let roll: Double
    let pitch: Double
    let yaw: Double
    
    public init(roll: Double, pitch: Double, yaw: Double) {
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
    }

    public var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let frame = CGSize(width: size, height: size)
                ZStack {
                    Circle()
                        .fill(KuyuUITheme.panelBackground)
                        .overlay(
                            Circle()
                                .stroke(KuyuUITheme.panelHighlight, lineWidth: 2)
                        )

                    Canvas { context, canvasSize in
                        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                        let pitchScale = canvasSize.height * 0.22
                        let pitchOffset = CGFloat(clamp(pitch, min: -Double.pi / 3, max: Double.pi / 3) / (Double.pi / 3)) * pitchScale

                        context.translateBy(x: center.x, y: center.y + pitchOffset)
                        context.rotate(by: Angle(radians: roll))

                        let sky = CGRect(x: -canvasSize.width, y: -canvasSize.height * 2, width: canvasSize.width * 2, height: canvasSize.height * 2)
                        let ground = CGRect(x: -canvasSize.width, y: 0, width: canvasSize.width * 2, height: canvasSize.height * 2)

                        context.fill(Path(sky), with: .color(Color(red: 0.25, green: 0.38, blue: 0.55).opacity(0.85)))
                        context.fill(Path(ground), with: .color(Color(red: 0.32, green: 0.22, blue: 0.17).opacity(0.85)))

                        var horizon = Path()
                        horizon.move(to: CGPoint(x: -canvasSize.width, y: 0))
                        horizon.addLine(to: CGPoint(x: canvasSize.width, y: 0))
                        context.stroke(horizon, with: .color(.white.opacity(0.8)), lineWidth: 2)

                        var ticks = Path()
                        for step in stride(from: -2, through: 2, by: 1) {
                            let y = CGFloat(step) * canvasSize.height * 0.12
                            ticks.move(to: CGPoint(x: -canvasSize.width * 0.25, y: y))
                            ticks.addLine(to: CGPoint(x: canvasSize.width * 0.25, y: y))
                        }
                        context.stroke(ticks, with: .color(.white.opacity(0.35)), lineWidth: 1)
                    }
                    .clipShape(Circle())

                    Circle()
                        .fill(KuyuUITheme.accent)
                        .frame(width: 6, height: 6)
                }
                .frame(width: frame.width, height: frame.height)
            }
            .frame(height: 180)

            HStack(spacing: 12) {
                AttitudeStatValueView(label: "Roll", value: roll * 180.0 / Double.pi, unit: "deg")
                AttitudeStatValueView(label: "Pitch", value: pitch * 180.0 / Double.pi, unit: "deg")
                AttitudeStatValueView(label: "Yaw", value: yaw * 180.0 / Double.pi, unit: "deg")
            }
        }
        .padding(12)
        .background(KuyuUITheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(KuyuUITheme.panelHighlight, lineWidth: 1)
        )
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

#Preview {
    AttitudeIndicatorView(roll: 0.3, pitch: -0.2, yaw: 1.2)
        .padding()
        .background(KuyuUITheme.background)
}
