import Foundation
import KuyuScenarios

struct ResolvedDescendingIntent {
    let vector: [Double]?
    let program: DescendingIntentProgram?
}

struct DescendingIntentPresentation {
    enum Severity: Equatable {
        case info
        case warning
    }

    let severity: Severity
    let message: String
    let metadata: [String: String]
}

struct DescendingIntentResolution {
    let intent: ResolvedDescendingIntent
    let presentation: DescendingIntentPresentation?
}

struct DescendingIntentResolver {
    func resolve(
        controller: ControllerSelection,
        channelIDs: [String],
        vectorText: String,
        programText: String
    ) throws -> DescendingIntentResolution {
        let rawVector = vectorText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawProgram = programText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInput = !rawVector.isEmpty || !rawProgram.isEmpty

        guard controller == .manasMLX else {
            if hasInput {
                return .init(
                    intent: ResolvedDescendingIntent(vector: nil, program: nil),
                    presentation: .init(
                        severity: .warning,
                        message: "Descending channels ignored for baseline controller",
                        metadata: ["from": "configured", "to": "ignored", "reason": "controllerDoesNotUseDescending"]
                    )
                )
            }
            return .init(intent: ResolvedDescendingIntent(vector: nil, program: nil), presentation: nil)
        }

        guard !channelIDs.isEmpty else {
            if hasInput {
                return .init(
                    intent: ResolvedDescendingIntent(vector: nil, program: nil),
                    presentation: .init(
                        severity: .warning,
                        message: "Descending channels ignored; descriptor has no control mapping",
                        metadata: ["from": "configured", "to": "count=0", "reason": "noDescriptorDescendingChannels"]
                    )
                )
            }
            return .init(intent: ResolvedDescendingIntent(vector: nil, program: nil), presentation: nil)
        }

        let parsedVector = try parseVector(vectorText)
        let parsedProgram = try parseProgram(programText)

        if parsedVector != nil, parsedProgram != nil {
            throw DescendingIntentParseError.conflictingInputs
        }

        if let parsedVector {
            if parsedVector.count == channelIDs.count {
                return .init(
                    intent: ResolvedDescendingIntent(vector: parsedVector, program: nil),
                    presentation: .init(
                        severity: .info,
                        message: "Descending channels applied",
                        metadata: ["channels": "\(channelIDs.count)", "values": formatVector(parsedVector)]
                    )
                )
            }

            let normalized = normalizedVector(parsedVector, expectedCount: channelIDs.count)
            return .init(
                intent: ResolvedDescendingIntent(vector: normalized, program: nil),
                presentation: .init(
                    severity: .warning,
                    message: "Descending channel count auto-corrected",
                    metadata: [
                        "from": "count=\(parsedVector.count)",
                        "to": "count=\(channelIDs.count)",
                        "reason": "descriptorCountMismatch",
                        "channels": channelIDs.joined(separator: ","),
                        "values": formatVector(normalized),
                    ]
                )
            )
        }

        if let parsedProgram {
            if parsedProgram.channelCount == channelIDs.count {
                return .init(
                    intent: ResolvedDescendingIntent(vector: nil, program: parsedProgram),
                    presentation: .init(
                        severity: .info,
                        message: "Descending program applied",
                        metadata: ["channels": "\(channelIDs.count)", "keyframes": "\(parsedProgram.keyframes.count)"]
                    )
                )
            }

            let normalizedProgram = try normalizedProgram(parsedProgram, expectedCount: channelIDs.count)
            return .init(
                intent: ResolvedDescendingIntent(vector: nil, program: normalizedProgram),
                presentation: .init(
                    severity: .warning,
                    message: "Descending program channel count auto-corrected",
                    metadata: [
                        "from": "count=\(parsedProgram.channelCount)",
                        "to": "count=\(channelIDs.count)",
                        "reason": "descriptorCountMismatch",
                        "channels": channelIDs.joined(separator: ","),
                        "keyframes": "\(normalizedProgram.keyframes.count)",
                    ]
                )
            )
        }

        if hasInput {
            return .init(
                intent: ResolvedDescendingIntent(vector: nil, program: nil),
                presentation: .init(
                    severity: .warning,
                    message: "Descending input ignored; nothing parsed",
                    metadata: ["reason": "invalidOrEmpty"]
                )
            )
        }

        return .init(
            intent: ResolvedDescendingIntent(vector: nil, program: nil),
            presentation: .init(
                severity: .info,
                message: "Descending channels omitted; using zero intent",
                metadata: ["channels": "\(channelIDs.count)", "reason": "emptyInput"]
            )
        )
    }

