import simd

public struct TorqueDisturbanceField: DisturbanceField {
    public var events: [TorqueDisturbanceEvent]
    public var store: WorldStore

    public init(events: [TorqueDisturbanceEvent], store: WorldStore) {
        self.events = events
        self.store = store
    }

    public mutating func update(time: WorldTime) throws {
        let now = time.time
        var torque = SIMD3<Double>(repeating: 0)
        for event in events where event.isActive(at: now) {
            torque += event.torqueSIMD
        }
        store.disturbances.torqueBody = torque
    }
}
