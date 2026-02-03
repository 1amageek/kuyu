import SwiftUI

enum RobotPanelKind: String, Hashable, Sendable {
    case timeline
    case render
    case attitude
    case tilt
    case omega
    case speed
    case altitude
}

struct RobotPanelItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let kind: RobotPanelKind
    let span: Int
    let minHeight: CGFloat?

    init(
        kind: RobotPanelKind,
        span: Int = 1,
        minHeight: CGFloat? = nil
    ) {
        self.kind = kind
        self.span = span
        self.minHeight = minHeight
    }
}

struct RobotPanelRow: Hashable, Sendable {
    let items: [RobotPanelItem]
}

struct RobotProfile: Hashable, Sendable {
    let id: String
    let name: String
    let rows: [RobotPanelRow]

    static let quadrotor = RobotProfile(
        id: "quadrotor",
        name: "Quadrotor",
        rows: [
            RobotPanelRow(items: [
                RobotPanelItem(kind: .timeline, span: 2, minHeight: 70)
            ]),
            RobotPanelRow(items: [
                RobotPanelItem(kind: .render, minHeight: 220),
                RobotPanelItem(kind: .tilt, minHeight: 220)
            ]),
            RobotPanelRow(items: [
                RobotPanelItem(kind: .attitude, minHeight: 220),
                RobotPanelItem(kind: .omega, minHeight: 220)
            ])
        ]
    )

    static let generic = RobotProfile(
        id: "generic",
        name: "Generic",
        rows: [
            RobotPanelRow(items: [
                RobotPanelItem(kind: .timeline, span: 2, minHeight: 70)
            ]),
            RobotPanelRow(items: [
                RobotPanelItem(kind: .render, minHeight: 220),
                RobotPanelItem(kind: .speed, minHeight: 220)
            ]),
            RobotPanelRow(items: [
                RobotPanelItem(kind: .attitude, minHeight: 220),
                RobotPanelItem(kind: .altitude, minHeight: 220)
            ])
        ]
    )
}
