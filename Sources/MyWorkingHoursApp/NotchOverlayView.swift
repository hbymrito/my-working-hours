import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var timerEngine: TimerEngine
    @EnvironmentObject private var overlayController: NotchOverlayController
    @EnvironmentObject private var mainWindowRouter: MainWindowRouter

    @State private var isTaskSwitcherPresented = false

    private var isPinned: Bool {
        overlayController.mode == .pinned
    }

    private var overlayWidth: CGFloat {
        isPinned ? 470 : 390
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.96))
                .frame(width: isPinned ? 220 : 180, height: 28)
                .overlay(alignment: .bottom) {
                    Capsule(style: .continuous)
                        .fill(.black.opacity(0.28))
                        .frame(width: isPinned ? 240 : 200, height: 8)
                        .blur(radius: 8)
                        .offset(y: 8)
                }

            GlassPanel(cornerRadius: 32) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(timerEngine.activeTask?.title ?? "点击开始你的第一个任务")
                                .font(.system(.title3, design: .rounded, weight: .semibold))

                            Text(timerEngine.activeTask?.project?.name ?? "工时会在这里持续积累")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        StatusPill(status: timerEngine.timerState.status)
                    }

                    Text(DurationTextFormatter.clock(timerEngine.currentSessionDuration))
                        .font(.system(size: isPinned ? 54 : 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    HStack(spacing: 12) {
                        StatTile(
                            title: "今日已累计",
                            value: DurationTextFormatter.compact(timerEngine.todayTotalDuration),
                            systemImage: "calendar",
                            accent: Color(hexString: PaletteColor.lemon.rawValue)
                        )

                        StatTile(
                            title: "当前任务",
                            value: timerEngine.activeTask?.title ?? "未选择",
                            systemImage: "briefcase.fill",
                            accent: Color(hexString: PaletteColor.sky.rawValue)
                        )
                    }

                    VStack(spacing: 12) {
                        if timerEngine.timerState.status == .running {
                            HStack(spacing: 12) {
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
                                title: timerEngine.activeTask == nil ? "选择任务开始" : (timerEngine.timerState.status == .paused ? "继续计时" : "开始计时"),
                                systemImage: "play.fill",
                                tint: Color(hexString: PaletteColor.sky.rawValue)
                            ) {
                                startOrPromptSelection()
                            }
                        }

                        if isPinned {
                            HStack(spacing: 12) {
                                Button {
                                    isTaskSwitcherPresented = true
                                } label: {
                                    Label("切换任务", systemImage: "arrow.triangle.branch")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftCapsuleButtonStyle(tint: .white.opacity(0.12), foreground: .primary))
                                .popover(isPresented: $isTaskSwitcherPresented, arrowEdge: .top) {
                                    QuickTaskSwitcherView { task in
                                        activate(task)
                                        isTaskSwitcherPresented = false
                                        overlayController.showPinned()
                                    }
                                    .environmentObject(timerEngine)
                                }

                                Button {
                                    if let activeTask = timerEngine.activeTask {
                                        mainWindowRouter.open(.tasks(activeTask.id))
                                    } else {
                                        mainWindowRouter.open(.today)
                                    }
                                } label: {
                                    Label("打开主界面", systemImage: "macwindow")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftCapsuleButtonStyle(tint: .white.opacity(0.12), foreground: .primary))
                            }
                        }
                    }
                }
                .padding(isPinned ? 22 : 20)
            }
        }
        .frame(width: overlayWidth)
        .padding(.top, 8)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onHover { overlayController.overlayHoverChanged($0) }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: overlayController.mode)
    }

    private func startOrPromptSelection() {
        guard timerEngine.activeTask != nil else {
            overlayController.isTaskSwitcherPresented = true
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
