import simd
import KuyuCore

public struct TorqueDisturbanceField: DisturbanceField {
    public var events: [TorqueDisturbanceEvent]
    public var hfEvents: [HFStressEvent]
    public var store: ReferenceQuadrotorWorldStore

    public init(events: [TorqueDisturbanceEvent], hfEvents: [HFStressEvent], store: ReferenceQuadrotorWorldStore) {
        self.events = events
        self.hfEvents = hfEvents
        self.store = store
    }

    public mutating func update(time: WorldTime) throws {
        let now = time.time
        var torque = SIMD3<Double>(repeating: 0)
        for event in events where event.isActive(at: now) {
            torque += event.torqueSIMD
        }
        for event in hfEvents where isActive(event, now: now) {
            torque += hfTorque(for: event, time: now)
        }
        store.disturbances.torqueBody = torque
    }

    public func snapshot() -> DisturbanceSnapshot {
        DisturbanceSnapshot(
            forceWorld: store.disturbances.forceAxis3(),
            torqueBody: store.disturbances.torqueAxis3()
        )
    }

    private func isActive(_ event: HFStressEvent, now: Double) -> Bool {
        now >= event.startTime && now <= (event.startTime + event.duration)
    }

    private func hfTorque(for event: HFStressEvent, time: Double) -> SIMD3<Double> {
        switch event.kind {
        case .impulse:
            return SIMD3<Double>(event.magnitude, 0, 0)
        case .vibration:
            let frequency = 120.0
            let phase = 2.0 * Double.pi * frequency * time
            return SIMD3<Double>(sin(phase) * event.magnitude, 0, 0)
        default:
            return SIMD3<Double>(repeating: 0)
        }
    }
}
