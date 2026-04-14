import SwiftData
import SwiftUI

struct QuickTaskSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var timerEngine: TimerEngine
    @Query(sort: [SortDescriptor(\WorkTask.updatedAt, order: .reverse)]) private var tasks: [WorkTask]

    @State private var searchText = ""

    let onSelect: (WorkTask) -> Void

    private var activeProjectID: UUID? {
        timerEngine.activeTask?.project?.id
    }

    private var filteredTasks: [WorkTask] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return tasks
        }

        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var currentProjectTasks: [WorkTask] {
        guard let activeProjectID else {
            return []
        }

        return filteredTasks.filter { $0.project?.id == activeProjectID }
    }

    private var recentTasks: [WorkTask] {
        let excludedIDs = Set(currentProjectTasks.map(\.id))
        return filteredTasks.filter { !excludedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("快速切换任务")
                    .font(.headline.weight(.semibold))

                Spacer()

                Button("新建并开始", action: createTask)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField("搜索任务，或输入后直接新建", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List {
                if !currentProjectTasks.isEmpty {
                    Section("当前项目") {
                        ForEach(currentProjectTasks) { task in
                            taskRow(task)
                        }
                    }
                }

                Section("最近任务") {
                    ForEach(recentTasks.prefix(10)) { task in
                        taskRow(task)
                    }
                }
            }
            .frame(minWidth: 320, minHeight: 300)

            if tasks.isEmpty {
                Text("还没有任务，输入名字后点击“新建并开始”即可。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
    }

    @ViewBuilder
    private func taskRow(_ task: WorkTask) -> some View {
        Button {
            onSelect(task)
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

                if timerEngine.activeTask?.id == task.id {
                    StatusPill(status: timerEngine.timerState.status)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createTask() {
        let task = timerEngine.createTask(
            named: searchText,
            project: timerEngine.activeTask?.project
        )
        onSelect(task)
    }
}
