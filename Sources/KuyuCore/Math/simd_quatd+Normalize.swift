import simd

public extension simd_quatd {
    var normalizedQuat: simd_quatd {
        simd_normalize(self)
    }
}
