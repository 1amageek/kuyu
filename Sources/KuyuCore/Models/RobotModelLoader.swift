import Foundation

public struct RobotModelLoader {
    public enum LoaderError: Error, Equatable {
        case descriptorNotFound(String)
        case descriptorReadFailed(String)
        case descriptorDecodeFailed
        case unsupportedPhysicsFormat
        case urdfParseFailed(String)
    }

    public init() {}

    public func loadDescriptor(path: String) throws -> LoadedRobotModelDescriptor {
        guard let url = resolvePath(path) else {
            throw LoaderError.descriptorNotFound(path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoaderError.descriptorReadFailed("\(error)")
        }

        do {
            let descriptor = try JSONDecoder().decode(RobotModelDescriptor.self, from: data)
            return LoadedRobotModelDescriptor(descriptor: descriptor, baseURL: url)
        } catch {
            throw LoaderError.descriptorDecodeFailed
        }
    }

    public func loadQuadrotorParameters(descriptor: LoadedRobotModelDescriptor) throws -> QuadrotorParameters {
        switch descriptor.descriptor.physicsFormat {
        case .urdf:
            let urdfURL = resolveRelativePath(
                descriptor.descriptor.physicsPath,
                baseURL: descriptor.baseURL
            )
            let inertial = try URDFInertialParser.parse(url: urdfURL)
            let base = QuadrotorParameters.baseline
            return try QuadrotorParameters(
                mass: inertial.mass,
                inertia: inertial.inertia,
                armLength: base.armLength,
                motorTimeConstant: base.motorTimeConstant,
                maxThrust: base.maxThrust,
                yawCoefficient: base.yawCoefficient,
                gravity: base.gravity,
                aerodynamics: base.aerodynamics
            )
        case .sdf:
            throw LoaderError.unsupportedPhysicsFormat
        }
    }

    public func loadRenderURL(descriptor: LoadedRobotModelDescriptor) -> URL {
        resolveRelativePath(descriptor.descriptor.renderPath, baseURL: descriptor.baseURL)
    }

    private func resolvePath(_ path: String) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var base = current
        for _ in 0..<4 {
            let candidate = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            base = base.deletingLastPathComponent()
        }

        return nil
    }

    private func resolveRelativePath(_ path: String, baseURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        let dir = baseURL.deletingLastPathComponent()
        let direct = dir.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        var base = dir
        for _ in 0..<4 {
            let candidate = base.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            base = base.deletingLastPathComponent()
        }

        return direct
    }
}

public struct LoadedRobotModelDescriptor: Sendable, Equatable {
    public let descriptor: RobotModelDescriptor
    public let baseURL: URL
}

private struct URDFInertial {
    let mass: Double
    let inertia: Axis3
}

private final class URDFInertialParser: NSObject, XMLParserDelegate {
    enum ParserError: Error, Equatable {
        case missingMass
        case missingInertia
        case invalidValue(String)
    }

    private var mass: Double?
    private var inertia: Axis3?

    static func parse(url: URL) throws -> URDFInertial {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ParserError.invalidValue("read-failed")
        }

        let parser = XMLParser(data: data)
        let delegate = URDFInertialParser()
        parser.delegate = delegate
        let success = parser.parse()
        if !success {
            throw ParserError.invalidValue("parse-failed")
        }

        guard let mass = delegate.mass else { throw ParserError.missingMass }
        guard let inertia = delegate.inertia else { throw ParserError.missingInertia }
        return URDFInertial(mass: mass, inertia: inertia)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "mass":
            if let value = attributeDict["value"], let parsed = Double(value) {
                mass = parsed
            }
        case "inertia":
            if let ixx = Double(attributeDict["ixx"] ?? ""),
               let iyy = Double(attributeDict["iyy"] ?? ""),
               let izz = Double(attributeDict["izz"] ?? "") {
                inertia = Axis3(x: ixx, y: iyy, z: izz)
            }
        default:
            break
        }
    }
}
