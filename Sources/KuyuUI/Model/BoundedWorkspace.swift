import SwiftUI

public enum BoundedWorkspace: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case training
    case experimentDesign
    case reinforcementLearning
    case geneticLearning
    case hybridIntegration
    case environment
    case analysis
    case report
    case monitor
    case settings
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return "ダッシュボード"
        case .training: return "トレーニング"
        case .experimentDesign: return "実験設計"
        case .reinforcementLearning: return "強化学習"
        case .geneticLearning: return "遺伝的学習"
        case .hybridIntegration: return "ハイブリッド統合"
        case .environment: return "環境"
        case .analysis: return "分析"
        case .report: return "レポート"
        case .monitor: return "モニター"
        case .settings: return "設定"
        case .system: return "システム"
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .training: return "waveform.path.ecg"
        case .experimentDesign: return "doc.badge.gearshape"
        case .reinforcementLearning: return "flask"
        case .geneticLearning: return "point.3.connected.trianglepath.dotted"
        case .hybridIntegration: return "arrow.triangle.merge"
        case .environment: return "cube.transparent"
        case .analysis: return "tablecells"
        case .report: return "doc.richtext"
        case .monitor: return "chart.line.uptrend.xyaxis"
        case .settings: return "gearshape"
        case .system: return "desktopcomputer"
        }
    }

    var isTrainingWorkspace: Bool {
        switch self {
        case .training, .experimentDesign, .reinforcementLearning, .geneticLearning, .hybridIntegration, .environment:
            return true
        case .dashboard, .analysis, .report, .monitor, .settings, .system:
            return false
        }
    }
}
