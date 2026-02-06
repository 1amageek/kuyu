public protocol FailurePolicy {
    mutating func update(log: WorldStepLog) -> FailureEvent?
}
