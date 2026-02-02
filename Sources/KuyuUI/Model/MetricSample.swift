struct MetricSample: Identifiable, Hashable {
    let id: Double
    let time: Double
    let value: Double

    init(time: Double, value: Double) {
        self.time = time
        self.value = value
        self.id = time
    }
}
