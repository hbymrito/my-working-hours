import SwiftUI

struct TimelineDaySidebar: View {
    @EnvironmentObject private var timerMetrics: TimerMetrics
    @Binding var date: Date
    let entries: [TimeEntry]
    let workflowService: TimelineWorkflowService
    let aggregationService: TimeAggregationService
    let onEdit: (UUID) -> Void
    let onRequestMerge: (TimeEntryMergeSuggestion) -> Void

    private var analysis: TimelineDayAnalysis {
        workflowService.analyze(day: date, entries: entries, now: timerMetrics.now)
    }

    private var interval: DateInterval {
        aggregationService.dayInterval(for: date)
    }

    private var totalDuration: TimeInterval {
        aggregationService.totalDuration(in: interval, entries: entries, now: timerMetrics.now)
    }

    private var wallClockDuration: TimeInterval {
        aggregationService.wallClockDuration(in: interval, entries: entries, now: timerMetrics.now)
    }

    private var displayedEntries: [TimeEntry] {
        let ids = Set(analysis.items.map(\.entryID))
        return entries.filter { ids.contains($0.id) }.sorted { $0.startAt < $1.startAt }
    }

    private var anomalousItems: [TimelineItem] {
        analysis.items.filter { !$0.anomalies.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    moveDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }

                DatePicker("日期", selection: $date, displayedComponents: .date)
                    .labelsHidden()

                Button {
                    moveDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }

                Spacer()

                if !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: timerMetrics.now) {
                    Button("今天") { date = timerMetrics.now }
                        .controlSize(.small)
                }
            }
            .padding(14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                Section("汇总") {
                    LabeledContent("记录", value: "\(displayedEntries.count) 条")
                    LabeledContent("累计工时", value: DurationTextFormatter.compact(totalDuration))
                    LabeledContent("实际经过", value: DurationTextFormatter.compact(wallClockDuration))
                }

                if !analysis.mergeSuggestions.isEmpty {
                    Section("合并建议") {
                        ForEach(analysis.mergeSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(suggestion.taskTitle)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)

                                Text("\(formattedTimeRange(start: suggestion.start, end: suggestion.end)) · \(suggestion.entryIDs.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button("合并这些记录") {
                                    DispatchQueue.main.async {
                                        onRequestMerge(suggestion)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if !anomalousItems.isEmpty {
                    Section("需要留意") {
                        ForEach(anomalousItems) { item in
                            if let entry = entries.first(where: { $0.id == item.entryID }) {
                                Button {
                                    let entryID = entry.id
                                    DispatchQueue.main.async {
                                        onEdit(entryID)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.task?.title ?? "未分配任务")
                                            .font(.body.weight(.medium))
                                            .lineLimit(2)
                                        Text(formattedTimeRange(start: entry.startAt, end: entry.endAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        anomalyPills(item.anomalies)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("当日记录") {
                    if displayedEntries.isEmpty {
                        Text("这一天没有计时记录")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(displayedEntries) { entry in
                        Button {
                            let entryID = entry.id
                            DispatchQueue.main.async {
                                onEdit(entryID)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.task?.title ?? "未分配任务")
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
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
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func anomalyPills(_ anomalies: Set<TimelineAnomaly>) -> some View {
        HStack(spacing: 5) {
            ForEach(TimelineAnomaly.allCases.filter(anomalies.contains), id: \.self) { anomaly in
                Text(anomaly.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(anomaly.tint.opacity(0.16), in: Capsule())
                    .foregroundStyle(anomaly.tint)
            }
        }
    }

    private func moveDay(by value: Int) {
        date = Calendar.autoupdatingCurrent.date(byAdding: .day, value: value, to: date) ?? date
    }
}

struct DailyTimelineView: View {
    @EnvironmentObject private var timerMetrics: TimerMetrics
    let date: Date
    let entries: [TimeEntry]
    let workflowService: TimelineWorkflowService
    let onEdit: (UUID) -> Void

    private let hourHeight: CGFloat = 72
    private let labelWidth: CGFloat = 58
    private let laneSpacing: CGFloat = 6

    private var dayStart: Date {
        Calendar.autoupdatingCurrent.startOfDay(for: date)
    }

    private var analysis: TimelineDayAnalysis {
        workflowService.analyze(day: date, entries: entries, now: timerMetrics.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(date.shortDateText())
                        .font(.title2.weight(.semibold))
                    Text("24 小时时间轴")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !analysis.items.isEmpty {
                    Label("\(analysis.items.count) 条记录", systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if analysis.items.isEmpty {
                EmptyStateView(
                    title: "这一天没有记录",
                    message: "切换日期查看其他时间轴，或从菜单栏开始一个任务。",
                    systemImage: "calendar.day.timeline.left"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        GeometryReader { geometry in
                            timeline(in: geometry.size.width)
                        }
                        .frame(height: hourHeight * 24)
                    }
                    .onAppear {
                        let firstHour = max(0, Calendar.autoupdatingCurrent.component(.hour, from: analysis.items[0].start) - 1)
                        proxy.scrollTo(firstHour, anchor: .top)
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    private func timeline(in width: CGFloat) -> some View {
        let availableWidth = max(200, width - labelWidth - 24)

        return ZStack(alignment: .topLeading) {
            ForEach(0...24, id: \.self) { hour in
                HStack(spacing: 8) {
                    Text(hour == 24 ? "24:00" : String(format: "%02d:00", hour))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth - 10, alignment: .trailing)

                    Rectangle()
                        .fill(.white.opacity(hour.isMultiple(of: 6) ? 0.16 : 0.08))
                        .frame(height: 1)
                }
                .frame(width: width - 8)
                .offset(y: CGFloat(hour) * hourHeight)
                .id(hour)
            }

            ForEach(analysis.items) { item in
                if let entry = entries.first(where: { $0.id == item.entryID }) {
                    timelineBlock(entry: entry, item: item, availableWidth: availableWidth)
                }
            }

            if Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: timerMetrics.now) {
                let y = yOffset(for: timerMetrics.now)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hexString: PaletteColor.coral.rawValue))
                        .frame(width: 7, height: 7)
                    Rectangle()
                        .fill(Color(hexString: PaletteColor.coral.rawValue))
                        .frame(height: 1)
                }
                .frame(width: availableWidth + 8)
                .offset(x: labelWidth, y: y)
            }
        }
    }

    private func timelineBlock(entry: TimeEntry, item: TimelineItem, availableWidth: CGFloat) -> some View {
        let laneCount = max(1, item.laneCount)
        let totalSpacing = CGFloat(laneCount - 1) * laneSpacing
        let laneWidth = max(72, (availableWidth - totalSpacing) / CGFloat(laneCount))
        let x = labelWidth + CGFloat(item.laneIndex) * (laneWidth + laneSpacing)
        let naturalHeight = item.end.timeIntervalSince(item.start) / 3_600 * hourHeight
        let height = max(10, naturalHeight)
        let color = Color(hexString: entry.task?.project?.colorHex ?? PaletteColor.sky.rawValue)

        return Button {
            onEdit(entry.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if height >= 28 {
                    HStack(spacing: 4) {
                        Text(entry.task?.title ?? "未分配任务")
                            .font(.caption.weight(.semibold))
                            .lineLimit(height >= 48 ? 2 : 1)
                        if !item.anomalies.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(hexString: PaletteColor.lemon.rawValue))
                        }
                    }
                    if height >= 50 {
                        Text(formattedTimeRange(start: item.start, end: item.end))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, height >= 28 ? 6 : 0)
            .frame(width: laneWidth, height: height, alignment: .topLeading)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.75), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(entry.task?.title ?? "未分配任务") · \(formattedTimeRange(start: item.start, end: item.end))")
        .offset(x: x, y: yOffset(for: item.start))
    }

    private func yOffset(for date: Date) -> CGFloat {
        max(0, date.timeIntervalSince(dayStart) / 3_600 * hourHeight)
    }
}

private extension TimelineAnomaly {
    var title: String {
        switch self {
        case .short: "不足 1 分钟"
        case .long: "超过 4 小时"
        case .overlapping: "时间重叠"
        case .crossesMidnight: "跨午夜"
        }
    }

    var tint: Color {
        switch self {
        case .short: Color(hexString: PaletteColor.slate.rawValue)
        case .long: Color(hexString: PaletteColor.lemon.rawValue)
        case .overlapping: Color(hexString: PaletteColor.coral.rawValue)
        case .crossesMidnight: Color(hexString: PaletteColor.lilac.rawValue)
        }
    }
}
