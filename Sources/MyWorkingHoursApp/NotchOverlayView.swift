import SwiftUI

struct NotchOverlayView: View {
    @EnvironmentObject private var timerEngine: TimerEngine
    @EnvironmentObject private var overlayController: NotchOverlayController
    @EnvironmentObject private var mainWindowRouter: MainWindowRouter

    private var overlayWidth: CGFloat {
        520
    }

    private var overlayHeight: CGFloat {
        isSimulatedNotch ? 32 : 68
    }

    private var contentTopInset: CGFloat {
        isSimulatedNotch ? 1 : 0
    }

    private var contentBottomInset: CGFloat {
        isSimulatedNotch ? 0 : 4
    }

    private var contentHeight: CGFloat {
        28
    }

    private var contentWidth: CGFloat {
        isSimulatedNotch ? 480 : 420
    }

    private var itemSpacing: CGFloat {
        5
    }

    private var titleRegionWidth: CGFloat? {
        isSimulatedNotch ? 286 : 226
    }

    private var titleFontSize: CGFloat {
        11
    }

    private var clockFontSize: CGFloat {
        15
    }

    private var buttonSize: CGFloat {
        22
    }

    private var buttonIconSize: CGFloat {
        9
    }

    private var contentAlignment: Alignment {
        isSimulatedNotch ? .top : .bottom
    }

    private var topCornerRadius: CGFloat {
        isSimulatedNotch ? 8 : 18
    }

    private var bottomCornerRadius: CGFloat {
        isSimulatedNotch ? 14 : 24
    }

    private var isSimulatedNotch: Bool {
        overlayController.chromeStyle == .simulatedNotch
    }

    private var displayTitle: String {
        guard let primary = timerEngine.primaryTask else {
            return "未选择任务"
        }
        if timerEngine.runningCount > 1 {
            return "\(primary.title) +\(timerEngine.runningCount - 1)"
        }
        return primary.title
    }

    private var hasActiveTasks: Bool {
        timerEngine.runningCount > 0 || timerEngine.pausedCount > 0
    }

    var body: some View {
        HStack(spacing: itemSpacing) {
            MarqueeText(
                text: displayTitle,
                font: .system(size: titleFontSize, weight: .semibold, design: .rounded),
                foregroundColor: foregroundColor.opacity(timerEngine.primaryTask == nil ? 0.78 : 0.96)
            )
            .frame(width: titleRegionWidth, alignment: .leading)
            .frame(maxWidth: titleRegionWidth == nil ? .infinity : nil, alignment: .leading)
            .offset(y: 2)

            Spacer(minLength: 0)

            Text(DurationTextFormatter.clock(timerEngine.primarySessionDuration))
                .font(.system(size: clockFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(foregroundColor)

            // Play / add task
            overlayButton(
                systemImage: timerEngine.runningCount > 0 ? "plus" : "play.fill",
                tint: Color(hexString: PaletteColor.sky.rawValue),
                isEnabled: true
            ) {
                if timerEngine.runningCount > 0 {
                    mainWindowRouter.open(.tasks(nil))
                } else if let primary = timerEngine.primaryTask {
                    timerEngine.start(task: primary)
                } else {
                    mainWindowRouter.open(.tasks(nil))
                }
            }

            // Pause all
            overlayButton(
                systemImage: "pause.fill",
                tint: Color(hexString: PaletteColor.lemon.rawValue),
                isEnabled: timerEngine.runningCount > 0
            ) {
                timerEngine.pauseAll()
            }

            // Stop all
            overlayButton(
                systemImage: "stop.fill",
                tint: Color(hexString: PaletteColor.coral.rawValue),
                isEnabled: hasActiveTasks
            ) {
                timerEngine.stopAll()
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        .padding(.top, contentTopInset)
        .padding(.bottom, contentBottomInset)
        .frame(width: overlayWidth, height: overlayHeight, alignment: contentAlignment)
        .background(backgroundShape)
        .frame(width: overlayWidth)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onHover { overlayController.overlayHoverChanged($0) }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: overlayController.mode)
    }

    @ViewBuilder
    private func overlayButton(systemImage: String, tint: Color, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: buttonIconSize, weight: .bold))
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(CompactOverlayButtonStyle(
            tint: isEnabled ? tint : .gray.opacity(0.28),
            foreground: .white,
            usesDarkChrome: true
        ))
        .disabled(!isEnabled)
    }

    private var foregroundColor: Color {
        .white
    }

    @ViewBuilder
    private var backgroundShape: some View {
        let notchShape = NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)

        notchShape
            .fill(Color.black.opacity(0.96))
            .overlay {
                notchShape
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.96))
                    .frame(height: 1)
                    .padding(.horizontal, topCornerRadius)
            }
            .shadow(color: .black.opacity(0.34), radius: 14, y: 8)
    }
}

private struct CompactOverlayButtonStyle: ButtonStyle {
    let tint: Color
    let foreground: Color
    let usesDarkChrome: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(configuration.isPressed ? 0.84 : 1),
                                tint.opacity(configuration.isPressed ? 0.68 : 0.9),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        usesDarkChrome ? .white.opacity(configuration.isPressed ? 0.08 : 0.18) : .white.opacity(configuration.isPressed ? 0.14 : 0.32),
                        lineWidth: 1
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let foregroundColor: Color

    private let gap: CGFloat = 28
    private let speed: CGFloat = 32

    @State private var textWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                if shouldScroll(in: width) {
                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: isAnimating ? -(textWidth + gap) : 0)
                } else {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .clipped()
            .onAppear {
                availableWidth = width
                restartAnimationIfNeeded(for: width)
            }
            .onChange(of: width) { _, newValue in
                availableWidth = newValue
                restartAnimationIfNeeded(for: newValue)
            }
            .onChange(of: text) { _, _ in
                restartAnimationIfNeeded(for: availableWidth)
            }
            .onChange(of: textWidth) { _, _ in
                restartAnimationIfNeeded(for: availableWidth)
            }
        }
        .frame(height: 22)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            textWidth = proxy.size.width
                        }
                        .onChange(of: proxy.size.width) { _, newValue in
                            textWidth = newValue
                        }
                }
            )
    }

    private func shouldScroll(in width: CGFloat) -> Bool {
        textWidth > width + 6
    }

    private func restartAnimationIfNeeded(for width: CGFloat) {
        guard width > 0 else {
            return
        }

        let needsScroll = shouldScroll(in: width)
        isAnimating = false

        guard needsScroll else {
            return
        }

        let duration = max(5, Double((textWidth + gap) / speed))
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}
