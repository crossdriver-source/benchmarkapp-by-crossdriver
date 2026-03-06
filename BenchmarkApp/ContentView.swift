import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var vm = BenchmarkViewModel()
    @State private var saveStatus = ""
    @State private var showCompareInput = false
    @State private var compareLeftLabel = ""
    @State private var compareRightLabel = ""

    private struct IOPSLinePoint: Identifiable {
        let id = UUID()
        let second: Int
        let value: Double
        let series: String
    }

    private var iopsLinePoints: [IOPSLinePoint] {
        vm.iopsSamples.flatMap { sample in
            [
                IOPSLinePoint(second: sample.second, value: sample.mixedIOPS, series: "Mixed IOPS"),
                IOPSLinePoint(second: sample.second, value: sample.readIOPS, series: "Read IOPS"),
                IOPSLinePoint(second: sample.second, value: sample.writeIOPS, series: "Write IOPS")
            ]
        }
    }

    private var scenarioFileCountText: String {
        let count = vm.selectedPersona == .codeEditor ? 100_000 : 10_000
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let countText = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(countText) small files created"
    }

    private var hasComparisonData: Bool {
        vm.previousSnapshot != nil && vm.latestSnapshot != nil
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.32), .blue.opacity(0.2), .cyan.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 360)
                .blur(radius: 20)
                .offset(x: 430, y: -300)

            Circle()
                .fill(.blue.opacity(0.10))
                .frame(width: 420)
                .blur(radius: 24)
                .offset(x: -460, y: 260)

            ScrollView {
                VStack(spacing: 16) {
                    header
                    configPanel
                    dashboardPanel
                    throughputPanel
                    curvePanel
                    logPanel
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(WindowConfigurator())
        .sheet(isPresented: $showCompareInput) {
            compareInputSheet
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Small-File IOPS Benchmark")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("\(vm.selectedPersona.title) Scenario · Small-file IOPS + Layered Throughput Analysis")
                    .foregroundStyle(.secondary)
            }
            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .foregroundStyle(.blue)
                Picker("Disk", selection: $vm.selectedVolumeID) {
                    ForEach(vm.mountedVolumes) { volume in
                        Text(volume.name).tag(volume.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: vm.selectedVolumeID) { _ in
                    vm.applySelectedVolume()
                }

                Button {
                    vm.refreshMountedVolumes()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())

            Button {
                vm.runAllBenchmarks()
            } label: {
                Label("Run All", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isRunning)

            Button {
                vm.cancel()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!vm.isRunning)

            Button {
                saveStatus = SnapshotExporter.exportCurrentWindow()
            } label: {
                Label("Save Snapshot", systemImage: "camera")
            }
            .buttonStyle(.borderedProminent)

            if hasComparisonData {
                Button {
                    compareLeftLabel = "Previous"
                    compareRightLabel = "Current"
                    showCompareInput = true
                } label: {
                    Label("Compare with Previous", systemImage: "chart.bar.xaxis")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    saveStatus = "⚠️ At least two completed runs are required to compare with the previous result"
                } label: {
                    Label("Compare with Previous", systemImage: "chart.bar.xaxis")
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text(vm.isRunning ? "RUNNING" : "IDLE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(vm.isRunning ? .green.opacity(0.2) : .secondary.opacity(0.18), in: Capsule())
                .padding(8)
        }
    }

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Benchmark Path", systemImage: "internaldrive")
                    .font(.headline)
                Text(vm.rootPath)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            if let selected = vm.mountedVolumes.first(where: { $0.id == vm.selectedVolumeID }) {
                Text("Target Volume: \(selected.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: vm.progress)
                .tint(.blue)
            Text(vm.progressText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Scenario")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Scenario", selection: $vm.selectedPersona) {
                    ForEach(BenchmarkPersona.allCases) { persona in
                        Text(persona.title).tag(persona)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: vm.selectedPersona) { _ in
                    vm.applyPersonaPreset()
                }
                .disabled(vm.isRunning)

                Text("Enabled Tests: \(vm.selectedPersona.enabledTestsDescription)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("Use atomic write for small-file create", isOn: $vm.useAtomicWriteForCreateTest)
                    .font(.caption)
                    .disabled(vm.isRunning)
            }

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    private var throughputPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sequential Throughput & Layered Report", systemImage: "speedometer")
                    .font(.headline)
                Spacer()
                Text(String(format: "Interactive %.1f / Media %.1f", vm.interactiveScore, vm.mediaScore))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if vm.throughputProfiles.isEmpty {
                Text("Sequential throughput is not enabled for the current scenario, or tests are not finished yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.throughputProfiles) { profile in
                    HStack(spacing: 10) {
                        Text(profile.sizeLabel)
                            .font(.subheadline.bold())
                            .frame(width: 56, alignment: .leading)
                        Text(String(format: "Cold R/W %.0f/%.0f MB/s", profile.coldReadMBps, profile.coldWriteMBps))
                            .font(.caption)
                        Text(String(format: "Warm R/W %.0f/%.0f MB/s", profile.warmReadMBps, profile.warmWriteMBps))
                            .font(.caption)
                        Text(String(format: "Median %.0f", profile.medianMBps))
                            .font(.caption)
                        Text(String(format: "P95 %.0f", profile.p95MBps))
                            .font(.caption)
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dashboardPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                dashboardCard(
                    title: "Small-file Create Speed",
                    subtitle: scenarioFileCountText,
                    icon: "doc.badge.plus",
                    value: vm.createFilesPerSec,
                    maxValue: max(2000, vm.createFilesPerSec * 1.2),
                    unit: "Files/Sec"
                )

                dashboardCard(
                    title: "Folder Scan Throughput",
                    subtitle: "scan full main dataset (10,000 or 100,000 files)",
                    icon: "folder.badge.questionmark",
                    value: vm.traversalFilesPerSec,
                    maxValue: max(2000, vm.traversalFilesPerSec * 1.2),
                    unit: "files/s"
                )

                dashboardCard(
                    title: "Metadata Create",
                    subtitle: "file metadata create/update ops",
                    icon: "tag",
                    value: vm.metadataCreateOpsPerSec,
                    maxValue: max(3000, vm.metadataCreateOpsPerSec * 1.2),
                    unit: "ops/s"
                )
            }

            HStack(spacing: 14) {
                dashboardCard(
                    title: "File Edit",
                    subtitle: "100MB / 4KB random edits",
                    icon: "pencil.and.outline",
                    value: vm.fileEditOpsPerSec,
                    maxValue: max(2000, vm.fileEditOpsPerSec * 1.2),
                    unit: "ops/s"
                )

                dashboardCard(
                    title: "Random Option (Write)",
                    subtitle: "Random write IOPS",
                    icon: "shuffle",
                    value: vm.randomOptionIOPS,
                    maxValue: max(1500, vm.randomOptionIOPS * 1.2),
                    unit: "IOPS"
                )

                dashboardCard(
                    title: "Random Option (Write+fsync)",
                    subtitle: "Random write + fsync",
                    icon: "checkmark.seal",
                    value: vm.randomOptionIOPSFsync,
                    maxValue: max(800, vm.randomOptionIOPSFsync * 1.2),
                    unit: "IOPS"
                )
            }
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Run Logs", systemImage: "list.bullet.rectangle")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 220)
            .padding(8)
            .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var curvePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("IOPS Stability Curve (1 min)", systemImage: "chart.xyaxis.line")
                .font(.headline)
            HStack(spacing: 14) {
                legendItem(color: .blue, text: "Mixed IOPS")
                legendItem(color: .green, text: "Read IOPS")
                legendItem(color: .orange, text: "Write IOPS")
            }

            if vm.iopsSamples.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .overlay(
                        Text("No sampling data yet. Click \"Run All\"")
                            .foregroundStyle(.secondary)
                    )
                    .frame(height: 250)
            } else {
                Chart(iopsLinePoints) { point in
                    LineMark(
                        x: .value("Second", point.second),
                        y: .value("IOPS", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(by: .value("Series", point.series))
                }
                .chartForegroundStyleScale([
                    "Mixed IOPS": Color.blue,
                    "Read IOPS": Color.green,
                    "Write IOPS": Color.orange
                ])
                .chartXAxisLabel("Time (s)")
                .chartYAxisLabel("IOPS")
                .frame(height: 250)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dashboardCard(title: String,
                               subtitle: String,
                               icon: String,
                               value: Double,
                               maxValue: Double,
                               unit: String,
                               lowerIsBetter: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Gauge(value: max(0, min(value, maxValue)), in: 0...maxValue) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", value))
                        .font(.title3.bold())
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .gaugeStyle(.accessoryLinearCapacity)

            Text(lowerIsBetter ? "Lower is better" : "Higher is better")
                .font(.caption2)
                .foregroundStyle(lowerIsBetter ? .orange : .green)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 5)
    }

    private var benchmarkSnapshotView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Small-File IOPS Benchmark Snapshot")
                .font(.title2.bold())
            Text("\(Date().formatted(date: .abbreviated, time: .standard))")
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                statTile("Create", value: vm.createFilesPerSec, unit: "Files/Sec")
                statTile("Folder Scan", value: vm.traversalFilesPerSec, unit: "files/s")
                statTile("Metadata", value: vm.metadataCreateOpsPerSec, unit: "ops/s")
                statTile("Edit", value: vm.fileEditOpsPerSec, unit: "ops/s")
                statTile("Ops", value: Double(vm.totalOperations), unit: "total")
            }

            if vm.iopsSamples.isEmpty {
                Text("No benchmark result")
            } else {
                Chart(iopsLinePoints) { point in
                    LineMark(
                        x: .value("Second", point.second),
                        y: .value("IOPS", point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                }
                .chartForegroundStyleScale([
                    "Mixed IOPS": Color.blue,
                    "Read IOPS": Color.green,
                    "Write IOPS": Color.orange
                ])
                .frame(width: 1100, height: 500)
            }
        }
        .padding(20)
        .frame(width: 1200, height: 620, alignment: .topLeading)
        .background(.background)
    }

    private func statTile(_ title: String, value: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f", value))
                .font(.title3.bold())
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var compareInputSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate Comparison")
                .font(.title3.bold())
            Text("Enter display labels shown as \"Previous Result Name vs Current Result Name\"")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("Previous Name")
                    .frame(width: 90, alignment: .leading)
                TextField("e.g. CrossDriver NTFS v1.0", text: $compareLeftLabel)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Current Name")
                    .frame(width: 90, alignment: .leading)
                TextField("e.g. CrossDriver NTFS v1.1", text: $compareRightLabel)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showCompareInput = false
                }
                Button("Generate & Open") {
                    let left = compareLeftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let right = compareRightLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalLeft = left.isEmpty ? "Previous" : left
                    let finalRight = right.isEmpty ? "Current" : right

                    guard let report = vm.buildComparisonReport(leftLabel: finalLeft, rightLabel: finalRight) else {
                        saveStatus = "❌ Unable to generate comparison: previous or current result is missing"
                        showCompareInput = false
                        return
                    }

                    BenchmarkComparisonWindowPresenter.show(report: report)
                    saveStatus = "✅ Comparison window opened: \(finalLeft) vs \(finalRight)"
                    showCompareInput = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 480)
    }
}

#Preview {
    ContentView()
}
