import SwiftUI
import Charts
import AppKit

private struct CompareMetricRow: Identifiable {
    let id = UUID()
    let name: String
    let unit: String
    let leftValue: Double
    let rightValue: Double
    let lowerIsBetter: Bool

    var deltaPercent: Double {
        guard leftValue > 0 else { return 0 }
        return ((rightValue - leftValue) / leftValue) * 100
    }

    var trendText: String {
        if leftValue == 0 {
            if rightValue == 0 { return "1.00x" }
            return "∞x"
        }
        return String(format: "%.2fx", rightValue / leftValue)
    }

    var trendColor: Color {
        if lowerIsBetter {
            return deltaPercent <= 0 ? .green : .red
        }
        return deltaPercent >= 0 ? .green : .red
    }

    var improvementMultiple: Double {
        if lowerIsBetter {
            if rightValue == 0 {
                return leftValue == 0 ? 1.0 : .infinity
            }
            return leftValue / rightValue
        }

        if leftValue == 0 {
            return rightValue == 0 ? 1.0 : .infinity
        }
        return rightValue / leftValue
    }
}

private struct CompareBarPoint: Identifiable {
    let id = UUID()
    let metric: String
    let series: String
    let value: Double
    let rawValue: Double
}

private struct CompareLinePoint: Identifiable {
    let id = UUID()
    let second: Int
    let value: Double
    let series: String
}

struct BenchmarkComparisonView: View {
    let report: BenchmarkComparisonReport
    @State private var exportStatus: String = ""
    @State private var showDetailedRows: Bool = false

    private var metrics: [CompareMetricRow] {
        [
            CompareMetricRow(name: "Small-file Create", unit: "Files/Sec", leftValue: report.left.createFilesPerSec, rightValue: report.right.createFilesPerSec, lowerIsBetter: false),
            CompareMetricRow(name: "Folder Scan Throughput", unit: "files/s", leftValue: report.left.traversalFilesPerSec, rightValue: report.right.traversalFilesPerSec, lowerIsBetter: false),
            CompareMetricRow(name: "File Edit", unit: "ops/s", leftValue: report.left.fileEditOpsPerSec, rightValue: report.right.fileEditOpsPerSec, lowerIsBetter: false),
            CompareMetricRow(name: "Random Write IOPS", unit: "IOPS", leftValue: report.left.randomOptionIOPS, rightValue: report.right.randomOptionIOPS, lowerIsBetter: false),
            CompareMetricRow(name: "Metadata Create", unit: "ops/s", leftValue: report.left.metadataCreateOpsPerSec, rightValue: report.right.metadataCreateOpsPerSec, lowerIsBetter: false),
            CompareMetricRow(name: "Interactive Score", unit: "score", leftValue: report.left.interactiveScore, rightValue: report.right.interactiveScore, lowerIsBetter: false),
            CompareMetricRow(name: "Media Score", unit: "score", leftValue: report.left.mediaScore, rightValue: report.right.mediaScore, lowerIsBetter: false)
        ]
        .sorted {
            if $0.improvementMultiple == $1.improvementMultiple {
                return $0.name < $1.name
            }
            return $0.improvementMultiple > $1.improvementMultiple
        }
    }

    private var barPoints: [CompareBarPoint] {
        metrics.flatMap { metric in
            let maxRaw = max(metric.leftValue, metric.rightValue)
            let leftNormalized = maxRaw > 0 ? (metric.leftValue / maxRaw) * 100 : 0
            let rightNormalized = maxRaw > 0 ? (metric.rightValue / maxRaw) * 100 : 0
            return [
                CompareBarPoint(metric: metric.name, series: report.leftLabel, value: leftNormalized, rawValue: metric.leftValue),
                CompareBarPoint(metric: metric.name, series: report.rightLabel, value: rightNormalized, rawValue: metric.rightValue)
            ]
        }
    }

    private struct MetricTrendItem: Identifiable {
        let id = UUID()
        let name: String
        let leftValue: Double
        let rightValue: Double
        let leftNormalized: Double
        let rightNormalized: Double
        let multipleText: String
        let color: Color
    }

