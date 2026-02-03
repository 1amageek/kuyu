public enum PhysicsModelFormat: String, Sendable, Codable, Equatable {
    case urdf
    case sdf
}

public enum RenderMeshFormat: String, Sendable, Codable, Equatable {
    case gltf
    case glb
    case obj
    case usdz
    case usdc
}

public enum PrintMeshFormat: String, Sendable, Codable, Equatable {
    case stl
    case threeMF = "3mf"
}

public struct RobotModelDescriptor: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Equatable {
        case empty(String)
        case extensionMismatch(String)
    }

    public let id: String
    public let name: String
    public let physicsFormat: PhysicsModelFormat
    public let physicsPath: String
    public let renderFormat: RenderMeshFormat
    public let renderPath: String
    public let printFormat: PrintMeshFormat?
    public let printPath: String?

    public init(
        id: String,
        name: String,
        physicsFormat: PhysicsModelFormat,
        physicsPath: String,
        renderFormat: RenderMeshFormat,
        renderPath: String,
        printFormat: PrintMeshFormat? = nil,
        printPath: String? = nil
    ) throws {
        guard !id.isEmpty else { throw ValidationError.empty("id") }
        guard !name.isEmpty else { throw ValidationError.empty("name") }
        guard !physicsPath.isEmpty else { throw ValidationError.empty("physicsPath") }
        guard !renderPath.isEmpty else { throw ValidationError.empty("renderPath") }

        if !Self.matchesExtension(path: physicsPath, format: physicsFormat) {
            throw ValidationError.extensionMismatch("physicsPath")
        }
        if !Self.matchesExtension(path: renderPath, format: renderFormat) {
            throw ValidationError.extensionMismatch("renderPath")
        }
        if let printFormat, let printPath {
            guard !printPath.isEmpty else { throw ValidationError.empty("printPath") }
            if !Self.matchesExtension(path: printPath, format: printFormat) {
                throw ValidationError.extensionMismatch("printPath")
            }
        }

        self.id = id
        self.name = name
        self.physicsFormat = physicsFormat
        self.physicsPath = physicsPath
        self.renderFormat = renderFormat
        self.renderPath = renderPath
        self.printFormat = printFormat
        self.printPath = printPath
    }

    private static func matchesExtension(path: String, format: PhysicsModelFormat) -> Bool {
        matches(path: path, extensions: [format.rawValue])
    }

    private static func matchesExtension(path: String, format: RenderMeshFormat) -> Bool {
        matches(path: path, extensions: [format.rawValue])
    }

    private static func matchesExtension(path: String, format: PrintMeshFormat) -> Bool {
        matches(path: path, extensions: [format.rawValue])
    }

    private static func matches(path: String, extensions: [String]) -> Bool {
        let lowercased = path.lowercased()
        return extensions.contains { lowercased.hasSuffix(".\($0)") }
    }
}
