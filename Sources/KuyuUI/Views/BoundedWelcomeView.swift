import AppKit
import KuyuTraining
import SwiftUI

public struct BoundedWelcomeWindowContentView: View {
    @Bindable var model: AppViewModel

    public init(model: AppViewModel) {
        self.model = model
    }

    public var body: some View {
        BoundedWelcomeView(model: model)
            .frame(minWidth: 920, minHeight: 600)
    }
}

struct BoundedWelcomeView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppViewModel
    @State private var step: BoundedWelcomeStep = .start
    @State private var selectedDomain: AutonomousOperationDomain = .aerialDrone
    @State private var selectedTemplateID: String?
    @State private var projectName: String
    @State private var parentDirectoryPath: String
    @State private var parentDirectoryURL: URL?
    @State private var projectLocationError: String?

    init(model: AppViewModel) {
        self.model = model
        let firstTemplate = model.projectTemplates.first { $0.domain == .aerialDrone } ?? model.projectTemplates.first
        let defaultDirectory = Self.defaultParentDirectory()
        _selectedTemplateID = State(initialValue: firstTemplate?.templateID)
        _projectName = State(initialValue: firstTemplate?.displayName ?? "Untitled")
        _parentDirectoryPath = State(initialValue: defaultDirectory?.path ?? "")
        _parentDirectoryURL = State(initialValue: defaultDirectory)
        _projectLocationError = State(initialValue: defaultDirectory == nil ? "Default project location is unavailable. Choose a writable folder before creating the project." : nil)
    }

    var body: some View {
        Group {
            switch step {
            case .start:
                startView
            case .chooseTemplate:
                chooseTemplateView
            case .configureProject:
                configureProjectView
            }
        }
        .containerBackground(.thinMaterial, for: .window)
        .onChange(of: selectedDomain) { _, domain in
            selectFirstTemplate(in: domain)
        }
        .onChange(of: model.currentProject?.package.manifest.projectID) { _, projectID in
            if projectID != nil {
                openWindow(id: BoundedWindowID.main.rawValue)
                NSApp.activate(ignoringOtherApps: true)
                dismissWindow(id: BoundedWindowID.welcome.rawValue)
            }
        }
        .onOpenURL { url in
            model.openURL(url)
        }
        .alert(
            "Operation Failed",
            isPresented: Binding(
                get: { model.projectCreationError != nil },
                set: { if !$0 { model.projectCreationError = nil } }
            ),
            presenting: model.projectCreationError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
    }

    // MARK: - Start

    private var startView: some View {
        HStack(spacing: 0) {
            startLeftSection
                .frame(width: 440)
            Divider()
            startRightSection
                .frame(maxWidth: .infinity)
        }
    }

    private var startLeftSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroHeader
                .padding(.top, 56)
                .padding(.horizontal, 36)
                .padding(.bottom, 28)

            VStack(spacing: 4) {
                WelcomeActionButton(
                    title: "Create New Project…",
                    subtitle: "Create a new Bounded project from a template.",
                    systemImage: "plus.square.dashed"
                ) {
                    step = .chooseTemplate
                }
                WelcomeActionButton(
                    title: "Clone Git Repository…",
                    subtitle: "Fetch a project from a remote repository.",
                    systemImage: "arrow.triangle.branch",
                    isEnabled: false
                ) {}
                WelcomeActionButton(
                    title: "Open Existing Project…",
                    subtitle: "Open an existing .kuyu project package.",
                    systemImage: "folder"
                ) {
                    openExistingProject()
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "b.square.fill")
                .font(.system(size: 96, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome to Bounded")
                    .font(.system(size: 28, weight: .semibold))
                Text(versionString)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startRightSection: some View {
        VStack(spacing: 0) {
            if model.recentProjectURLs.isEmpty {
                ContentUnavailableView {
                    Label("No Recent Projects", systemImage: "clock")
                } description: {
                    Text("Created and opened projects will appear here.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(model.recentProjectURLs, id: \.self) { url in
                            RecentProjectRow(url: url) {
                                model.openProject(at: url)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        }
                    } header: {
                        Text("Recent Projects")
                            .font(.headline)
                            .padding(.top, 8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Choose Template

    private var chooseTemplateView: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "Choose a project template",
                subtitle: "Select a platform, then choose a runnable starter curriculum or a design-only template."
            )

            VStack(spacing: 16) {
                Picker("Platform", selection: $selectedDomain) {
                    ForEach(AutonomousOperationDomain.allCases, id: \.self) { domain in
                        Text(domainTitle(domain)).tag(domain)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)

                if filteredTemplates.isEmpty {
                    ContentUnavailableView {
                        Label("No Templates Available", systemImage: "square.grid.2x2")
                    } description: {
                        Text("This platform has no project templates installed.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: templateGridColumns, spacing: 16) {
                            ForEach(filteredTemplates, id: \.templateID) { template in
                                TemplateCard(
                                    template: template,
                                    isSelected: selectedTemplateID == template.templateID,
                                    iconName: iconName(for: template),
                                    domainTitle: domainTitle(template.domain)
                                ) {
                                    selectedTemplateID = template.templateID
                                }
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 32)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 8)

            actionBar(
                primaryTitle: "Next",
                primaryEnabled: selectedTemplate != nil,
                primaryAction: {
                    if let template = selectedTemplate {
                        projectName = template.displayName
                    }
                    step = .configureProject
                }
            )
        }
    }

    // MARK: - Configure Project

    private var configureProjectView: some View {
        VStack(spacing: 0) {
            stepHeader(
                title: "Choose options for your new project",
                subtitle: "Set the project name and location for the .kuyu package."
            )

            HStack(alignment: .top, spacing: 24) {
                if let template = selectedTemplate {
                    TemplateSummaryView(
                        template: template,
                        iconName: iconName(for: template),
                        domainTitle: domainTitle(template.domain)
                    )
                    .frame(width: 320)
                }

                Form {
                    Section {
                        TextField("Project Name", text: $projectName)
                        HStack {
                            TextField("Location", text: parentDirectoryPathBinding)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Choose…") {
                                chooseParentDirectory()
                            }
                        }
                        if let projectLocationError {
                            Label(projectLocationError, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxHeight: .infinity, alignment: .top)

            actionBar(
                primaryTitle: model.isCreatingProject ? "Creating…" : "Create",
                primaryEnabled: !model.isCreatingProject &&
                    !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !parentDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    selectedTemplate != nil,
                primaryAction: {
                    if let template = selectedTemplate {
                        createProject(template)
                    }
                }
            )
        }
    }

    // MARK: - Shared Components

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }

    private func actionBar(
        primaryTitle: String,
        primaryEnabled: Bool,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button("Cancel") {
                    step = .start
                }
                .keyboardShortcut(.cancelAction)
                .disabled(model.isCreatingProject)
                Spacer()
                Button("Previous") {
                    goBack()
                }
                .disabled(step == .chooseTemplate || model.isCreatingProject)
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!primaryEnabled)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    // MARK: - Helpers

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let short, let build {
            return "Version \(short) (\(build))"
        }
        return "Learnable CNS Robotics Studio"
    }

    private var filteredTemplates: [LearningProjectTemplate] {
        model.projectTemplates.filter { $0.domain == selectedDomain }
    }

    private var selectedTemplate: LearningProjectTemplate? {
        guard let selectedTemplateID else {
            return nil
        }
        return model.projectTemplates.first { $0.templateID == selectedTemplateID }
    }

    private var templateGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16, alignment: .top)]
    }

    private func createProject(_ template: LearningProjectTemplate) {
        let parentDirectory = parentDirectoryURL?.path == parentDirectoryPath
            ? parentDirectoryURL
            : URL(fileURLWithPath: parentDirectoryPath, isDirectory: true)
        model.createProject(
            name: projectName,
            parentDirectory: parentDirectory ?? URL(fileURLWithPath: parentDirectoryPath, isDirectory: true),
            template: template
        )
    }

    private func chooseParentDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            parentDirectoryURL = url
            parentDirectoryPath = url.path
            projectLocationError = nil
        }
    }

    private var parentDirectoryPathBinding: Binding<String> {
        Binding {
            parentDirectoryPath
        } set: { value in
            parentDirectoryPath = value
            if parentDirectoryURL?.path != value {
                parentDirectoryURL = nil
            }
        }
    }

    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.kuyuProject]
        if panel.runModal() == .OK, let url = panel.url {
            model.openProject(at: url)
        }
    }

    private func selectFirstTemplate(in domain: AutonomousOperationDomain) {
        guard let template = model.projectTemplates.first(where: { $0.domain == domain }) else {
            selectedTemplateID = nil
            return
        }
        selectedTemplateID = template.templateID
        projectName = template.displayName
    }

    private func goBack() {
        switch step {
        case .start:
            break
        case .chooseTemplate:
            step = .start
        case .configureProject:
            step = .chooseTemplate
        }
    }

    private func iconName(for template: LearningProjectTemplate) -> String {
        domainIcon(template.domain)
    }

    private func domainIcon(_ domain: AutonomousOperationDomain) -> String {
        switch domain {
        case .aerialDrone:
            return "paperplane.fill"
        case .groundRobot:
            return "car.fill"
        case .manipulator:
            return "hand.raised.fill"
        case .automotive:
            return "steeringwheel"
        }
    }

    private func domainTitle(_ domain: AutonomousOperationDomain) -> String {
        switch domain {
        case .aerialDrone:
            return "Drone"
        case .groundRobot:
            return "Robot"
        case .manipulator:
            return "Manipulator"
        case .automotive:
            return "Automotive"
        }
    }

    private static func defaultParentDirectory() -> URL? {
        let fileManager = FileManager.default
        let developerDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer", isDirectory: true)
            .appendingPathComponent("Bounded", isDirectory: true)
        do {
            try fileManager.createDirectory(at: developerDirectory, withIntermediateDirectories: true)
            return developerDirectory
        } catch {
            guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return nil
            }
            let fallbackDirectory = supportDirectory
                .appendingPathComponent("Bounded", isDirectory: true)
                .appendingPathComponent("Projects", isDirectory: true)
            do {
                try fileManager.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
                return fallbackDirectory
            } catch {
                return nil
            }
        }
    }
}

// MARK: - Action Button

private struct WelcomeActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isEnabled ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && isEnabled ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Recent Project Row

private struct RecentProjectRow: View {
    let url: URL
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: LearningProjectTemplate
    let isSelected: Bool
    let iconName: String
    let domainTitle: String
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .frame(width: 36, height: 36)
                    Spacer()
                    runnabilityBadge
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.displayName)
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(domainTitle)
                        Text("·")
                        Text(template.trainingStrategy.kind.rawValue)
                    }
                    Text(stageSummary)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var runnabilityBadge: some View {
        let isRunnable = template.isRunnableStarter
        return Text(isRunnable ? "Ready Now" : "Design Only")
            .font(.caption2.weight(.medium))
            .foregroundStyle(isRunnable ? Color.green : Color.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((isRunnable ? Color.green : Color.orange).opacity(0.12))
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(borderColor, lineWidth: borderWidth)
    }

    private var borderColor: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.secondary.opacity(0.45)
        }
        return Color.secondary.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 1
    }

    private var stageSummary: String {
        let runnableCount = template.curriculum.trainingStages.filter { $0.taskProfileID != nil }.count
        return "\(template.curriculum.trainingStages.count)-stage curriculum · \(runnableCount) ready now"
    }
}

