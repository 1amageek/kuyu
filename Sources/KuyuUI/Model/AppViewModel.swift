import Foundation
import Observation

/// Root view model that manages application mode and delegates to mode-specific view models
@Observable
@MainActor
public final class AppViewModel {
    /// Application operating mode
    public enum Mode: String, CaseIterable, Sendable {
        case simulation
        case training

        public var displayName: String {
            switch self {
            case .simulation: return "Simulation"
            case .training: return "Training"
            }
        }
    }

    // MARK: - Mode Management

    /// Current application mode
    public var currentMode: Mode = .simulation

    // MARK: - Mode-Specific ViewModels

    /// Simulation mode state
    public let simulationViewModel: SimulationViewModel

    // MARK: - Shared Resources

    /// Shared log store across all modes
    public let logStore: UILogStore

    // MARK: - Initialization

    public init(logStore: UILogStore) {
        self.logStore = logStore
        self.simulationViewModel = SimulationViewModel(logStore: logStore)
    }
}