    private func parseVector(_ raw: String) throws -> [Double]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        var values: [Double] = []
        values.reserveCapacity(parts.count)

        for rawPart in parts {
            let token = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                throw DescendingIntentParseError.invalidToken(String(rawPart))
            }
            guard let value = Double(token) else {
                throw DescendingIntentParseError.invalidToken(token)
            }
            guard value.isFinite else {
                throw DescendingIntentParseError.nonFiniteValue(token)
            }
            values.append(value)
        }
        return values
    }

    private func normalizedVector(_ values: [Double], expectedCount: Int) -> [Double] {
        guard expectedCount > 0 else { return [] }
        if values.count >= expectedCount {
            return Array(values.prefix(expectedCount))
        }
        return values + Array(repeating: 0.0, count: expectedCount - values.count)
    }

    private func parseProgram(_ raw: String) throws -> DescendingIntentProgram? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let frameSpecs = trimmed.split(separator: ";", omittingEmptySubsequences: false)
        var keyframes: [DescendingIntentProgram.Keyframe] = []
        keyframes.reserveCapacity(frameSpecs.count)

        for rawFrame in frameSpecs {
            let frame = rawFrame.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !frame.isEmpty else {
                throw DescendingIntentParseError.invalidProgramFrame(String(rawFrame))
            }
            guard let separator = frame.firstIndex(of: ":") else {
                throw DescendingIntentParseError.invalidProgramFrame(frame)
            }
            let timeToken = String(frame[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valuesToken = String(frame[frame.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let time = Double(timeToken), time.isFinite else {
                throw DescendingIntentParseError.invalidProgramTime(timeToken)
            }
            guard let values = try parseVector(valuesToken) else {
                throw DescendingIntentParseError.invalidProgramFrame(frame)
            }
            do {
                keyframes.append(try DescendingIntentProgram.Keyframe(time: time, values: values))
            } catch {
                throw DescendingIntentParseError.invalidProgramFrame(frame)
            }
        }

        do {
            return try DescendingIntentProgram(keyframes: keyframes)
        } catch {
            throw DescendingIntentParseError.invalidProgram(raw)
        }
    }

    private func normalizedProgram(
        _ program: DescendingIntentProgram,
        expectedCount: Int
    ) throws -> DescendingIntentProgram {
        let normalizedKeyframes = try program.keyframes.map { frame in
            try DescendingIntentProgram.Keyframe(
                time: frame.time,
                values: normalizedVector(frame.values, expectedCount: expectedCount)
            )
        }
        return try DescendingIntentProgram(keyframes: normalizedKeyframes)
    }

    private func formatVector(_ values: [Double]) -> String {
        values.map { String(format: "%.4f", $0) }.joined(separator: ",")
    }
}

enum DescendingIntentParseError: LocalizedError {
    case invalidToken(String)
    case nonFiniteValue(String)
    case conflictingInputs
    case invalidProgram(String)
    case invalidProgramFrame(String)
    case invalidProgramTime(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken(let token):
            return "Invalid descending token '\(token)'. Use comma-separated finite numbers."
        case .nonFiniteValue(let token):
            return "Descending token '\(token)' is not finite."
        case .conflictingInputs:
            return "Specify either descending vector or descending program, not both."
        case .invalidProgram(let raw):
            return "Invalid descending program '\(raw)'. Use 'time:values;time:values'."
        case .invalidProgramFrame(let frame):
            return "Invalid descending program frame '\(frame)'. Use 'time:values'."
        case .invalidProgramTime(let token):
            return "Invalid descending program time '\(token)'."
        }
    }
}