// MARK: - Template Summary

private struct TemplateSummaryView: View {
    let template: LearningProjectTemplate
    let iconName: String
    let domainTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.displayName)
                        .font(.headline)
                    Text(domainTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(template.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Curriculum", template.task)
                summaryRow("Stages", "\(template.curriculum.trainingStages.count)")
                summaryRow("Ready Now", "\(template.curriculum.trainingStages.filter { $0.taskProfileID != nil }.count)")
                summaryRow("Observation", "\(template.observation.channelCount) channels")
                summaryRow("Action", "\(template.action.driveCount ?? template.action.actuatorCount ?? 0) drives")
                summaryRow("Strategy", template.trainingStrategy.kind.rawValue)
                summaryRow(
                    "Status",
                    template.isRunnableStarter ? "Starter project" : "Design only"
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Training Stages")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(template.curriculum.trainingStages.prefix(5), id: \.stageID) { stage in
                    HStack(spacing: 8) {
                        Image(systemName: stage.taskProfileID == nil ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(stage.taskProfileID == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.displayName)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text("\(stage.executionMode.rawValue) · \(stageStatusText(stage))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private func stageStatusText(_ stage: LearningProjectTrainingStage) -> String {
        stage.taskProfileID == nil ? "planned contract" : "ready now"
    }
}

private enum BoundedWelcomeStep: Sendable {
    case start
    case chooseTemplate
    case configureProject
}
