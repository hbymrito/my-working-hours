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

    private var hasSelectedTask: Bool {
        timerEngine.activeTask != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timerEngine.activeTask?.title ?? "还没有开始计时")
                        .font(.headline.weight(.semibold))

                    Text(timerEngine.activeTask?.project?.name ?? "选择一个任务后开始")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(status: timerEngine.timerState.status)
            }

            GlassPanel(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(DurationTextFormatter.clock(timerEngine.currentSessionDuration))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    HStack(spacing: 12) {
                        StatTile(
                            title: "今日累计",
                            value: DurationTextFormatter.compact(timerEngine.todayTotalDuration),
                            systemImage: "sun.max.fill",
                            accent: Color(hexString: PaletteColor.lemon.rawValue)
                        )

                        StatTile(
                            title: "当前状态",
                            value: timerEngine.timerState.status.displayTitle,
                            systemImage: timerEngine.timerState.status.symbolName,
                            accent: timerEngine.timerState.status.tint
                        )
                    }
                }
                .padding(18)
            }

            VStack(spacing: 10) {
                if timerEngine.timerState.status == .running {
                    HStack(spacing: 10) {
                        ActionCapsuleButton(
                            title: "暂停",
                            systemImage: "pause.fill",
                            tint: Color(hexString: PaletteColor.lemon.rawValue)
                        ) {
                            timerEngine.pauseTimer()
                        }

                        ActionCapsuleButton(
                            title: "停止",
                            systemImage: "stop.fill",
                            tint: Color(hexString: PaletteColor.coral.rawValue)
                        ) {
                            timerEngine.stopTimer()
                        }
                    }
                } else {
                    ActionCapsuleButton(
                        title: hasSelectedTask ? (timerEngine.timerState.status == .paused ? "继续计时" : "开始计时") : "选择任务开始",
                        systemImage: "play.fill",
                        tint: Color(hexString: PaletteColor.sky.rawValue)
                    ) {
                        startOrPromptSelection()
                    }
                }

                Button {
                    isTaskSwitcherPresented = true
                } label: {
                    Label("快速切换任务", systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftCapsuleButtonStyle(tint: Color.white.opacity(0.1), foreground: .primary))
                .popover(isPresented: $isTaskSwitcherPresented, arrowEdge: .bottom) {
                    QuickTaskSwitcherView { task in
                        activate(task)
                        isTaskSwitcherPresented = false
                    }
                    .environmentObject(timerEngine)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                menuAction("打开主界面", systemImage: "macwindow") {
                    if let activeTask = timerEngine.activeTask {
                        mainWindowRouter.open(.tasks(activeTask.id))
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
    private func menuAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func startOrPromptSelection() {
        guard hasSelectedTask else {
            isTaskSwitcherPresented = true
            return
        }

        try? timerEngine.startTimer()
    }

    private func activate(_ task: WorkTask) {
        if timerEngine.timerState.status == .running {
            timerEngine.switchTask(to: task)
            return
        }

        timerEngine.selectTask(task)
        try? timerEngine.startTimer()
    }
}
