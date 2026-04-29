import MLX

public enum ManasMLXRandomSeed {
    public static func seed(_ value: UInt64) {
        MLXRandom.seed(value)
    }
}