    private var metricTrendItems: [MetricTrendItem] {
        metrics.map { metric in
            let maxRaw = max(metric.leftValue, metric.rightValue)
            let leftNormalized = maxRaw > 0 ? (metric.leftValue / maxRaw) * 100 : 0
            let rightNormalized = maxRaw > 0 ? (metric.rightValue / maxRaw) * 100 : 0
            let multipleText: String = {
                if metric.leftValue == 0 {
                    if metric.rightValue == 0 { return "1.00x" }
                    return "∞x"
                }
                return String(format: "%.2fx", metric.rightValue / metric.leftValue)
            }()

            return MetricTrendItem(
                name: metric.name,
                leftValue: metric.leftValue,
                rightValue: metric.rightValue,
                leftNormalized: leftNormalized,
                rightNormalized: rightNormalized,
                multipleText: multipleText,
                color: metric.trendColor
            )
        }
    }

    private var linePoints: [CompareLinePoint] {
        let left = report.left.iopsSamples.map {
            CompareLinePoint(second: $0.second, value: $0.mixedIOPS, series: report.leftLabel)
        }
        let right = report.right.iopsSamples.map {
            CompareLinePoint(second: $0.second, value: $0.mixedIOPS, series: report.rightLabel)
        }
        return left + right
    }

    private var leftMixedIOPSMean: Double {
        meanMixedIOPS(report.left.iopsSamples)
    }

    private var rightMixedIOPSMean: Double {
        meanMixedIOPS(report.right.iopsSamples)
    }

    private var mixedIopsMultipleText: String {
        if leftMixedIOPSMean == 0 {
            if rightMixedIOPSMean == 0 { return "1.00x" }
            return "∞x"
        }
        return String(format: "%.2fx", rightMixedIOPSMean / leftMixedIOPSMean)
    }

    private var mixedIopsTrendColor: Color {
        if rightMixedIOPSMean > leftMixedIOPSMean { return .green }
        if rightMixedIOPSMean < leftMixedIOPSMean { return .red }
        return .secondary
    }

    private var topGainMetric: CompareMetricRow? {
        metrics.first
    }

    private var promoAccentYellow: Color { .yellow }
    private var promoBadgeFill: Color { promoAccentYellow.opacity(0.48) }
    private var promoBadgeStroke: Color { .orange.opacity(0.78) }
    private var promoBadgeShadow: Color { promoAccentYellow.opacity(0.4) }

