import AppKit
import SwiftData
import SwiftUI

private enum SidebarSection: String, CaseIterable, Hashable, Identifiable {
    case today
    case overview
    case tasks
    case projects
    case tags
    case records
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今天"
        case .overview: "总览"
        case .tasks: "所有任务"
        case .projects: "项目"
        case .tags: "标签"
        case .records: "记录"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "clock.badge.checkmark"
        case .overview: "chart.bar.xaxis"
        case .tasks: "checklist"
        case .projects: "square.grid.2x2"
        case .tags: "tag"
        case .records: "list.bullet.rectangle.portrait"
        case .settings: "gearshape"
        }
    }
}

struct MainWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var timerEngine: TimerEngine
    @EnvironmentObject private var mainWindowRouter: MainWindowRouter
    @EnvironmentObject private var appSettings: AppSettings

    @Query(sort: [SortDescriptor(\WorkTask.updatedAt, order: .reverse)]) private var tasks: [WorkTask]
    @Query(sort: [SortDescriptor(\Project.createdAt)]) private var projects: [Project]
    @Query(sort: [SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query(sort: [SortDescriptor(\TimeEntry.startAt, order: .reverse)]) private var entries: [TimeEntry]

    @State private var selectedSection: SidebarSection? = .today
    @State private var displayedSection: SidebarSection = .today
    @State private var routedSection: SidebarSection?
    @State private var searchText = ""
    @State private var selectedTaskID: UUID?
    @State private var selectedProjectID: UUID?
    @State private var selectedTagID: UUID?
    @State private var selectedEntryID: UUID?
    @State private var recordFilterDate = Date()
    @State private var recordProjectID: UUID?
    @State private var recordTagID: UUID?
    @State private var recordTaskID: UUID?
    @State private var todayViewDate = Date()
    @State private var overviewPeriod: OverviewPeriod = .today
    @State private var overviewCustomStart: Date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var overviewCustomEnd: Date = Date()

    private var todaySummaries: [TaskSummary] {
        timerEngine.aggregationService.groupedDurations(on: todayViewDate, entries: entries, now: timerEngine.now)
            .sorted { a, b in
                let aOrder = taskSortOrder(a.task)
                let bOrder = taskSortOrder(b.task)
                if aOrder != bOrder { return aOrder < bOrder }
                return a.duration > b.duration
            }
    }

    private var isViewingToday: Bool {
        Calendar.autoupdatingCurrent.isDate(todayViewDate, inSameDayAs: timerEngine.now)
    }

    private var todayViewTotalDuration: TimeInterval {
        timerEngine.aggregationService.totalDuration(on: todayViewDate, entries: entries, now: timerEngine.now)
    }

    private var todayViewWallClockDuration: TimeInterval {
        let interval = timerEngine.aggregationService.dayInterval(for: todayViewDate)
        return timerEngine.aggregationService.wallClockDuration(in: interval, entries: entries, now: timerEngine.now)
    }

    private var todayViewDateBinding: Binding<Date> {
        Binding(
            get: { todayViewDate },
            set: { newValue in
                if selectedTaskID != nil {
                    selectedTaskID = nil
                }
                todayViewDate = newValue
            }
        )
    }

    /// Selection binding for the today List. The getter filters out any id that isn't
    /// present in todaySummaries so the List's NSTableView never sees a stale selection
    /// tag after the date changes — which otherwise would trigger a reentrant delegate
    /// call when the table reloads with mismatching selection + data.
    private var todaySelectedTaskBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let id = selectedTaskID,
                      todaySummaries.contains(where: { $0.task.id == id }) else {
                    return nil
                }
                return id
            },
            set: { selectedTaskID = $0 }
        )
    }

    /// Running = 0, Paused = 1, Stopped = 2 — for sorting active tasks first.
    private func taskSortOrder(_ task: WorkTask) -> Int {
        if timerEngine.isTaskRunning(task) { return 0 }
        if timerEngine.isTaskPaused(task) { return 1 }
        return 2
    }

    private var activeSection: SidebarSection {
        displayedSection
    }

    private var todayEntries: [TimeEntry] {
        let interval = timerEngine.aggregationService.dayInterval(for: todayViewDate)
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
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
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
        .onChange(of: selectedSection) { _, newSection in
            guard let newSection else { return }
            if routedSection == newSection {
                routedSection = nil
                return
            }
            // Defer page replacement and secondary List selection changes until after the
            // sidebar NSTableView finishes processing its delegate selection callback.
            DispatchQueue.main.async {
                displayedSection = newSection
                selectedTaskID = nil
                selectedProjectID = nil
                selectedTagID = nil
                selectedEntryID = nil
            }
        }
    }

    private func sectionFor(_ destination: MainWindowDestination) -> SidebarSection {
        switch destination {
        case .today: return .today
        case .overview: return .overview
        case .tasks: return .tasks
        case .projects: return .projects
        case .tags: return .tags
        case .records: return .records
        case .settings: return .settings
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch activeSection {
        case .today:
            todayContent
        case .overview:
            overviewContent
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
        case .settings:
            settingsContent
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
                    onDelete: { deleteTask(selectedTask) },
                    onClose: { DispatchQueue.main.async { selectedTaskID = nil } }
                )
            } else {
                TodayOverview(
                    date: todayViewDate,
                    isToday: isViewingToday,
                    totalDuration: todayViewTotalDuration,
                    wallClockDuration: todayViewWallClockDuration,
                    summaries: todaySummaries,
                    entries: todayEntries,
                    timerEngine: timerEngine
                )
            }
        case .overview:
            if let selectedTask = tasks.first(where: { $0.id == selectedTaskID }) {
                TaskInspector(
                    task: selectedTask,
                    entries: entries,
                    projects: projects,
                    tags: tags,
                    timerEngine: timerEngine,
                    modelContext: modelContext,
                    onDelete: { deleteTask(selectedTask) },
                    onClose: { DispatchQueue.main.async { selectedTaskID = nil } }
                )
            } else {
                EmptyStateView(
                    title: "选择一个任务",
                    message: "在左侧任务细分里选中任务，可以在这里查看它的详情。",
                    systemImage: "chart.bar.xaxis"
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
                    onDelete: { deleteTask(selectedTask) },
                    onClose: { DispatchQueue.main.async { selectedTaskID = nil } }
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
        case .settings:
            EmptyView()
        }
    }

    private var todayContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                DatePicker("日期", selection: todayViewDateBinding, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()

                if !isViewingToday {
                    Button("回到今天") {
                        selectedTaskID = nil
                        todayViewDate = Date()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)

            List(selection: todaySelectedTaskBinding) {
                Section(isViewingToday ? "今日任务" : "\(todayViewDate.shortDateText()) 的任务") {
                    if todaySummaries.isEmpty {
                        Text("这一天没有计时记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(todaySummaries) { summary in
                        HStack {
                            TaskRow(task: summary.task, timerEngine: timerEngine)
                            Spacer()
                            Text(DurationTextFormatter.compact(summary.duration))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .tag(summary.task.id)
                    }
                }

                Section(isViewingToday ? "最近记录" : "当日记录") {
                    ForEach(todayEntries.prefix(12), id: \.id) { entry in
                        Button {
                            let taskID = entry.task?.id
                            DispatchQueue.main.async {
                                selectedTaskID = taskID
                            }
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
            // Force SwiftUI to treat each day's List as a distinct view identity, so switching
            // dates rebuilds a fresh NSTableView instead of reloading the existing one mid-render.
            // This sidesteps the reentrant delegate warning triggered when the underlying
            // NSTableView tries to reconcile selection + data changes in the same pass.
            .id(Calendar.autoupdatingCurrent.startOfDay(for: todayViewDate))
        }
    }

    private var overviewInterval: DateInterval {
        switch overviewPeriod {
        case .today:
            return timerEngine.aggregationService.dayInterval(for: timerEngine.now)
        case .week:
            return timerEngine.aggregationService.weekInterval(for: timerEngine.now)
        case .month:
            return timerEngine.aggregationService.monthInterval(for: timerEngine.now)
        case .custom:
            return timerEngine.aggregationService.customInterval(from: overviewCustomStart, to: overviewCustomEnd)
        }
    }

    private var overviewContent: some View {
        OverviewContentView(
            period: $overviewPeriod,
            customStart: $overviewCustomStart,
            customEnd: $overviewCustomEnd,
            interval: overviewInterval,
            entries: entries,
            timerEngine: timerEngine,
            selectedTaskID: $selectedTaskID
        )
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

    private var settingsContent: some View {
        Form {
            Section("显示") {
                Toggle("启用刘海显示", isOn: $appSettings.isNotchDisplayEnabled)
                Toggle("任务栏计时显示", isOn: $appSettings.isMenuBarTimerDisplayEnabled)
            }
            Section("数据") {
                Button("导出 CSV…") { exportCSV() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = CSVExportService.suggestedFileName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let csv = CSVExportService.makeCSV(from: entries)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
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
                    mainWindowRouter.destination = .tasks(task.id)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
            case .overview:
                EmptyView()
            case .projects:
                Button {
                    let project = Project()
                    modelContext.insert(project)
                    persist()
                    mainWindowRouter.destination = .projects(project.id)
                } label: {
                    Label("新建项目", systemImage: "plus")
                }
            case .tags:
                Button {
                    let tag = Tag()
                    modelContext.insert(tag)
                    persist()
                    mainWindowRouter.destination = .tags(tag.id)
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
                    mainWindowRouter.destination = .records(entry.id)
                } label: {
                    Label("新增记录", systemImage: "plus")
                }
            case .settings:
                EmptyView()
            }
        }
    }

    private func apply(_ destination: MainWindowDestination) {
        let destinationSection = sectionFor(destination)
        if selectedSection != destinationSection {
            routedSection = destinationSection
        }
        selectedSection = destinationSection
        displayedSection = destinationSection

        switch destination {
        case .today:
            break
        case .overview:
            break
        case .tasks(let taskID):
            selectedTaskID = taskID
        case .projects(let projectID):
            selectedProjectID = projectID
        case .tags(let tagID):
            selectedTagID = tagID
        case .records(let entryID):
            selectedEntryID = entryID
        case .settings:
            break
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

        DispatchQueue.main.async {
            if selectedTaskID == taskID {
                selectedTaskID = nil
            }

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

        // Only stop the task owning this entry, not the whole workbench
        if entry.endAt == nil, let task = entry.task {
            timerEngine.stop(task: task)
        }

        DispatchQueue.main.async {
            if selectedEntryID == entryID {
                selectedEntryID = nil
            }

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
    let date: Date
    let isToday: Bool
    let totalDuration: TimeInterval
    let wallClockDuration: TimeInterval
    let summaries: [TaskSummary]
    let entries: [TimeEntry]
    let timerEngine: TimerEngine

    private var headerTitle: String {
        isToday ? "今日总览" : "\(date.shortDateText()) 总览"
    }

    private var distributionTitle: String {
        isToday ? "今日任务分布" : "当日任务分布"
    }

    private var recentTitle: String {
        isToday ? "最近记录" : "当日记录"
    }

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
                        Text(headerTitle)
                            .font(.title2.weight(.semibold))

                        HStack(spacing: 16) {
                            StatTile(
                                title: "累计工时",
                                value: DurationTextFormatter.compact(totalDuration),
                                systemImage: "calendar.badge.clock",
                                accent: Color(hexString: PaletteColor.lemon.rawValue)
                            )

                            StatTile(
                                title: "实际经过",
                                value: DurationTextFormatter.compact(wallClockDuration),
                                systemImage: "clock.fill",
                                accent: Color(hexString: PaletteColor.sky.rawValue)
                            )
                        }

                        if isToday {
                            HStack(spacing: 16) {
                                StatTile(
                                    title: "当前状态",
                                    value: statusText,
                                    systemImage: timerEngine.timerState.status.symbolName,
                                    accent: timerEngine.timerState.status.tint
                                )
                            }
                        }
                    }
                    .padding(24)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(distributionTitle)
                        .font(.headline)

                    if summaries.isEmpty {
                        Text("这一天没有计时记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

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
                    Text(recentTitle)
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
    let onClose: () -> Void

    private var taskEntries: [TimeEntry] {
        entries.filter { $0.task?.id == task.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Spacer()
                            Button {
                                onClose()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("关闭详情")
                        }

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

private struct OverviewContentView: View {
    @Binding var period: OverviewPeriod
    @Binding var customStart: Date
    @Binding var customEnd: Date
    let interval: DateInterval
    let entries: [TimeEntry]
    let timerEngine: TimerEngine
    @Binding var selectedTaskID: UUID?

    private var totalDuration: TimeInterval {
        timerEngine.aggregationService.totalDuration(in: interval, entries: entries, now: timerEngine.now)
    }

    private var wallClockDuration: TimeInterval {
        timerEngine.aggregationService.wallClockDuration(in: interval, entries: entries, now: timerEngine.now)
    }

    private var taskSummaries: [TaskSummary] {
        timerEngine.aggregationService.groupedDurations(in: interval, entries: entries, now: timerEngine.now)
    }

    private var projectSummaries: [ProjectSummary] {
        timerEngine.aggregationService.groupedByProject(in: interval, entries: entries, now: timerEngine.now)
    }

    private var tagSummaries: [TagSummary] {
        timerEngine.aggregationService.groupedByTag(in: interval, entries: entries, now: timerEngine.now)
    }

    private var rangeTitle: String {
        switch period {
        case .today: return "今日总览"
        case .week: return "本周总览"
        case .month: return "本月总览"
        case .custom:
            let start = interval.start.shortDateText()
            let end = Calendar.autoupdatingCurrent.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            if Calendar.autoupdatingCurrent.isDate(interval.start, inSameDayAs: end) {
                return "\(start) 总览"
            }
            return "\(start) - \(end.shortDateText()) 总览"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodControls

                GlassPanel(cornerRadius: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(rangeTitle)
                            .font(.title2.weight(.semibold))

                        HStack(spacing: 16) {
                            StatTile(
                                title: "累计工时",
                                value: DurationTextFormatter.compact(totalDuration),
                                systemImage: "calendar.badge.clock",
                                accent: Color(hexString: PaletteColor.lemon.rawValue)
                            )

                            StatTile(
                                title: "实际经过",
                                value: DurationTextFormatter.compact(wallClockDuration),
                                systemImage: "clock.fill",
                                accent: Color(hexString: PaletteColor.sky.rawValue)
                            )
                        }
                    }
                    .padding(24)
                }

                breakdownSection(title: "任务细分", emptyHint: "这段时间没有任务记录") {
                    if taskSummaries.isEmpty {
                        emptyRow("这段时间没有任务记录")
                    } else {
                        ForEach(taskSummaries) { summary in
                            Button {
                                let id = summary.task.id
                                DispatchQueue.main.async {
                                    selectedTaskID = id
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(hexString: summary.task.project?.colorHex ?? PaletteColor.sky.rawValue))
                                        .frame(width: 10, height: 10)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(summary.task.title)
                                            .font(.body.weight(.medium))
                                        Text(summary.task.project?.name ?? "未分配项目")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(DurationTextFormatter.compact(summary.duration))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                breakdownSection(title: "项目细分", emptyHint: "没有项目维度的记录") {
                    if projectSummaries.isEmpty {
                        emptyRow("没有项目维度的记录")
                    } else {
                        ForEach(projectSummaries) { summary in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hexString: summary.colorHex))
                                    .frame(width: 10, height: 10)

                                Text(summary.displayName)
                                    .font(.body.weight(.medium))

                                Spacer()

                                Text(DurationTextFormatter.compact(summary.duration))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }

                breakdownSection(title: "标签细分", emptyHint: "没有标签维度的记录") {
                    if tagSummaries.isEmpty {
                        emptyRow("没有标签维度的记录")
                    } else {
                        ForEach(tagSummaries) { summary in
                            HStack(spacing: 12) {
                                TagPill(tag: summary.tag)

                                Spacer()

                                Text(DurationTextFormatter.compact(summary.duration))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("时间范围", selection: $period) {
                ForEach(OverviewPeriod.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if period == .custom {
                HStack(spacing: 12) {
                    DatePicker("开始", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                        .datePickerStyle(.compact)

                    DatePicker("结束", selection: $customEnd, in: customStart..., displayedComponents: .date)
                        .datePickerStyle(.compact)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownSection<Inner: View>(title: String, emptyHint: String, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
    }
}
