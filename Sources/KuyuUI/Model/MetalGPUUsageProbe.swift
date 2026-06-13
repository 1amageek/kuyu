#if canImport(Metal)
import Metal
#endif

@MainActor
enum MetalGPUUsageProbe {
    #if canImport(Metal)
    private static let device = MTLCreateSystemDefaultDevice()

    static var currentAllocatedBytes: UInt64? {
        guard let device else { return nil }
        return UInt64(device.currentAllocatedSize)
    }

    static var recommendedMaxWorkingSetBytes: UInt64? {
        guard let device else { return nil }
        return device.recommendedMaxWorkingSetSize
    }
    #else
    static var currentAllocatedBytes: UInt64? { nil }
    static var recommendedMaxWorkingSetBytes: UInt64? { nil }
    #endif
}