    private func promoMultipleGradient(base: Color) -> LinearGradient {
        LinearGradient(
            colors: [base, base.opacity(0.78), promoAccentYellow],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func meanMixedIOPS(_ samples: [IOPSSample]) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.map(\.mixedIOPS).reduce(0, +) / Double(samples.count)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.28), .blue.opacity(0.2), .cyan.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    contentStack
                }
                .padding(20)
            }
        }
    }

    private var contentStack: some View {
        VStack(spacing: 14) {
            header
            topGainPanel
            heroMultiplierPanel
            scoreSummaryPanel
            comparisonCards
            barChartPanel
            lineChartPanel
        }
    }

    @ViewBuilder
    private var topGainPanel: some View {
        if let topGainMetric {
            HStack(spacing: 10) {
                Label("Top Gain", systemImage: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(promoBadgeFill, in: Capsule())
                    .overlay(
                        Capsule().stroke(promoBadgeStroke, lineWidth: 1)
                    )
                    .shadow(color: promoBadgeShadow, radius: 4, x: 0, y: 1)
                Text(topGainMetric.name)
                    .font(.headline)
                Spacer()
                Text(topGainMetric.trendText)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(promoMultipleGradient(base: topGainMetric.trendColor))
                    .shadow(color: topGainMetric.trendColor.opacity(0.28), radius: 2, x: 0, y: 1)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var heroMultiplierPanel: some View {
        HStack(spacing: 12) {
            heroMetricCard(title: "Interactive", multipleText: scoreMultipleText(left: report.left.interactiveScore, right: report.right.interactiveScore), trendColor: scoreTrendColor(left: report.left.interactiveScore, right: report.right.interactiveScore))
            heroMetricCard(title: "Media", multipleText: scoreMultipleText(left: report.left.mediaScore, right: report.right.mediaScore), trendColor: scoreTrendColor(left: report.left.mediaScore, right: report.right.mediaScore))
            heroMetricCard(title: "Mixed IOPS", multipleText: mixedIopsMultipleText, trendColor: mixedIopsTrendColor)
        }
    }

    private func heroMetricCard(title: String, multipleText: String, trendColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(multipleText)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(
                    title == "Mixed IOPS"
                    ? AnyShapeStyle(
                        promoMultipleGradient(base: trendColor)
                    )
                    : AnyShapeStyle(trendColor)
                )
                .shadow(color: title == "Mixed IOPS" ? trendColor.opacity(0.25) : .clear, radius: 2, x: 0, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("vs \(report.leftLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scoreMultipleText(left: Double, right: Double) -> String {
        if left == 0 {
            if right == 0 { return "1.00x" }
            return "∞x"
        }
        return String(format: "%.2fx", right / left)
    }

    private func scoreTrendColor(left: Double, right: Double) -> Color {
        if right > left { return .green }
        if right < left { return .red }
        return .secondary
    }

    private var scoreSummaryPanel: some View {
        HStack(spacing: 12) {
            scoreCard(
                title: "Interactive Score",
                leftValue: report.left.interactiveScore,
                rightValue: report.right.interactiveScore
            )
            scoreCard(
                title: "Media Score",
                leftValue: report.left.mediaScore,
                rightValue: report.right.mediaScore
            )
        }
    }

    private func scoreCard(title: String, leftValue: Double, rightValue: Double) -> some View {
        let delta = leftValue > 0 ? ((rightValue - leftValue) / leftValue) * 100 : 0
        let trendColor: Color = delta >= 0 ? .green : .red
        let multipleText: String = {
            if leftValue == 0 {
                if rightValue == 0 { return "1.00x" }
                return "∞x"
            }
            return String(format: "%.2fx", rightValue / leftValue)
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(spacing: 8) {
                Text(String(format: "%.1f", leftValue))
                    .font(.title3.bold())
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", rightValue))
                    .font(.title3.bold())
            }
            Text(multipleText)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(trendColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(report.rightLabel) VS \(report.leftLabel)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Compare current vs previous · one-click export for promo/blog")
                    .foregroundStyle(.secondary)
                Text("\(report.right.persona.title) VS \(report.left.persona.title) · \(report.right.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button {
                    exportStatus = SnapshotExporter.exportViewImageAutoSized(
                        comparisonSnapshotView,
                        width: 1240,
                        minHeight: 980,
                        maxHeight: 3200,
                        fileNamePrefix: "benchmark_comparison",
                        panelTitle: "Save Comparison Image"
                    )
                } label: {
                    Label("Export Comparison Image", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                if !exportStatus.isEmpty {
                    Text(exportStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var comparisonCards: some View {
        VStack(spacing: 10) {
            DisclosureGroup(isExpanded: $showDetailedRows) {
                VStack(spacing: 10) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        HStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Text(metric.name)
                                    .font(.headline)
                                if index == 0 {
                                    Text("Top Gain")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(promoBadgeFill, in: Capsule())
                                        .overlay(
                                            Capsule().stroke(promoBadgeStroke, lineWidth: 1)
                                        )
                                        .shadow(color: promoBadgeShadow, radius: 3, x: 0, y: 1)
                                }
                            }
                            .frame(width: 180, alignment: .leading)
                            Text(String(format: "%.1f %@", metric.leftValue, metric.unit))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("→")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f %@", metric.rightValue, metric.unit))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(metric.trendText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(metric.trendColor)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Label("Detailed Metric Rows", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Text(showDetailedRows ? "Collapse" : "Expand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var barChartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Core Metrics Bar Comparison", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Text("Per-metric normalized bars (0~100). Each metric includes a multiplier label.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(barPoints) { point in
                BarMark(
                    x: .value("Metric", point.metric),
                    y: .value("Normalized", point.value)
                )
                .position(by: .value("Version", point.series))
                .foregroundStyle(by: .value("Version", point.series))
                .cornerRadius(6)
                .annotation(position: .top) {
                    Text(String(format: "%.1f", point.rawValue))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...110)
            .chartForegroundStyleScale([
                report.leftLabel: Color.blue,
                report.rightLabel: Color.green
            ])
            .frame(height: 280)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plotFrame = geo[proxy.plotAreaFrame]
                    let metricCount = max(1, metricTrendItems.count)
                    let groupWidth = plotFrame.width / CGFloat(metricCount)

                    ZStack {
                        ForEach(Array(metricTrendItems.enumerated()), id: \.element.name) { index, item in
                            let centerX = plotFrame.minX + groupWidth * (CGFloat(index) + 0.5)
                            let barOffset = groupWidth * 0.17
                            let leftX = centerX - barOffset
                            let rightX = centerX + barOffset
                            let leftY = plotFrame.maxY - CGFloat(item.leftNormalized / 110.0) * plotFrame.height
                            let rightY = plotFrame.maxY - CGFloat(item.rightNormalized / 110.0) * plotFrame.height

                            let dx = rightX - leftX
                            let dy = rightY - leftY
                            let length = max(1, sqrt(dx * dx + dy * dy))
                            let ux = dx / length
                            let uy = dy / length
                            let nx = -uy
                            let ny = ux

                            let barHalfWidth: CGFloat = 9
                            let edgeGap: CGFloat = 7
                            let verticalLift: CGFloat = 12

                            let anchorStartX = leftX - barHalfWidth
                            let anchorStartY = leftY
                            let anchorEndX = rightX - barHalfWidth
                            let anchorEndY = rightY

                            let startX = anchorStartX + ux * edgeGap
                            let startY = anchorStartY + uy * edgeGap - verticalLift
                            let endX = anchorEndX - ux * edgeGap
                            let endY = anchorEndY - uy * edgeGap - verticalLift

                            let labelX = (startX + endX) / 2 + nx * 11
                            let labelY = (startY + endY) / 2 + ny * 11

                            Text(item.multipleText)
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(item.color.opacity(0.92), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(.white.opacity(0.95), lineWidth: 1.2)
                                )
                                .position(x: labelX, y: labelY)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lineChartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mixed IOPS Curve Comparison", systemImage: "chart.xyaxis.line")
                .font(.headline)

            if linePoints.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .overlay(Text("Sampling data unavailable. Complete two runs to show the curve."))
                    .frame(height: 260)
            } else {
                ZStack(alignment: .topTrailing) {
                    Chart(linePoints) { point in
                        LineMark(
                            x: .value("Second", point.second),
                            y: .value("IOPS", point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Version", point.series))
                    }
                    .chartForegroundStyleScale([
                        report.leftLabel: Color.blue,
                        report.rightLabel: Color.green
                    ])
                    .frame(height: 300)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Mixed IOPS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(mixedIopsMultipleText)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(mixedIopsTrendColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(8)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var comparisonSnapshotView: some View {
        VStack(spacing: 0) {
            contentStack
                .padding(20)
        }
        .frame(width: 1240, alignment: .top)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.28), .blue.opacity(0.2), .cyan.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

enum BenchmarkComparisonWindowPresenter {
    private static var windowControllers: [NSWindowController] = []

    @MainActor
    static func show(report: BenchmarkComparisonReport) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let horizontalPadding: CGFloat = 24
        let verticalPadding: CGFloat = 12
        let contentWidth = min(1240, max(900, visibleFrame.width - horizontalPadding))
        let contentHeight = max(700, visibleFrame.height - verticalPadding)
        let originX = visibleFrame.minX + (visibleFrame.width - contentWidth) / 2
        let originY = visibleFrame.minY + (visibleFrame.height - contentHeight) / 2

        let window = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(report.leftLabel) vs \(report.rightLabel)"
        window.contentView = NSHostingView(rootView: BenchmarkComparisonView(report: report))

        let controller = NSWindowController(window: window)
        windowControllers.append(controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            windowControllers.removeAll { $0 === controller }
        }
    }
}
