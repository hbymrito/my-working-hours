import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var timerEngine: TimerEngine

    var body: some View {
        Label("My Working Hours", systemImage: timerEngine.timerState.status.symbolName)
            .labelStyle(.iconOnly)
            .foregroundStyle(timerEngine.timerState.status.tint)
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var timerEngine: TimerEngine
    @EnvironmentObject private var overlayController: NotchOverlayController
    @EnvironmentObject private var mainWindowRouter: MainWindowRouter

    @State private var isTaskSwitcherPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Primary task header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let primary = timerEngine.primaryTask {
                        HStack(spacing: 6) {
                            Text(primary.title)
                                .font(.headline.weight(.semibold))
                            if timerEngine.runningCount > 1 {
                                Text("+\(timerEngine.runningCount - 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(primary.project?.name ?? "未分配项目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("还没有开始计时")
                            .font(.headline.weight(.semibold))
                        Text("选择一个任务后开始")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                StatusPill(status: timerEngine.timerState.status)
            }

            // Duration panel
            GlassPanel(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(DurationTextFormatter.clock(timerEngine.primarySessionDuration))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    HStack(spacing: 12) {
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
                }
                .padding(18)
            }

            // Running tasks list
            if !timerEngine.runningTasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("运行中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(timerEngine.runningTasks, id: \.id) { task in
                        taskControlRow(task: task, isRunning: true)
                    }
                }
            }

            // Paused tasks list
            if !timerEngine.pausedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已暂停")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(timerEngine.pausedTasks, id: \.id) { task in
                        taskControlRow(task: task, isRunning: false)
                    }
                }
            }

            // Global actions
            VStack(spacing: 10) {
                if timerEngine.runningCount > 0 {
                    HStack(spacing: 10) {
                        ActionCapsuleButton(
                            title: "全部暂停",
                            systemImage: "pause.fill",
                            tint: Color(hexString: PaletteColor.lemon.rawValue)
                        ) {
                            timerEngine.pauseAll()
                        }

                        ActionCapsuleButton(
                            title: "全部停止",
                            systemImage: "stop.fill",
                            tint: Color(hexString: PaletteColor.coral.rawValue)
                        ) {
                            timerEngine.stopAll()
                        }
                    }
                } else if timerEngine.pausedCount > 0 {
                    // All paused — offer to resume primary
                    if let primary = timerEngine.primaryTask {
                        ActionCapsuleButton(
                            title: "恢复 \(primary.title)",
                            systemImage: "play.fill",
                            tint: Color(hexString: PaletteColor.sky.rawValue)
                        ) {
                            timerEngine.start(task: primary)
                        }
                    }
                } else {
                    // Idle
                    ActionCapsuleButton(
                        title: "选择任务开始",
                        systemImage: "play.fill",
                        tint: Color(hexString: PaletteColor.sky.rawValue)
                    ) {
                        isTaskSwitcherPresented = true
                    }
                }

                Button {
                    isTaskSwitcherPresented = true
                } label: {
                    Label("加入并行任务", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftCapsuleButtonStyle(tint: Color.white.opacity(0.1), foreground: .primary))
                .popover(isPresented: $isTaskSwitcherPresented, arrowEdge: .bottom) {
                    QuickTaskSwitcherView { task in
                        timerEngine.start(task: task)
                        isTaskSwitcherPresented = false
                    }
                    .environmentObject(timerEngine)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                menuAction("打开主界面", systemImage: "macwindow") {
                    if let primaryTask = timerEngine.primaryTask {
                        mainWindowRouter.open(.tasks(primaryTask.id))
                    } else {
                        mainWindowRouter.open(.today)
                    }
                }

                menuAction(
                    overlayController.mode == .pinned ? "收起刘海面板" : "固定刘海面板",
                    systemImage: "rectangle.topthird.inset.filled"
                ) {
                    overlayController.togglePinned()
                }

                menuAction("退出应用", systemImage: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    @ViewBuilder
    private func taskControlRow(task: WorkTask, isRunning: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hexString: task.project?.colorHex ?? PaletteColor.sky.rawValue))
                .frame(width: 8, height: 8)

            Text(task.title)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            if timerEngine.primaryTask?.id != task.id {
                Button {
                    timerEngine.setPrimaryTask(task)
                } label: {
                    Image(systemName: "star")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("设为主任务")
            }

            if isRunning {
                Button {
                    timerEngine.pause(task: task)
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hexString: PaletteColor.lemon.rawValue))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    timerEngine.start(task: task)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(Color(hexString: PaletteColor.sky.rawValue))
                }
                .buttonStyle(.plain)
            }

            Button {
                timerEngine.stop(task: task)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundStyle(Color(hexString: PaletteColor.coral.rawValue))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func menuAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
