import SwiftData
import SwiftUI

private enum SidebarSection: String, CaseIterable, Hashable, Identifiable {
    case today
    case tasks
    case projects
    case tags
    case records

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .tasks: "所有任务"
        case .projects: "项目"
        case .tags: "标签"
        case .records: "记录"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "clock.badge.checkmark"
        case .tasks: "checklist"
        case .projects: "square.grid.2x2"
        case .tags: "tag"
        case .records: "list.bullet.rectangle.portrait"
        }
    }
}

struct MainWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var timerEngine: TimerEngine
    @EnvironmentObject private var mainWindowRouter: MainWindowRouter

    @Query(sort: [SortDescriptor(\WorkTask.updatedAt, order: .reverse)]) private var tasks: [WorkTask]
    @Query(sort: [SortDescriptor(\Project.createdAt)]) private var projects: [Project]
    @Query(sort: [SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query(sort: [SortDescriptor(\TimeEntry.startAt, order: .reverse)]) private var entries: [TimeEntry]

    @State private var selectedSection: SidebarSection? = .today
    @State private var searchText = ""
    @State private var selectedTaskID: UUID?
    @State private var selectedProjectID: UUID?
    @State private var selectedTagID: UUID?
    @State private var selectedEntryID: UUID?
    @State private var recordFilterDate = Date()
    @State private var recordProjectID: UUID?
    @State private var recordTagID: UUID?
    @State private var recordTaskID: UUID?

    private var todaySummaries: [TaskSummary] {
        timerEngine.aggregationService.groupedDurations(on: timerEngine.now, entries: entries, now: timerEngine.now)
            .sorted { a, b in
                let aOrder = taskSortOrder(a.task)
                let bOrder = taskSortOrder(b.task)
                if aOrder != bOrder { return aOrder < bOrder }
                return a.duration > b.duration
            }
    }

    /// Running = 0, Paused = 1, Stopped = 2 — for sorting active tasks first.
    private func taskSortOrder(_ task: WorkTask) -> Int {
        if timerEngine.isTaskRunning(task) { return 0 }
        if timerEngine.isTaskPaused(task) { return 1 }
        return 2
    }

    private var activeSection: SidebarSection {
        selectedSection ?? .today
    }

    private var todayEntries: [TimeEntry] {
        let interval = timerEngine.aggregationService.dayInterval(for: timerEngine.now)
        return entries.filter {
            timerEngine.aggregationService.overlapDuration(of: $0, within: interval, now: timerEngine.now) > 0
        }
    }

    private var filteredTasks: [WorkTask] {
        applySearch(to: tasks) { $0.title }
    }

    private var filteredProjects: [Project] {
        applySearch(to: projects) { $0.name }
    }

    private var filteredTags: [Tag] {
        applySearch(to: tags) { $0.name }
    }

    private var filteredEntries: [TimeEntry] {
        let interval = timerEngine.aggregationService.dayInterval(for: recordFilterDate)

        return entries.filter { entry in
            guard timerEngine.aggregationService.overlapDuration(of: entry, within: interval, now: timerEngine.now) > 0 else {
                return false
            }

            if let recordProjectID, entry.task?.project?.id != recordProjectID {
                return false
            }

            if let recordTagID, !(entry.task?.tags.contains(where: { $0.id == recordTagID }) ?? false) {
                return false
            }

            if let recordTaskID, entry.task?.id != recordTaskID {
                return false
            }

            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return true
            }

            return entry.task?.title.localizedCaseInsensitiveContains(trimmed) ?? false
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(Optional(section))
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 220)
        } content: {
            contentColumn
                .navigationTitle(activeSection.title)
        } detail: {
            detailColumn
        }
        .background(.regularMaterial)
        .toolbar {
            toolbarContent
        }
        .onChange(of: mainWindowRouter.destination, initial: true) { _, destination in
            apply(destination)
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch activeSection {
        case .today:
            todayContent
        case .tasks:
            searchableList(title: "搜索任务", text: $searchText) {
                List(filteredTasks, id: \.id, selection: $selectedTaskID) { task in
                    TaskRow(task: task, timerEngine: timerEngine)
                        .tag(task.id)
                }
            }
        case .projects:
            searchableList(title: "搜索项目", text: $searchText) {
                List(filteredProjects, id: \.id, selection: $selectedProjectID) { project in
                    ProjectRow(project: project, taskCount: tasks.filter { $0.project?.id == project.id }.count)
                        .tag(project.id)
                }
            }
        case .tags:
            searchableList(title: "搜索标签", text: $searchText) {
                List(filteredTags, id: \.id, selection: $selectedTagID) { tag in
                    TagRow(tag: tag, taskCount: tasks.filter { task in task.tags.contains(where: { $0.id == tag.id }) }.count)
                        .tag(tag.id)
                }
            }
        case .records:
            recordsContent
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch activeSection {
        case .today:
            if let selectedTask = tasks.first(where: { $0.id == selectedTaskID }) {
                TaskInspector(
                    task: selectedTask,
                    entries: entries,
                    projects: projects,
                    tags: tags,
                    timerEngine: timerEngine,
                    modelContext: modelContext,
                    onDelete: { deleteTask(selectedTask) }
                )
            } else {
                TodayOverview(
                    summaries: todaySummaries,
                    entries: todayEntries,
                    timerEngine: timerEngine
                )
            }
        case .tasks:
            if let selectedTask = tasks.first(where: { $0.id == selectedTaskID }) {
                TaskInspector(
                    task: selectedTask,
                    entries: entries,
                    projects: projects,
                    tags: tags,
                    timerEngine: timerEngine,
                    modelContext: modelContext,
                    onDelete: { deleteTask(selectedTask) }
                )
            } else {
                EmptyStateView(
                    title: "选择一个任务",
                    message: "在左侧选中任务后，这里会展示项目、标签、备注和最近记录。",
                    systemImage: "checklist"
                )
            }
        case .projects:
            if let selectedProject = projects.first(where: { $0.id == selectedProjectID }) {
                ProjectInspector(project: selectedProject, tasks: tasks, modelContext: modelContext)
            } else {
                EmptyStateView(
                    title: "选择一个项目",
                    message: "项目详情会展示颜色、任务和归档状态。",
                    systemImage: "square.grid.2x2"
                )
            }
        case .tags:
            if let selectedTag = tags.first(where: { $0.id == selectedTagID }) {
                TagInspector(tag: selectedTag, tasks: tasks, modelContext: modelContext)
            } else {
                EmptyStateView(
                    title: "选择一个标签",
                    message: "标签可以帮助你从多个维度整理任务和工时。",
                    systemImage: "tag"
                )
            }
        case .records:
            if let selectedEntry = entries.first(where: { $0.id == selectedEntryID }) {
                TimeEntryInspector(
                    entry: selectedEntry,
                    tasks: tasks,
                    timerEngine: timerEngine,
                    modelContext: modelContext,
                    onDelete: { deleteEntry(selectedEntry) }
                )
            } else {
                EmptyStateView(
                    title: "选择一条记录",
                    message: "在这里可以修正开始结束时间，或者切换记录归属的任务。",
                    systemImage: "list.bullet.rectangle.portrait"
                )
            }
        }
    }

    private var todayContent: some View {
        List(selection: $selectedTaskID) {
            Section("今日任务") {
                ForEach(todaySummaries) { summary in
                    Button {
                        selectedTaskID = summary.task.id
                    } label: {
                        HStack {
                            TaskRow(task: summary.task, timerEngine: timerEngine)
                            Spacer()
                            Text(DurationTextFormatter.compact(summary.duration))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(summary.task.id)
                }
            }

            Section("最近记录") {
                ForEach(todayEntries.prefix(8), id: \.id) { entry in
                    Button {
                        selectedTaskID = entry.task?.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.task?.title ?? "未分配任务")
                                .font(.body.weight(.medium))
                            Text(formattedTimeRange(start: entry.startAt, end: entry.endAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recordsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DatePicker("日期", selection: $recordFilterDate, displayedComponents: .date)
                    .datePickerStyle(.compact)

                Picker("项目", selection: $recordProjectID) {
                    Text("全部项目").tag(Optional<UUID>.none)
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }

                Picker("标签", selection: $recordTagID) {
                    Text("全部标签").tag(Optional<UUID>.none)
                    ForEach(tags) { tag in
                        Text(tag.name).tag(Optional(tag.id))
                    }
                }

                Picker("任务", selection: $recordTaskID) {
                    Text("全部任务").tag(Optional<UUID>.none)
                    ForEach(tasks) { task in
                        Text(task.title).tag(Optional(task.id))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)

            searchableList(title: "搜索记录", text: $searchText) {
                List(filteredEntries, id: \.id, selection: $selectedEntryID) { entry in
                    TimeEntryRow(entry: entry)
                        .tag(entry.id)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            switch activeSection {
            case .today, .tasks:
                Button {
                    let task = WorkTask(title: "新任务", updatedAt: Date())
                    modelContext.insert(task)
                    persist()
                    selectedSection = .tasks
                    selectedTaskID = task.id
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            case .projects:
                Button {
                    let project = Project()
                    modelContext.insert(project)
                    persist()
                    selectedProjectID = project.id
                } label: {
                    Label("新建项目", systemImage: "plus")
                }
            case .tags:
                Button {
                    let tag = Tag()
                    modelContext.insert(tag)
                    persist()
                    selectedTagID = tag.id
                } label: {
                    Label("新建标签", systemImage: "plus")
                }
            case .records:
                Button {
                    let targetTask = tasks.first ?? timerEngine.createTask(named: "补录任务")
                    let endDate = Date()
                    let startDate = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -1, to: endDate) ?? endDate
                    let entry = TimeEntry(task: targetTask, startAt: startDate, endAt: endDate, source: .manual, createdAt: Date())
                    modelContext.insert(entry)
                    persist()
                    selectedEntryID = entry.id
                } label: {
                    Label("新增记录", systemImage: "plus")
                }
            }
        }
    }

    private func apply(_ destination: MainWindowDestination) {
        switch destination {
        case .today:
            selectedSection = .today
        case .tasks(let taskID):
            selectedSection = .tasks
            selectedTaskID = taskID
        case .projects(let projectID):
            selectedSection = .projects
            selectedProjectID = projectID
        case .tags(let tagID):
            selectedSection = .tags
            selectedTagID = tagID
        case .records(let entryID):
            selectedSection = .records
            selectedEntryID = entryID
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save changes: \(error)")
        }
    }

    private func deleteTask(_ task: WorkTask) {
        let taskID = task.id

        // Only stop this specific task, not the whole workbench
        if timerEngine.isTaskRunning(task) || timerEngine.isTaskPaused(task) {
            timerEngine.stop(task: task)
        }

        if selectedTaskID == taskID {
            selectedTaskID = nil
        }

        DispatchQueue.main.async {
            let relatedEntries = entries.filter { $0.task?.id == taskID }
            relatedEntries.forEach(modelContext.delete)

            if let currentTask = tasks.first(where: { $0.id == taskID }) {
                modelContext.delete(currentTask)
            }

            persist()
        }
    }

    private func deleteEntry(_ entry: TimeEntry) {
        let entryID = entry.id

        if selectedEntryID == entryID {
            selectedEntryID = nil
        }

        // Only stop the task owning this entry, not the whole workbench
        if entry.endAt == nil, let task = entry.task {
            timerEngine.stop(task: task)
        }

        DispatchQueue.main.async {
            guard let currentEntry = entries.first(where: { $0.id == entryID }) else {
                return
            }

            modelContext.delete(currentEntry)
            persist()
        }
    }

    private func applySearch<Model>(to models: [Model], text: @escaping (Model) -> String) -> [Model] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return models
        }

        return models.filter { text($0).localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct TaskRow: View {
    let task: WorkTask
    let timerEngine: TimerEngine

    private var taskStatus: TimerStatus {
        if timerEngine.isTaskRunning(task) { return .running }
        if timerEngine.isTaskPaused(task) { return .paused }
        return .idle
    }

    var body: some View {
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

            if taskStatus != .idle {
                StatusPill(status: taskStatus)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let taskCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hexString: project.colorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.body.weight(.medium))
                Text(project.isArchived ? "已归档" : "\(taskCount) 个任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TagRow: View {
    let tag: Tag
    let taskCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hexString: tag.colorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(tag.name)
                    .font(.body.weight(.medium))
                Text("\(taskCount) 个任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TimeEntryRow: View {
    let entry: TimeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.task?.title ?? "未分配任务")
                .font(.body.weight(.medium))

            HStack {
                Text(formattedTimeRange(start: entry.startAt, end: entry.endAt))
                Spacer()
                Text(entry.source.displayTitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct TodayOverview: View {
    let summaries: [TaskSummary]
    let entries: [TimeEntry]
    let timerEngine: TimerEngine

    private var statusText: String {
        if timerEngine.runningCount > 0 {
            return "运行中 \(timerEngine.runningCount) 个"
        } else if timerEngine.pausedCount > 0 {
            return "已暂停 \(timerEngine.pausedCount) 个"
        }
        return "待机"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("今日总览")
                            .font(.title2.weight(.semibold))

                        HStack(spacing: 16) {
                            StatTile(
                                title: "累计工时",
                                value: DurationTextFormatter.compact(timerEngine.todayTotalDuration),
                                systemImage: "calendar.badge.clock",
                                accent: Color(hexString: PaletteColor.lemon.rawValue)
                            )

                            StatTile(
                                title: "实际经过",
                                value: DurationTextFormatter.compact(timerEngine.todayWallClockDuration),
                                systemImage: "clock.fill",
                                accent: Color(hexString: PaletteColor.sky.rawValue)
                            )
                        }

                        HStack(spacing: 16) {
                            StatTile(
                                title: "当前状态",
                                value: statusText,
                                systemImage: timerEngine.timerState.status.symbolName,
                                accent: timerEngine.timerState.status.tint
                            )
                        }
                    }
                    .padding(24)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("今日任务分布")
                        .font(.headline)

                    ForEach(summaries) { summary in
                        HStack {
                            Text(summary.task.title)
                            Spacer()
                            Text(DurationTextFormatter.compact(summary.duration))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("最近记录")
                        .font(.headline)

                    ForEach(entries.prefix(10), id: \.id) { entry in
                        TimeEntryRow(entry: entry)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct TaskInspector: View {
    @Bindable var task: WorkTask
    let entries: [TimeEntry]
    let projects: [Project]
    let tags: [Tag]
    let timerEngine: TimerEngine
    let modelContext: ModelContext
    let onDelete: () -> Void

    private var taskEntries: [TimeEntry] {
        entries.filter { $0.task?.id == task.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("任务名称", text: $task.title)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .textFieldStyle(.plain)
                            .onChange(of: task.title) { _, _ in saveTaskChanges() }

                        Picker("所属项目", selection: projectBinding) {
                            Text("无项目").tag(Optional<UUID>.none)
                            ForEach(projects) { project in
                                Text(project.name).tag(Optional(project.id))
                            }
                        }

                        Toggle("归档任务", isOn: $task.isArchived)
                            .toggleStyle(.switch)
                            .onChange(of: task.isArchived) { _, _ in saveTaskChanges() }

                        Text("备注")
                            .font(.headline)

                        TextEditor(text: $task.notes)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .onChange(of: task.notes) { _, _ in saveTaskChanges() }

                        HStack(spacing: 12) {
                            StatTile(
                                title: "今日工时",
                                value: DurationTextFormatter.compact(timerEngine.aggregationService.totalDuration(on: timerEngine.now, entries: taskEntries, now: timerEngine.now)),
                                systemImage: "sun.max.fill",
                                accent: Color(hexString: PaletteColor.lemon.rawValue)
                            )

                            StatTile(
                                title: "累计工时",
                                value: DurationTextFormatter.compact(timerEngine.aggregationService.totalDuration(for: task, entries: taskEntries, now: timerEngine.now)),
                                systemImage: "clock.arrow.circlepath",
                                accent: Color(hexString: PaletteColor.sky.rawValue)
                            )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("标签")
                                .font(.headline)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                                ForEach(tags) { tag in
                                    Toggle(isOn: Binding(
                                        get: { task.tags.contains(where: { $0.id == tag.id }) },
                                        set: { isSelected in
                                            if isSelected {
                                                task.tags.append(tag)
                                            } else {
                                                task.tags.removeAll(where: { $0.id == tag.id })
                                            }
                                            saveTaskChanges()
                                        }
                                    )) {
                                        Label(tag.name, systemImage: "tag.fill")
                                            .foregroundStyle(Color(hexString: tag.colorHex))
                                    }
                                    .toggleStyle(.button)
                                }
                            }
                        }

                        actionRow
                    }
                    .padding(24)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("最近记录")
                        .font(.headline)

                    ForEach(taskEntries.sorted(by: { $0.startAt > $1.startAt }).prefix(8), id: \.id) { entry in
                        TimeEntryRow(entry: entry)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(24)
        }
    }

    private var projectBinding: Binding<UUID?> {
        Binding<UUID?>(
            get: { task.project?.id },
            set: { newValue in
                task.project = projects.first(where: { $0.id == newValue })
                saveTaskChanges()
            }
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 12) {
            if timerEngine.isTaskRunning(task) {
                ActionCapsuleButton(
                    title: "暂停此任务",
                    systemImage: "pause.fill",
                    tint: Color(hexString: PaletteColor.lemon.rawValue)
                ) {
                    timerEngine.pause(task: task)
                }

                ActionCapsuleButton(
                    title: "停止此任务",
                    systemImage: "stop.fill",
                    tint: Color(hexString: PaletteColor.coral.rawValue)
                ) {
                    timerEngine.stop(task: task)
                }
            } else {
                ActionCapsuleButton(
                    title: timerEngine.isTaskPaused(task) ? "恢复此任务" : "开始此任务",
                    systemImage: "play.fill",
                    tint: Color(hexString: PaletteColor.sky.rawValue)
                ) {
                    timerEngine.start(task: task)
                }
            }

            if timerEngine.primaryTask?.id != task.id,
               timerEngine.isTaskRunning(task) || timerEngine.isTaskPaused(task)
            {
                Button {
                    timerEngine.setPrimaryTask(task)
                } label: {
                    Label("设为主任务", systemImage: "star")
                }
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除任务", systemImage: "trash")
            }
        }
    }

    private func saveTaskChanges() {
        task.updatedAt = Date()

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save task changes: \(error)")
        }
    }
}

private struct ProjectInspector: View {
    let project: Project
    let tasks: [WorkTask]
    let modelContext: ModelContext

    private var projectTasks: [WorkTask] {
        tasks.filter { $0.project?.id == project.id }.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("项目名称", text: Binding(
                            get: { project.name },
                            set: { project.name = $0; persist() }
                        ))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .textFieldStyle(.plain)

                        Picker("项目颜色", selection: Binding(
                            get: { project.colorHex },
                            set: { project.colorHex = $0; persist() }
                        )) {
                            ForEach(PaletteColor.allCases) { color in
                                Label(color.label, systemImage: "circle.fill")
                                    .foregroundStyle(color.color)
                                    .tag(color.rawValue)
                            }
                        }

                        Toggle("归档项目", isOn: Binding(
                            get: { project.isArchived },
                            set: { project.isArchived = $0; persist() }
                        ))

                        Text("包含任务")
                            .font(.headline)

                        ForEach(projectTasks, id: \.id) { task in
                            Text(task.title)
                                .padding(.vertical, 4)
                        }

                        Button(role: .destructive) {
                            projectTasks.forEach { $0.project = nil }
                            modelContext.delete(project)
                            persist()
                        } label: {
                            Label("删除项目", systemImage: "trash")
                        }
                    }
                    .padding(24)
                }
            }
            .padding(24)
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save project changes: \(error)")
        }
    }
}

private struct TagInspector: View {
    let tag: Tag
    let tasks: [WorkTask]
    let modelContext: ModelContext

    private var taggedTasks: [WorkTask] {
        tasks
            .filter { task in
                task.tags.contains(where: { $0.id == tag.id })
            }
            .sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("标签名称", text: Binding(
                            get: { tag.name },
                            set: { tag.name = $0; persist() }
                        ))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .textFieldStyle(.plain)

                        Picker("标签颜色", selection: Binding(
                            get: { tag.colorHex },
                            set: { tag.colorHex = $0; persist() }
                        )) {
                            ForEach(PaletteColor.allCases) { color in
                                Label(color.label, systemImage: "circle.fill")
                                    .foregroundStyle(color.color)
                                    .tag(color.rawValue)
                            }
                        }

                        Text("已使用于以下任务")
                            .font(.headline)

                        ForEach(taggedTasks, id: \.id) { task in
                            Text(task.title)
                                .padding(.vertical, 4)
                        }

                        Button(role: .destructive) {
                            taggedTasks.forEach { task in
                                task.tags.removeAll(where: { $0.id == tag.id })
                            }
                            modelContext.delete(tag)
                            persist()
                        } label: {
                            Label("删除标签", systemImage: "trash")
                        }
                    }
                    .padding(24)
                }
            }
            .padding(24)
        }
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save tag changes: \(error)")
        }
    }
}

private struct TimeEntryInspector: View {
    let entry: TimeEntry
    let tasks: [WorkTask]
    let timerEngine: TimerEngine
    let modelContext: ModelContext
    let onDelete: () -> Void

    private var isRunningEntry: Bool {
        entry.endAt == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("计时记录")
                            .font(.system(.title2, design: .rounded, weight: .semibold))

                        if isRunningEntry {
                            Text("进行中的记录不能直接编辑。请先停止对应任务的计时，再回来修正时间。")
                                .font(.body)
                                .foregroundStyle(.secondary)

                            ActionCapsuleButton(
                                title: "停止此任务",
                                systemImage: "stop.fill",
                                tint: Color(hexString: PaletteColor.coral.rawValue)
                            ) {
                                if let task = entry.task {
                                    timerEngine.stop(task: task)
                                }
                            }
                        } else {
                            Picker("所属任务", selection: taskBinding) {
                                ForEach(tasks) { task in
                                    Text(task.title).tag(Optional(task.id))
                                }
                            }

                            Picker("记录来源", selection: Binding(
                                get: { entry.source },
                                set: { entry.source = $0; persist() }
                            )) {
                                ForEach(TimeEntrySource.allCases) { source in
                                    Text(source.displayTitle).tag(source)
                                }
                            }

                            DatePicker("开始时间", selection: Binding(
                                get: { entry.startAt },
                                set: { newValue in
                                    entry.startAt = newValue
                                    if let endAt = entry.endAt, endAt < newValue {
                                        entry.endAt = newValue
                                    }
                                    persist()
                                }
                            ))

                            DatePicker("结束时间", selection: endBinding)
                        }

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("删除记录", systemImage: "trash")
                        }
                    }
                    .padding(24)
                }
            }
            .padding(24)
        }
    }

    private var taskBinding: Binding<UUID?> {
        Binding<UUID?>(
            get: { entry.task?.id },
            set: { newValue in
                entry.task = tasks.first(where: { $0.id == newValue })
                persist()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding<Date>(
            get: { entry.endAt ?? entry.startAt },
            set: { newValue in
                entry.endAt = max(entry.startAt, newValue)
                persist()
            }
        )
    }

    private func persist() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to save entry changes: \(error)")
        }
    }
}

private struct SearchableList<Content: View>: View {
    let title: String
    @Binding var text: String
    let content: Content

    init(title: String, text: Binding<String>, @ViewBuilder content: () -> Content) {
        self.title = title
        _text = text
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .padding()

            content
        }
    }
}

private extension View {
    func searchableList(title: String, text: Binding<String>, @ViewBuilder content: () -> some View) -> some View {
        SearchableList(title: title, text: text, content: content)
    }
}
