import SwiftData
import SwiftUI

struct QuickTaskSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var timerEngine: TimerEngine
    @Query(sort: [SortDescriptor(\WorkTask.updatedAt, order: .reverse)]) private var tasks: [WorkTask]
    @Query(sort: [SortDescriptor(\Project.createdAt)]) private var projects: [Project]

    @State private var searchText = ""
    @State private var selectedProjectID: UUID?
    @State private var didChooseDefaultProject = false

    let onSelect: (WorkTask) -> Void

    private let workflowService = TaskWorkflowService()

    private var activeProjects: [Project] {
        projects.filter { !$0.isArchived }
    }

    private var filteredTasks: [WorkTask] {
        workflowService.filterQuickTasks(tasks, query: searchText)
    }

    private var duplicateCandidates: [WorkTask] {
        workflowService.duplicateCandidates(
            for: searchText,
            tasks: tasks,
            selectedProjectID: selectedProjectID
        )
    }

    private var currentProjectTasks: [WorkTask] {
        guard let selectedProjectID else {
            return []
        }

        let duplicateIDs = Set(duplicateCandidates.map(\.id))
        return filteredTasks.filter { $0.project?.id == selectedProjectID && !duplicateIDs.contains($0.id) }
    }

    private var recentTasks: [WorkTask] {
        let excludedIDs = Set(currentProjectTasks.map(\.id) + duplicateCandidates.map(\.id))
        return filteredTasks.filter { !excludedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("加入并行任务")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button(duplicateCandidates.isEmpty ? "新建并开始" : "仍然新建", action: createTask)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("搜索任务，或输入后直接新建", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("所属项目", selection: $selectedProjectID) {
                Text("无项目").tag(Optional<UUID>.none)
                ForEach(activeProjects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .pickerStyle(.menu)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                if !duplicateCandidates.isEmpty {
                    sectionHeader("可能已存在 · 建议复用")
                    ForEach(duplicateCandidates.prefix(5)) { task in
                        taskRow(task)
                    }

                    Divider().padding(.vertical, 4)
                }

                if !currentProjectTasks.isEmpty {
                    sectionHeader("所选项目")
                    ForEach(currentProjectTasks) { task in
                        taskRow(task)
                    }

                    Divider().padding(.vertical, 4)
                }

                sectionHeader("最近任务")
                ForEach(recentTasks.prefix(10)) { task in
                    taskRow(task)
                }
            }
                .padding(8)
            }
            .frame(minWidth: 320, minHeight: 300)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if tasks.isEmpty {
                Text("还没有任务，输入名字后点击\u{201C}新建并开始\u{201D}即可。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .onAppear(perform: chooseDefaultProjectIfNeeded)
    }

    @ViewBuilder
    private func taskRow(_ task: WorkTask) -> some View {
        Button {
            DispatchQueue.main.async {
                onSelect(task)
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hexString: task.project?.colorHex ?? PaletteColor.sky.rawValue))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body.weight(.medium))

                    Text(task.project?.name ?? "未分配项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if timerEngine.isTaskRunning(task) {
                    StatusPill(status: .running)
                } else if timerEngine.isTaskPaused(task) {
                    StatusPill(status: .paused)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    private func createTask() {
        let task = timerEngine.createTask(
            named: searchText,
            project: activeProjects.first(where: { $0.id == selectedProjectID })
        )
        onSelect(task)
    }

    private func chooseDefaultProjectIfNeeded() {
        guard !didChooseDefaultProject else { return }
        didChooseDefaultProject = true

        if let primaryProjectID = timerEngine.primaryTask?.project?.id,
           activeProjects.contains(where: { $0.id == primaryProjectID }) {
            selectedProjectID = primaryProjectID
            return
        }

        selectedProjectID = tasks
            .first(where: { !$0.isArchived && $0.project?.isArchived == false })?
            .project?.id
    }
}
