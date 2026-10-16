import SwiftUI

public struct UsageStatsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var usageData: UsageData? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    // 热力图区间选择状态：1击起始，2击截止，3击清空
    @State private var selAnchorDate: String? = nil
    @State private var selEndDate: String? = nil

    // 选中时段查看详情
    @State private var selectedHour: Int? = nil

    // 是否显示返回按钮（在非嵌入模式下提供退出）
    public var showBackButton: Bool = false
    public var onBack: (() -> Void)? = nil

    private let heatWeeks = 20
    private let heatBands: [Int64] = [10_000_000, 50_000_000, 100_000_000, 500_000_000, 1_000_000_000, 1_500_000_000, 2_000_000_000]

    public init(showBackButton: Bool = false, onBack: (() -> Void)? = nil) {
        self.showBackButton = showBackButton
        self.onBack = onBack
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.md) {
                // 顶部操作栏
                topHeaderBar

                if let err = errorMessage, usageData == nil {
                    errorStateView(err)
                } else if let data = usageData {
                    // 1. 第一位：热力图（全局时间控制器，右侧顶到边，指示器在右上角上方）
                    heatmapCard(data: data)

                    // 2. 第二位：24小时分时段消耗（紧贴热力图，随时间联动）
                    hourlyCard(data: data)

                    // 3. 第三位：核心数据指标总览（随时间联动）
                    let summary = computeSummary(data: data)
                    summaryGrid(summary: summary)

                    // 4. 第四位：项目用量（左边排序明细 + 右边圆环图）
                    projectsDonutCard(data: data)

                    // 5. 第五位：分工具用量（原生圆环图）
                    toolsDonutChartCard(data: data)
                } else {
                    loadingStateView
                }
            }
            .padding(.bottom, 32)
        }
        .background(DesignTokens.Colors.background)
        .refreshable {
            await loadUsage(force: true)
        }
        .task {
            await loadUsage(force: false)
        }
    }

    // MARK: - 顶部导航条
    private var topHeaderBar: some View {
        HStack {
            if showBackButton {
                Button {
                    DesignTokens.Haptics.light()
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(DesignTokens.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .buttonStyle(.plain)
            }

            Text("用量统计")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            if let sel = currentSelectedRangeString {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text(sel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(DesignTokens.Colors.morandiPurple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignTokens.Colors.morandiPurple.opacity(0.18))
                .clipShape(Capsule())
            }

            Spacer()

            Button {
                DesignTokens.Haptics.medium()
                Task { await loadUsage(force: true) }
            } label: {
                HStack(spacing: 4) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("刷新")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DesignTokens.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.sm)
    }

    // MARK: - 1. 顶层热力图（右上角上方放色阶指示器，网格自适应撑满卡片右侧，时间选择器）
    private func heatmapCard(data: UsageData) -> some View {
        let dailyMap = buildDailyMap(data: data)
        let (_, cells) = generateCalendarCells(dailyMap: dailyMap)

        return VStack(alignment: .leading, spacing: 10) {
            // 第一行：左边标题，右上角上方放置色阶指示器，绝不挤压下方网格，无废话副标题
            HStack(alignment: .center) {
                Text("用量热力图")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                // 色阶指示器：少 到 多（放在右上角上方）
                HStack(spacing: 3) {
                    Text("少")
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    ForEach(1...7, id: \.self) { lvl in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(heatColor(for: lvl))
                            .frame(width: 8, height: 8)
                    }
                    Text("多")
                        .font(.system(size: 9))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                }
            }

            // 下方热力图网格：彻底撑满可用宽度，严丝合缝顶到卡片右边缘
            GeometryReader { geo in
                let totalWidth = geo.size.width
                let weekdayWidth: CGFloat = 16
                let spacing: CGFloat = 2.5
                let availWidth = max(totalWidth - weekdayWidth, 200)
                let colWidth = max(floor((availWidth - CGFloat(heatWeeks - 1) * spacing) / CGFloat(heatWeeks)), 10)

                HStack(alignment: .top, spacing: 4) {
                    // 星期标尺（一、三、五）
                    VStack(spacing: spacing) {
                        let wds = ["", "一", "", "三", "", "五", ""]
                        ForEach(0..<7, id: \.self) { idx in
                            Text(wds[idx])
                                .font(.system(size: 8))
                                .foregroundColor(DesignTokens.Colors.textSecondary)
                                .frame(width: 12, height: colWidth)
                        }
                    }

                    // 热力图网格与月份刻度
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: spacing) {
                            ForEach(0..<heatWeeks, id: \.self) { col in
                                VStack(spacing: spacing) {
                                    ForEach(0..<7, id: \.self) { row in
                                        let idx = col * 7 + row
                                        if idx < cells.count {
                                            let cell = cells[idx]
                                            let isSelected = isDateSelected(cell.date)
                                            RoundedRectangle(cornerRadius: 4.5)
                                                .fill(heatColor(for: cell.level))
                                                .frame(width: colWidth, height: colWidth)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4.5)
                                                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
                                                )
                                                .onTapGesture {
                                                    DesignTokens.Haptics.selection()
                                                    handleDateTap(cell.date)
                                                }
                                        }
                                    }
                                }
                            }
                        }

                        // 下方月份轴
                        HStack(spacing: spacing) {
                            ForEach(0..<heatWeeks, id: \.self) { col in
                                let idx = col * 7
                                let label = (idx < cells.count) ? cells[idx].monthLabel : ""
                                Text(label)
                                    .font(.system(size: 8))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)
                                    .frame(width: colWidth, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * 11 + 6 * 2.5 + 16)
        }
        .padding(14)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 2. 24小时分时段柱图（紧随热力图）
    private func hourlyCard(data: UsageData) -> some View {
        let hoursData = computeHourlyBars(data: data)
        let maxVal = max(hoursData.map { $0.total ?? 0 }.max() ?? 1, 1)
        let chartHeight: CGFloat = 76

        let titleStr: String = {
            if let sel = currentSelectedRangeString {
                return "分时段 · \(sel)"
            }
            let today = formatDate(Date())
            return "分时段 · \(String(today.dropFirst(5)))"
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titleStr)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                if let sh = selectedHour {
                    let hItem = hoursData.first { $0.hour == sh }
                    let tot = hItem?.total ?? 0
                    Text("\(sh)时: \(AggregatedUsageSummary.formatCompactTokens(tot))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.morandiPurple)
                }
            }

            // 24小时柱状图（严格贴底对齐）
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(hoursData) { item in
                        let val = item.total ?? 0
                        let pct = val > 0 ? max(0.06, CGFloat(val) / CGFloat(maxVal)) : 0.0
                        let isSel = selectedHour == item.hour
                        let barHeight = max(3, chartHeight * pct)

                        ZStack(alignment: .bottom) {
                            // 全高度透明点击热区（76pt 高度，保证任意柱子皆可整列点击）
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: chartHeight)

                            // 贴底生长的柱子实体（顶部圆润大圆角，底部纯平齐线，100% 底部贴齐）
                            UnevenRoundedRectangle(
                                topLeadingRadius: 5.5,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 5.5
                            )
                            .fill(
                                isSel
                                ? DesignTokens.Colors.morandiGold
                                : (val > 0 ? DesignTokens.Colors.morandiPurple : DesignTokens.Colors.heat0)
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: chartHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DesignTokens.Haptics.selection()
                            if selectedHour == item.hour {
                                selectedHour = nil
                            } else {
                                selectedHour = item.hour
                            }
                        }
                    }
                }
                .frame(height: chartHeight)

                // 底部基线（严格水平标尺）
                Rectangle()
                    .fill(Color(white: 0.18))
                    .frame(height: 1)

                // 底部刻度（0, 3, 6, 9... 间距 3 与上方柱子严格 1:1 对齐）
                HStack(spacing: 3) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 3 == 0 ? "\(h)" : "")
                            .font(.system(size: 8))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(14)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 3. 核心指标总览网格（承接在图表之后）
    private func summaryGrid(summary: AggregatedUsageSummary) -> some View {
        let items: [(String, String, String)] = [
            ("总 Tokens", AggregatedUsageSummary.formatCompactTokens(summary.total), "\(AggregatedUsageSummary.formatDelimitedNumber(summary.total))"),
            ("毛输入", AggregatedUsageSummary.formatCompactTokens(summary.totalInput), "已含缓存命中"),
            ("新增输入", AggregatedUsageSummary.formatCompactTokens(summary.freshInput), "首次读入"),
            ("缓存命中", AggregatedUsageSummary.formatCompactTokens(summary.totalCacheRead), "重复读取"),
            ("缓存命中率", summary.cacheHitRateString, "缓存读 ÷ 毛输入"),
            ("输出 Tokens", AggregatedUsageSummary.formatCompactTokens(summary.totalOutput), "模型生成"),
            ("对话轮次", "\(AggregatedUsageSummary.formatDelimitedNumber(summary.totalTurns)) 轮", "用户对话"),
            ("模型调用", "\(AggregatedUsageSummary.formatDelimitedNumber(summary.totalCalls)) 次", "实际请求")
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignTokens.Colors.textSecondary)
                    Text(item.1)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DesignTokens.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 4. 项目用量：左边排序明细 + 右边圆环图 (Donut Ring Chart)
    private func projectsDonutCard(data: UsageData) -> some View {
        let projects = computeProjects(data: data)
        let total = max(projects.reduce(0) { $0 + ($1.total ?? 0) }, 1)
        let topProjects = Array(projects.prefix(5))
        let chartItems = topProjects.map { p -> (name: String, color: Color, total: Int64) in
            (name: p.name, color: projectColor(name: p.name), total: p.total ?? 0)
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("项目用量")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            if projects.isEmpty {
                Text("暂无项目数据")
                    .font(.system(size: 12))
                    .foregroundColor(DesignTokens.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    // 左边：从多到少排序的项目列表
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(topProjects, id: \.name) { p in
                            let pTot = p.total ?? 0
                            let share = Double(pTot) / Double(total) * 100.0

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(projectColor(name: p.name))
                                    .frame(width: 7, height: 7)

                                Text(p.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                Spacer()

                                Text(String(format: "%.0f%%", share))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(DesignTokens.Colors.textSecondary)

                                Text(AggregatedUsageSummary.formatCompactTokens(pTot))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 46, alignment: .trailing)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // 右边：圆环图（对齐参考截图：胶囊弧线、圆润端点、空隙间隔）
                    let donutItems = chartItems.map {
                        RoundedCapsuleDonutItem(name: $0.name, value: Double($0.total), color: $0.color)
                    }
                    RoundedCapsuleDonutChart(
                        items: donutItems,
                        size: 96,
                        strokeWidth: 15,
                        centerLabel: "项目总计",
                        centerValue: AggregatedUsageSummary.formatCompactTokens(total)
                    )
                    .padding(4)
                }
            }
        }
        .padding(14)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    // MARK: - 5. 分工具用量：原生圆环图 (Donut Ring Chart)
    private func toolsDonutChartCard(data: UsageData) -> some View {
        let tools = data.tools ?? [:]
        let toolMeta: [(String, String, Color)] = [
            ("antigravity", "Antigravity", DesignTokens.Colors.morandiPurple),
            ("workbuddy", "WorkBuddy", DesignTokens.Colors.morandiGreen),
            ("codex", "CodeX", DesignTokens.Colors.morandiBlue),
            ("claude_code", "Claude Code", DesignTokens.Colors.morandiGold),
        ]

        let toolItems = toolMeta.map { item -> (key: String, name: String, color: Color, total: Int64, cache: Int64, input: Int64, calls: Int64) in
            let t = tools[item.0]
            return (
                key: item.0,
                name: item.1,
                color: item.2,
                total: t?.total ?? 0,
                cache: t?.totalCacheRead ?? 0,
                input: t?.totalInput ?? 0,
                calls: t?.totalCalls ?? 0
            )
        }
        let totalUsage = max(toolItems.reduce(0) { $0 + $1.total }, 1)

        return VStack(alignment: .leading, spacing: 12) {
            Text("分工具用量")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)

            HStack(spacing: 20) {
                // 原生圆环图（Donut Ring）
                // 原生圆环图（对齐参考截图：胶囊弧线、圆润端点、空隙间隔）
                let donutItems = toolItems.map {
                    RoundedCapsuleDonutItem(name: $0.name, value: Double($0.total), color: $0.color)
                }
                RoundedCapsuleDonutChart(
                    items: donutItems,
                    size: 104,
                    strokeWidth: 16,
                    centerLabel: "总消耗",
                    centerValue: AggregatedUsageSummary.formatCompactTokens(totalUsage)
                )
                .padding(4)

                // 右侧图例与各自缓存命中率
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(toolItems, id: \.key) { item in
                        let rate = item.input > 0 ? String(format: "%.1f%%", Double(item.cache) / Double(item.input) * 100.0) : "0.0%"

                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 7, height: 7)

                            Text(item.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer()

                            Text("缓存: \(rate)")
                                .font(.system(size: 10))
                                .foregroundColor(DesignTokens.Colors.textSecondary)

                            Text(AggregatedUsageSummary.formatCompactTokens(item.total))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(14)
        .background(DesignTokens.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private func fractionBefore(index: Int, items: [(key: String, name: String, color: Color, total: Int64, cache: Int64, input: Int64, calls: Int64)], total: Int64) -> Double {
        var sum: Int64 = 0
        for i in 0..<index {
            sum += items[i].total
        }
        return Double(sum) / Double(total)
    }

    private func projectFractionBefore(index: Int, items: [(name: String, color: Color, total: Int64)], total: Int64) -> Double {
        var sum: Int64 = 0
        for i in 0..<index {
            sum += items[i].total
        }
        return Double(sum) / Double(total)
    }

    // MARK: - 辅助计算与交互逻辑
    private func loadUsage(force: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            let res = try await APIService.shared.fetchUsageStats(force: force)
            self.usageData = res
            self.isLoading = false
        } catch {
            self.errorMessage = "加载失败: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    private var currentSelectedRangeString: String? {
        guard let a = selAnchorDate else { return nil }
        if let b = selEndDate, b != a {
            let lo = min(a, b)
            let hi = max(a, b)
            return "\(String(lo.dropFirst(5))) ~ \(String(hi.dropFirst(5)))"
        }
        return "\(String(a.dropFirst(5)))"
    }

    private func isDateSelected(_ date: String) -> Bool {
        guard let a = selAnchorDate else { return false }
        if let b = selEndDate {
            let lo = min(a, b)
            let hi = max(a, b)
            return date >= lo && date <= hi
        }
        return date == a
    }

    private func handleDateTap(_ date: String) {
        if selAnchorDate != nil && selEndDate != nil {
            // 第3下：清空恢复全期
            selAnchorDate = nil
            selEndDate = nil
        } else if selAnchorDate == nil {
            // 第1下：选定起始日
            selAnchorDate = date
            selEndDate = nil
        } else {
            // 第2下：选定截止日（可为同一天）
            selEndDate = date
        }
    }

    private func computeSummary(data: UsageData) -> AggregatedUsageSummary {
        var s = AggregatedUsageSummary()
        let tools = data.tools ?? [:]

        // 选定区间筛选
        if let a = selAnchorDate {
            let b = selEndDate ?? a
            let lo = min(a, b)
            let hi = max(a, b)

            for (_, t) in tools where t.available {
                for d in t.daily ?? [] where d.date >= lo && d.date <= hi {
                    s.total += d.total ?? 0
                    s.totalCalls += d.calls ?? 0
                    s.totalTurns += d.turns ?? 0
                    s.totalInput += d.input ?? 0
                    s.totalOutput += d.output ?? 0
                    s.totalCacheRead += d.cacheRead ?? 0
                    s.totalCacheWrite += d.cacheWrite ?? 0
                }
            }
            return s
        }

        // 全期汇总
        for (_, t) in tools where t.available {
            s.total += t.total ?? 0
            s.totalInput += t.totalInput ?? 0
            s.totalOutput += t.totalOutput ?? 0
            s.totalCacheRead += t.totalCacheRead ?? 0
            s.totalCacheWrite += t.totalCacheWrite ?? 0
            s.totalCalls += t.totalCalls ?? 0
            s.totalTurns += t.totalTurns ?? 0
        }
        return s
    }

    private func computeHourlyBars(data: UsageData) -> [HourlyUsageItem] {
        var hours: [Int: (total: Int64, calls: Int64, turns: Int64)] = [:]
        for h in 0..<24 { hours[h] = (0, 0, 0) }

        let tools = data.tools ?? [:]
        let targetDates: Set<String>

        if let a = selAnchorDate {
            let b = selEndDate ?? a
            let lo = min(a, b)
            let hi = max(a, b)
            var datesInRange = Set<String>()
            for (_, t) in tools where t.available {
                for d in t.daily ?? [] where d.date >= lo && d.date <= hi {
                    datesInRange.insert(d.date)
                }
            }
            targetDates = datesInRange
        } else {
            targetDates = [formatDate(Date())]
        }

        for (_, t) in tools where t.available {
            for d in t.daily ?? [] where targetDates.contains(d.date) {
                for h in d.hourly ?? [] {
                    if h.hour >= 0 && h.hour < 24 {
                        let cur = hours[h.hour] ?? (0, 0, 0)
                        hours[h.hour] = (cur.total + (h.total ?? 0), cur.calls + (h.calls ?? 0), cur.turns + (h.turns ?? 0))
                    }
                }
            }
        }

        // 如果未指定历史区间（默认展示今天），则当前小时之后的未来时段强制置零，绝不展示未来假数据
        if selAnchorDate == nil {
            let curHour = Calendar.current.component(.hour, from: Date())
            for h in (curHour + 1)..<24 {
                hours[h] = (0, 0, 0)
            }
        }

        return (0..<24).map { h in
            let v = hours[h] ?? (0, 0, 0)
            return HourlyUsageItem(hour: h, total: v.total, calls: v.calls, turns: v.turns)
        }
    }

    private func computeProjects(data: UsageData) -> [ProjectUsageItem] {
        if let a = selAnchorDate {
            let b = selEndDate ?? a
            let lo = min(a, b)
            let hi = max(a, b)
            var pmap: [String: Int64] = [:]
            for (_, t) in data.tools ?? [:] where t.available {
                for d in t.daily ?? [] where d.date >= lo && d.date <= hi {
                    for (pName, pVal) in d.projects ?? [:] {
                        pmap[pName] = (pmap[pName] ?? 0) + (pVal.total ?? 0)
                    }
                }
            }
            return pmap.map { ProjectUsageItem(name: $0.key, path: nil, total: $0.value, input: nil, output: nil, cacheRead: nil, calls: nil) }
                .sorted { ($0.total ?? 0) > ($1.total ?? 0) }
        }
        return (data.projects ?? []).sorted { ($0.total ?? 0) > ($1.total ?? 0) }
    }

    private struct HeatCell {
        let date: String
        let level: Int
        let monthLabel: String
    }

    private func buildDailyMap(data: UsageData) -> [String: Int64] {
        var map: [String: Int64] = [:]
        for (_, t) in data.tools ?? [:] where t.available {
            for d in t.daily ?? [] {
                map[d.date] = (map[d.date] ?? 0) + (d.total ?? 0)
            }
        }
        return map
    }

    private func generateCalendarCells(dailyMap: [String: Int64]) -> (Date, [HeatCell]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = weekday - 1
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromSunday, to: today),
              let start = calendar.date(byAdding: .day, value: -(heatWeeks - 1) * 7, to: weekStart) else {
            return (Date(), [])
        }

        var cells: [HeatCell] = []
        var lastMonth = -1

        for i in 0..<(heatWeeks * 7) {
            if let d = calendar.date(byAdding: .day, value: i, to: start) {
                let ds = formatDate(d)
                let val = dailyMap[ds] ?? 0
                let lvl = levelFor(val)
                let m = calendar.component(.month, from: d)
                let mLabel = (i % 7 == 0 && m != lastMonth) ? "\(m)月" : ""
                if i % 7 == 0 && m != lastMonth {
                    lastMonth = m
                }
                cells.append(HeatCell(date: ds, level: lvl, monthLabel: mLabel))
            }
        }
        return (start, cells)
    }

    private func levelFor(_ v: Int64) -> Int {
        guard v > 0 else { return 0 }
        if v < heatBands[0] { return 0 }
        if v < heatBands[1] { return 1 }
        if v < heatBands[2] { return 2 }
        if v < heatBands[3] { return 3 }
        if v < heatBands[4] { return 4 }
        if v < heatBands[5] { return 5 }
        if v < heatBands[6] { return 6 }
        return 7
    }

    private func heatColor(for level: Int) -> Color {
        switch level {
        case 1: return DesignTokens.Colors.heat1
        case 2: return DesignTokens.Colors.heat2
        case 3: return DesignTokens.Colors.heat3
        case 4: return DesignTokens.Colors.heat4
        case 5: return DesignTokens.Colors.heat5
        case 6: return DesignTokens.Colors.heat6
        case 7: return DesignTokens.Colors.heat7
        default: return DesignTokens.Colors.heat0
        }
    }

    private func projectColor(name: String) -> Color {
        switch name {
        case "盒宝HéBot": return DesignTokens.Colors.morandiPurple
        case "其它": return DesignTokens.Colors.morandiGreen
        case "工作台": return DesignTokens.Colors.morandiBlue
        case "花少模拟器": return DesignTokens.Colors.morandiGold
        case "iFrigo": return DesignTokens.Colors.morandiRose
        case "watch": return DesignTokens.Colors.morandiMauve
        default: return DesignTokens.Colors.morandiGray
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func errorStateView(_ err: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(DesignTokens.Colors.danger)
            Text(err)
                .font(.system(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
            Button("重试") {
                Task { await loadUsage(force: true) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(DesignTokens.Colors.accent)
            .clipShape(Capsule())
        }
        .padding(32)
    }

    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("正在拉取一手用量数据…")
                .font(.system(size: 13))
                .foregroundColor(DesignTokens.Colors.textSecondary)
        }
        .padding(48)
    }
}

// MARK: - 原生圆润胶囊圆环图组件（对齐用户参考截图）
public struct RoundedCapsuleDonutItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let value: Double
    public let color: Color

    public init(name: String, value: Double, color: Color) {
        self.name = name
        self.value = value
        self.color = color
    }
}

public struct RoundedCapsuleDonutChart: View {
    public let items: [RoundedCapsuleDonutItem]
    public var size: CGFloat = 96
    public var strokeWidth: CGFloat = 14
    public var centerLabel: String = ""
    public var centerValue: String = ""

    public init(
        items: [RoundedCapsuleDonutItem],
        size: CGFloat = 96,
        strokeWidth: CGFloat = 14,
        centerLabel: String = "",
        centerValue: String = ""
    ) {
        self.items = items
        self.size = size
        self.strokeWidth = strokeWidth
        self.centerLabel = centerLabel
        self.centerValue = centerValue
    }

    public var body: some View {
        let validItems = items.filter { $0.value > 0 }
        let total = validItems.reduce(0.0) { $0 + $1.value }
        let radius = max((size - strokeWidth) / 2.0, 10.0)
        let capAngle = Double((strokeWidth / 2.0) / radius * (180.0 / .pi))
        let visibleGapDeg: Double = 6.0
        let n = max(validItems.count, 1)

        let centerGap = (2.0 * capAngle) + visibleGapDeg
        let totalGaps = Double(n) * centerGap
        let arcBudget = max(360.0 - totalGaps, 60.0)

        ZStack {
            if validItems.isEmpty || total <= 0 {
                Circle()
                    .stroke(Color(white: 0.18), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .frame(width: size - strokeWidth, height: size - strokeWidth)
            } else {
                let segments = computeSegments(items: validItems, total: total, arcBudget: arcBudget, centerGap: centerGap)
                ForEach(segments) { seg in
                    Circle()
                        .trim(from: CGFloat(seg.startFraction), to: CGFloat(seg.endFraction))
                        .stroke(seg.color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size - strokeWidth, height: size - strokeWidth)
                }
            }

            if !centerValue.isEmpty {
                VStack(spacing: 2) {
                    if !centerLabel.isEmpty {
                        Text(centerLabel)
                            .font(.system(size: 9))
                            .foregroundColor(DesignTokens.Colors.textSecondary)
                    }
                    Text(centerValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private struct Segment: Identifiable {
        let id = UUID()
        let startFraction: Double
        let endFraction: Double
        let color: Color
    }

    private func computeSegments(
        items: [RoundedCapsuleDonutItem],
        total: Double,
        arcBudget: Double,
        centerGap: Double
    ) -> [Segment] {
        var segs: [Segment] = []
        var curAngle = 0.0

        for item in items {
            let share = item.value / total
            let span = max(share * arcBudget, 0.5)
            let startFrac = curAngle / 360.0
            let endFrac = (curAngle + span) / 360.0
            segs.append(Segment(startFraction: startFrac, endFraction: endFrac, color: item.color))
            curAngle += span + centerGap
        }
        return segs
    }
}
