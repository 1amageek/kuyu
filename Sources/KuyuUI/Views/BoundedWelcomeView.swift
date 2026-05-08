import AppKit
import KuyuTraining
import SwiftUI

struct BoundedWelcomeView: View {
    @Bindable var model: AppViewModel
    @State private var selectedTemplateID: String
    @State private var projectName: String
    @State private var parentDirectoryPath: String

    init(model: AppViewModel) {
        self.model = model
        let firstTemplate = model.projectTemplates.first
        _selectedTemplateID = State(initialValue: firstTemplate?.templateID ?? "")
        _projectName = State(initialValue: firstTemplate?.displayName ?? "Untitled")
        _parentDirectoryPath = State(initialValue: Self.defaultParentDirectory().path)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            detail
        }
        .navigationTitle("Bounded")
    }

    private var sidebar: some View {
        List(selection: $selectedTemplateID) {
            Section("テンプレート") {
                ForEach(model.projectTemplates, id: \.templateID) { template in
                    Label(template.displayName, systemImage: iconName(for: template))
                        .tag(template.templateID)
                }
            }

            if !model.recentProjectURLs.isEmpty {
                Section("最近使ったプロジェクト") {
                    ForEach(model.recentProjectURLs, id: \.self) { url in
                        Button {
                            model.openProject(at: url)
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc")
                        }
                    }
                }
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.xl) {
            header
            if let template = selectedTemplate {
                templateSummary(template)
                projectForm(template)
            } else {
                ContentUnavailableView("テンプレートがありません", systemImage: "doc.badge.plus")
            }
            Spacer(minLength: 0)
        }
        .padding(KuyuSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: KuyuSpacing.sm) {
            Text("新しい Kuyu プロジェクト")
                .font(.largeTitle.weight(.semibold))
            Text(".kuyu project package を作成し、テンプレートからすぐ学習を開始できる状態にします。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func templateSummary(_ template: LearningProjectTemplate) -> some View {
        GroupBox {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: KuyuSpacing.xl, verticalSpacing: KuyuSpacing.md) {
                GridRow {
                    Label(template.displayName, systemImage: iconName(for: template))
                        .font(.title3.weight(.semibold))
                    StatusPill(template.taskProfileID == nil ? "Design Only" : "Runnable", tone: template.taskProfileID == nil ? .warning : .success)
                }
                GridRow {
                    Text("Domain")
                        .foregroundStyle(.secondary)
                    Text(template.domain.rawValue)
                }
                GridRow {
                    Text("Task")
                        .foregroundStyle(.secondary)
                    Text(template.task)
                }
                GridRow {
                    Text("Strategy")
                        .foregroundStyle(.secondary)
                    Text(template.trainingStrategy.kind.rawValue)
                }
                GridRow {
                    Text("Observation")
                        .foregroundStyle(.secondary)
                    Text("\(template.observation.channelCount) channels")
                }
                GridRow {
                    Text("Action")
                        .foregroundStyle(.secondary)
                    Text("\(template.action.driveCount ?? template.action.actuatorCount ?? 0) drives")
                }
            }
            Text(template.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, KuyuSpacing.md)
        }
    }

    private func projectForm(_ template: LearningProjectTemplate) -> some View {
        Form {
            TextField("Project Name", text: $projectName)
            HStack {
                TextField("Location", text: $parentDirectoryPath)
                Button("Choose...") {
                    chooseParentDirectory()
                }
            }
            if let error = model.projectCreationError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            HStack {
                Button {
                    openExistingProject()
                } label: {
                    Label("Open Existing Project", systemImage: "folder")
                }
                Spacer()
                Button {
                    createProject(template)
                } label: {
                    Label(model.isCreatingProject ? "Creating..." : "Create Project", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isCreatingProject || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedTemplate: LearningProjectTemplate? {
        model.projectTemplates.first { $0.templateID == selectedTemplateID }
    }

    private func createProject(_ template: LearningProjectTemplate) {
        model.createProject(
            name: projectName,
            parentDirectory: URL(fileURLWithPath: parentDirectoryPath, isDirectory: true),
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
            parentDirectoryPath = url.path
        }
    }

    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.kuyuProject]
        if panel.runModal() == .OK, let url = panel.url {
            model.openProject(at: url)
        }
    }

    private func iconName(for template: LearningProjectTemplate) -> String {
        switch template.domain {
        case .aerialDrone:
            return "paperplane"
        case .groundRobot:
            return "car"
        case .manipulator:
            return "hand.raised"
        case .automotive:
            return "steeringwheel"
        }
    }

    private static func defaultParentDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
}
