struct FNV1a64 {
    private static let offset: UInt64 = 0xcbf29ce484222325
    private static let prime: UInt64 = 0x00000100000001b3

    public static func hash(data: [UInt8]) -> UInt64 {
        var value = offset
        for byte in data {
            value ^= UInt64(byte)
            value &*= prime
        }
        return value
    }
}
