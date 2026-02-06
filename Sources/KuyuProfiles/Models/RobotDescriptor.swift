import Foundation

public struct RobotDescriptor: Sendable, Codable, Equatable {
    public enum MotorNerveType: String, Sendable, Codable {
        case direct
        case matrix
        case mixer
        case custom
    }

    public struct Robot: Sendable, Codable, Equatable {
        public let robotID: String
        public let name: String
        public let category: String
        public let manufacturer: String?
        public let tags: [String]?

        public init(
            robotID: String,
            name: String,
            category: String,
            manufacturer: String? = nil,
            tags: [String]? = nil
        ) {
            self.robotID = robotID
            self.name = name
            self.category = category
            self.manufacturer = manufacturer
            self.tags = tags
        }
    }

    public struct Vector3: Sendable, Codable, Equatable {
        public let x: Double
        public let y: Double
        public let z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let x = try container.decode(Double.self)
            let y = try container.decode(Double.self)
            let z = try container.decode(Double.self)
            if !container.isAtEnd {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Vector3 expects exactly 3 elements"
                )
            }
            self.x = x
            self.y = y
            self.z = z
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(x)
            try container.encode(y)
            try container.encode(z)
        }
    }

    public struct Range: Sendable, Codable, Equatable {
        public let min: Double
        public let max: Double

        public init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let min = try container.decode(Double.self)
            let max = try container.decode(Double.self)
            if !container.isAtEnd {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Range expects exactly 2 elements"
                )
            }
            self.min = min
            self.max = max
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(min)
            try container.encode(max)
        }
    }

    public struct Physics: Sendable, Codable, Equatable {
        public let model: PhysicsModel
        public let engine: EngineBinding

        public init(model: PhysicsModel, engine: EngineBinding) {
            self.model = model
            self.engine = engine
        }
    }

    public struct PhysicsModel: Sendable, Codable, Equatable {
        public let format: PhysicsModelFormat
        public let path: String

        public init(format: PhysicsModelFormat, path: String) {
            self.format = format
            self.path = path
        }
    }

    public struct EngineBinding: Sendable, Codable, Equatable {
        public let id: String
        public let parameters: [String: String]?

        public init(id: String, parameters: [String: String]? = nil) {
            self.id = id
            self.parameters = parameters
        }
    }

    public struct Render: Sendable, Codable, Equatable {
        public let assets: [RenderAsset]

        public init(assets: [RenderAsset]) {
            self.assets = assets
        }
    }

    public struct RenderAsset: Sendable, Codable, Equatable {
        public let id: String
        public let name: String
        public let format: RenderMeshFormat
        public let path: String
        public let scale: Vector3?

        public init(
            id: String,
            name: String,
            format: RenderMeshFormat,
            path: String,
            scale: Vector3? = nil
        ) {
            self.id = id
            self.name = name
            self.format = format
            self.path = path
            self.scale = scale
        }
    }

    public struct Signals: Sendable, Codable, Equatable {
        public let sensor: [SignalDefinition]
        public let actuator: [SignalDefinition]
        public let drive: [SignalDefinition]
        public let reflex: [SignalDefinition]
        public let motorNerve: [SignalDefinition]?

        public init(
            sensor: [SignalDefinition],
            actuator: [SignalDefinition],
            drive: [SignalDefinition],
            reflex: [SignalDefinition],
            motorNerve: [SignalDefinition]? = nil
        ) {
            self.sensor = sensor
            self.actuator = actuator
            self.drive = drive
            self.reflex = reflex
            self.motorNerve = motorNerve
        }
    }

    public struct SignalDefinition: Sendable, Codable, Equatable {
        public let id: String
        public let index: Int
        public let name: String
        public let units: String
        public let rateHz: Double?
        public let range: Range?
        public let group: String?

        public init(
            id: String,
            index: Int,
            name: String,
            units: String,
            rateHz: Double? = nil,
            range: Range? = nil,
            group: String? = nil
        ) {
            self.id = id
            self.index = index
            self.name = name
            self.units = units
            self.rateHz = rateHz
            self.range = range
            self.group = group
        }
    }

    public struct SensorNoise: Sendable, Codable, Equatable {
        public let bias: Double
        public let std: Double
        public let randomWalkStd: Double

        public init(bias: Double, std: Double, randomWalkStd: Double) {
            self.bias = bias
            self.std = std
            self.randomWalkStd = randomWalkStd
        }
    }

    public struct SensorDropout: Sendable, Codable, Equatable {
        public let prob: Double
        public let burstMs: Double

        public init(prob: Double, burstMs: Double) {
            self.prob = prob
            self.burstMs = burstMs
        }
    }

    public struct SensorSwapProfile: Sendable, Codable, Equatable {
        public let gainRange: Range
        public let biasRange: Range
        public let delayMsRange: Range

        public init(gainRange: Range, biasRange: Range, delayMsRange: Range) {
            self.gainRange = gainRange
            self.biasRange = biasRange
            self.delayMsRange = delayMsRange
        }
    }

    public struct SensorDefinition: Sendable, Codable, Equatable {
        public let id: String
        public let type: String
        public let channels: [String]
        public let rateHz: Double
        public let latencyMs: Double
        public let noise: SensorNoise?
        public let dropout: SensorDropout?
        public let swapProfile: SensorSwapProfile?

        public init(
            id: String,
            type: String,
            channels: [String],
            rateHz: Double,
            latencyMs: Double,
            noise: SensorNoise? = nil,
            dropout: SensorDropout? = nil,
            swapProfile: SensorSwapProfile? = nil
        ) {
            self.id = id
            self.type = type
            self.channels = channels
            self.rateHz = rateHz
            self.latencyMs = latencyMs
            self.noise = noise
            self.dropout = dropout
            self.swapProfile = swapProfile
        }
    }

    public struct ActuatorLimits: Sendable, Codable, Equatable {
        public let min: Double
        public let max: Double
        public let rateLimit: Double

        public init(min: Double, max: Double, rateLimit: Double) {
            self.min = min
            self.max = max
            self.rateLimit = rateLimit
        }
    }

    public struct ActuatorDynamics: Sendable, Codable, Equatable {
        public let timeConstant: Double
        public let deadzone: Double

        public init(timeConstant: Double, deadzone: Double) {
            self.timeConstant = timeConstant
            self.deadzone = deadzone
        }
    }

    public struct ActuatorSwapProfile: Sendable, Codable, Equatable {
        public let gainRange: Range
        public let maxRange: Range
        public let lagMsRange: Range

        public init(gainRange: Range, maxRange: Range, lagMsRange: Range) {
            self.gainRange = gainRange
            self.maxRange = maxRange
            self.lagMsRange = lagMsRange
        }
    }

    public struct ActuatorDefinition: Sendable, Codable, Equatable {
        public let id: String
        public let type: String
        public let channels: [String]
        public let limits: ActuatorLimits
        public let dynamics: ActuatorDynamics?
        public let swapProfile: ActuatorSwapProfile?

        public init(
            id: String,
            type: String,
            channels: [String],
            limits: ActuatorLimits,
            dynamics: ActuatorDynamics? = nil,
            swapProfile: ActuatorSwapProfile? = nil
        ) {
            self.id = id
            self.type = type
            self.channels = channels
            self.limits = limits
            self.dynamics = dynamics
            self.swapProfile = swapProfile
        }
    }

    public struct ControlConstraints: Sendable, Codable, Equatable {
        public let driveClamp: Range?
        public let reflexClamp: Range?

        public init(driveClamp: Range? = nil, reflexClamp: Range? = nil) {
            self.driveClamp = driveClamp
            self.reflexClamp = reflexClamp
        }
    }

    public struct Control: Sendable, Codable, Equatable {
        public let driveChannels: [String]
        public let reflexChannels: [String]
        public let constraints: ControlConstraints?

        public init(
            driveChannels: [String],
            reflexChannels: [String],
            constraints: ControlConstraints? = nil
        ) {
            self.driveChannels = driveChannels
            self.reflexChannels = reflexChannels
            self.constraints = constraints
        }
    }

    public struct MotorNerveMapping: Sendable, Codable, Equatable {
        public let matrix: [[Double]]?
        public let bias: [Double]?
        public let clip: Range?

        public init(matrix: [[Double]]? = nil, bias: [Double]? = nil, clip: Range? = nil) {
            self.matrix = matrix
            self.bias = bias
            self.clip = clip
        }
    }

    public struct MotorNerveStage: Sendable, Codable, Equatable {
        public let id: String
        public let type: MotorNerveType
        public let inputs: [String]
        public let outputs: [String]
        public let mapping: MotorNerveMapping?
        public let parameters: [String: String]?

        public init(
            id: String,
            type: MotorNerveType,
            inputs: [String],
            outputs: [String],
            mapping: MotorNerveMapping? = nil,
            parameters: [String: String]? = nil
        ) {
            self.id = id
            self.type = type
            self.inputs = inputs
            self.outputs = outputs
            self.mapping = mapping
            self.parameters = parameters
        }
    }

    public struct MotorNerveDescriptor: Sendable, Codable, Equatable {
        public let stages: [MotorNerveStage]

        public init(stages: [MotorNerveStage]) {
            self.stages = stages
        }
    }

    public let robot: Robot
    public let physics: Physics
    public let render: Render?
    public let signals: Signals
    public let sensors: [SensorDefinition]
    public let actuators: [ActuatorDefinition]
    public let control: Control
    public let motorNerve: MotorNerveDescriptor

    public init(
        robot: Robot,
        physics: Physics,
        render: Render? = nil,
        signals: Signals,
        sensors: [SensorDefinition],
        actuators: [ActuatorDefinition],
        control: Control,
        motorNerve: MotorNerveDescriptor
    ) {
        self.robot = robot
        self.physics = physics
        self.render = render
        self.signals = signals
        self.sensors = sensors
        self.actuators = actuators
        self.control = control
        self.motorNerve = motorNerve
    }
}
