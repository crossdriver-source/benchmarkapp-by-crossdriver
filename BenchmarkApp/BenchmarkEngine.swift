import Foundation
import AppKit
import Darwin

@MainActor
final class BenchmarkViewModel: ObservableObject {
    @Published var mountedVolumes: [MountedVolume] = []
    @Published var selectedVolumeID: String = ""
    @Published var usesCustomFolder: Bool = false
    @Published var rootPath: String = "/tmp/benchmarkapp"
    @Published var isRunning: Bool = false
    @Published var progress: Double = 0
    @Published var progressText: String = "Ready"
    @Published var logs: [String] = []
    @Published var iopsSamples: [IOPSSample] = []
    @Published var selectedPersona: BenchmarkPersona = .fileEditor
    @Published var enableFileEditTest: Bool = true
    @Published var enableRandomOptionTest: Bool = true
    @Published var enableMetadataCreateTest: Bool = true
    @Published var runSequentialThroughput: Bool = false
    @Published var useAtomicWriteForCreateTest: Bool = true
    @Published var createFilesPerSec: Double = 0
    @Published var traversalFilesPerSec: Double = 0
    @Published var fileEditOpsPerSec: Double = 0
    @Published var randomOptionIOPS: Double = 0
    @Published var randomOptionIOPSFsync: Double = 0
    @Published var metadataCreateOpsPerSec: Double = 0
    @Published var throughputProfiles: [ThroughputProfile] = []
    @Published var interactiveScore: Double = 0
    @Published var mediaScore: Double = 0
    @Published var totalOperations: Int = 0
    @Published private(set) var latestSnapshot: BenchmarkSnapshot?
    @Published private(set) var previousSnapshot: BenchmarkSnapshot?

    private let fileManager = FileManager.default
    private var shouldCancel = false

    init() {
        applyPersonaPreset()
        refreshMountedVolumes()
    }

    func applyPersonaPreset() {
        switch selectedPersona {
        case .codeEditor:
            enableMetadataCreateTest = true
            enableFileEditTest = true
            enableRandomOptionTest = true
            runSequentialThroughput = false
        case .fileEditor:
            enableMetadataCreateTest = true
            enableFileEditTest = true
            enableRandomOptionTest = false
            runSequentialThroughput = false
        case .videoCreator:
            enableMetadataCreateTest = false
            enableFileEditTest = false
            enableRandomOptionTest = true
            runSequentialThroughput = true
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Benchmark Test Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            usesCustomFolder = true
            rootPath = url.path
            appendLog("Selected custom test folder: \(rootPath)")
        }
    }

    func refreshMountedVolumes() {
        var volumes: [MountedVolume] = []

        let rootURL = URL(fileURLWithPath: "/")
        if isValidBenchmarkVolume(rootURL.path) {
            let rootFree = availableBytes(atPath: rootURL.path)
            volumes.append(MountedVolume(id: rootURL.path, name: "Macintosh HD", mountPath: rootURL.path, freeBytes: rootFree))
        }

        let volumesURL = URL(fileURLWithPath: "/Volumes")
        if let entries = try? fileManager.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard isValidBenchmarkVolume(entry.path) else { continue }
                volumes.append(
                    MountedVolume(
                        id: entry.path,
                        name: entry.lastPathComponent,
                        mountPath: entry.path,
                        freeBytes: availableBytes(atPath: entry.path)
                    )
                )
            }
        }

        mountedVolumes = volumes

        if selectedVolumeID.isEmpty || !volumes.contains(where: { $0.id == selectedVolumeID }) {
            selectedVolumeID = volumes.first?.id ?? "/"
        }

        if !usesCustomFolder {
            applySelectedVolume()
        }
    }

    func applySelectedVolume() {
        guard let selected = mountedVolumes.first(where: { $0.id == selectedVolumeID }) else { return }
        usesCustomFolder = false
        rootPath = URL(fileURLWithPath: selected.mountPath).appendingPathComponent("benchmarkapp-work").path
        appendLog("Selected volume: \(selected.mountPath)")
    }

    func cancel() {
        shouldCancel = true
        appendLog("Cancel requested. Waiting for current step to end safely...")
    }

    func runAllBenchmarks() {
        guard !isRunning else { return }
        isRunning = true
        shouldCancel = false
        progress = 0
        iopsSamples = []
        createFilesPerSec = 0
        traversalFilesPerSec = 0
        fileEditOpsPerSec = 0
        randomOptionIOPS = 0
        randomOptionIOPSFsync = 0
        metadataCreateOpsPerSec = 0
        throughputProfiles = []
        interactiveScore = 0
        mediaScore = 0
        totalOperations = 0
        logs = []

        let fileCount = selectedPersona == .codeEditor ? 100_000 : 10_000
        let traversalSampleFileCount: Int
        switch selectedPersona {
        case .codeEditor:
            traversalSampleFileCount = 20_000
        case .fileEditor:
            traversalSampleFileCount = 12_000
        case .videoCreator:
            traversalSampleFileCount = 8_000
        }
        let config = BenchmarkConfig(
            rootPath: rootPath,
            persona: selectedPersona,
            fileCount: fileCount,
            enableFileEditTest: enableFileEditTest,
            enableRandomOptionTest: enableRandomOptionTest,
            enableMetadataCreateTest: enableMetadataCreateTest,
            runSequentialThroughput: runSequentialThroughput,
            traversalSampleFileCount: traversalSampleFileCount,
            useAtomicWriteForCreateTest: useAtomicWriteForCreateTest
        )
        appendLog("Benchmark started: \(config.persona.title) · \(config.fileCount) files (4KB~16KB), writeMode=\(config.useAtomicWriteForCreateTest ? "atomic" : "direct"), root: \(config.rootPath)")

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let summary = try await BenchmarkRunner.run(
                    config: config,
                    isCancelled: {
                        await MainActor.run { self.shouldCancel }
                    },
                    onMetric: { metric in
                        await MainActor.run {
                            switch metric {
                            case .metadataCreate(let value):
                                self.metadataCreateOpsPerSec = value
                            case .fileEdit(let value):
                                self.fileEditOpsPerSec = value
                            case .randomOption(let write, let fsync):
                                self.randomOptionIOPS = write
                                self.randomOptionIOPSFsync = fsync
                            case .createFilesPerSec(let value):
                                self.createFilesPerSec = value
                            case .traversalFilesPerSec(let value):
                                self.traversalFilesPerSec = value
                            case .throughput(let profiles):
                                self.throughputProfiles = profiles
                            case .layeredScores(let interactive, let media):
                                self.interactiveScore = interactive
                                self.mediaScore = media
                            }
                        }
                    },
                    onProgress: { progress, text in
                        await MainActor.run {
                            self.progress = progress
                            self.progressText = text
                        }
                    },
                    onSample: { sample in
                        await MainActor.run {
                            self.iopsSamples.append(sample)
                        }
                    },
                    onLog: { message in
                        await MainActor.run {
                            self.appendLog(message)
                        }
                    }
                )
                await MainActor.run {
                    self.createFilesPerSec = summary.createFilesPerSec
                    self.traversalFilesPerSec = summary.traversalFilesPerSec
                    self.fileEditOpsPerSec = summary.fileEditOpsPerSec
                    self.randomOptionIOPS = summary.randomOptionIOPS
                    self.randomOptionIOPSFsync = summary.randomOptionIOPSFsync
                    self.metadataCreateOpsPerSec = summary.metadataCreateOpsPerSec
                    self.throughputProfiles = summary.throughputProfiles
                    self.interactiveScore = summary.interactiveScore
                    self.mediaScore = summary.mediaScore
                    self.totalOperations = summary.totalOperations

                    if !self.shouldCancel {
                        let snapshot = BenchmarkSnapshot(
                            persona: config.persona,
                            capturedAt: Date(),
                            createFilesPerSec: summary.createFilesPerSec,
                            traversalFilesPerSec: summary.traversalFilesPerSec,
                            fileEditOpsPerSec: summary.fileEditOpsPerSec,
                            randomOptionIOPS: summary.randomOptionIOPS,
                            randomOptionIOPSFsync: summary.randomOptionIOPSFsync,
                            metadataCreateOpsPerSec: summary.metadataCreateOpsPerSec,
                            throughputProfiles: summary.throughputProfiles,
                            interactiveScore: summary.interactiveScore,
                            mediaScore: summary.mediaScore,
                            totalOperations: summary.totalOperations,
                            iopsSamples: self.iopsSamples
                        )
                        self.previousSnapshot = self.latestSnapshot
                        self.latestSnapshot = snapshot
                    }

                    if !self.shouldCancel {
                        self.progress = 1.0
                    }
                    self.progressText = self.shouldCancel ? "Canceled" : "Completed"
                    self.appendLog(self.shouldCancel ? "⏹ Canceled" : "✅ All tests completed")
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.progressText = "Failed"
                    self.appendLog("❌ Error: \(error.localizedDescription)")
                    self.isRunning = false
                }
            }
        }
    }

    func buildComparisonReport(leftLabel: String, rightLabel: String) -> BenchmarkComparisonReport? {
        guard let left = previousSnapshot, let right = latestSnapshot else { return nil }
        return BenchmarkComparisonReport(leftLabel: leftLabel, rightLabel: rightLabel, left: left, right: right)
    }

    private func appendLog(_ text: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(text)")
    }

    private func availableBytes(atPath path: String) -> Int64? {
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: path) else { return nil }
        return (attrs[.systemFreeSize] as? NSNumber)?.int64Value
    }

    private func isValidBenchmarkVolume(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        guard fileManager.isWritableFile(atPath: path) else { return false }
        return true
    }
}

private enum BenchmarkRunner {
    static func run(
        config: BenchmarkConfig,
        isCancelled: @escaping @Sendable () async -> Bool,
        onMetric: @escaping @Sendable (BenchmarkLiveMetric) async -> Void,
        onProgress: @escaping @Sendable (Double, String) async -> Void,
        onSample: @escaping @Sendable (IOPSSample) async -> Void,
        onLog: @escaping @Sendable (String) async -> Void
    ) async throws -> BenchmarkSummary {
        let fileManager = FileManager.default
        let runDir = URL(fileURLWithPath: config.rootPath).appendingPathComponent("smallfile_bench_tmp")
        try recreateDirectory(runDir, fileManager: fileManager)

        var metadataCreateOpsPerSec = 0.0
        var fileEditOpsPerSec = 0.0
        var randomOptionResult: (iops: Double, iopsFsync: Double, totalOperations: Int, totalOperationsFsync: Int) = (0, 0, 0, 0)
        var extraOps = 0
        var throughputProfiles: [ThroughputProfile] = []

        if config.enableMetadataCreateTest {
            await onProgress(0.02, "Metadata create test ")
            await onLog("▶️ Metadata create test started")
            let metadataResult = try await runMetadataOperationsTest(in: runDir, fileManager: fileManager, isCancelled: isCancelled)
            metadataCreateOpsPerSec = metadataResult.createOpsPerSecond
            await onMetric(.metadataCreate(metadataCreateOpsPerSec))
            extraOps += metadataResult.totalOperations
            await onLog(String(format: "Metadata create speed: %.0f ops/s", metadataResult.createOpsPerSecond))
        } else {
            await onLog("⏭ Skipped: metadata create test")
        }

        if config.enableFileEditTest {
            await onProgress(0.05, "File edit test ")
            await onLog("▶️ File edit test started")
            fileEditOpsPerSec = try await runFileEditOperationsTest(in: runDir, isCancelled: isCancelled)
            await onMetric(.fileEdit(fileEditOpsPerSec))
            extraOps += 10_000
            await onLog(String(format: "File edit speed: %.0f ops/s", fileEditOpsPerSec))
        } else {
            await onLog("⏭ Skipped: file edit test")
        }

        if config.enableRandomOptionTest {
            await onProgress(0.08, "Random option test (random write / write+fsync)")
            await onLog("▶️ Random option test started")
            randomOptionResult = try await runRandomOptionTest(in: runDir, isCancelled: isCancelled)
            await onMetric(.randomOption(randomOptionResult.iops, randomOptionResult.iopsFsync))
            extraOps += randomOptionResult.totalOperations + randomOptionResult.totalOperationsFsync
            await onLog(String(format: "Random option IOPS: write=%.0f, write+fsync=%.0f", randomOptionResult.iops, randomOptionResult.iopsFsync))
        } else {
            await onLog("⏭ Skipped: random option test")
        }

        if config.runSequentialThroughput {
            await onProgress(0.1, "Sequential throughput test (1GB/4GB, cold/warm)")
            await onLog("▶️ Sequential throughput test started")
            throughputProfiles = try runSequentialThroughputTests(in: runDir, config: config, fileManager: fileManager)
            await onMetric(.throughput(throughputProfiles))
            for profile in throughputProfiles {
                await onLog(String(format: "%@ throughput: coldR %.0f / coldW %.0f / warmR %.0f / warmW %.0f MB/s",
                                   profile.sizeLabel,
                                   profile.coldReadMBps,
                                   profile.coldWriteMBps,
                                   profile.warmReadMBps,
                                   profile.warmWriteMBps))
            }
        }

        await onProgress(0.12, "Preparing dataset: creating \(config.fileCount) random small files [\(config.useAtomicWriteForCreateTest ? "atomic" : "direct")]")
        let datasetResult = try await prepareDataset(
            config: config,
            in: runDir,
            fileManager: fileManager,
            isCancelled: isCancelled,
            onProgress: onProgress,
            onLog: onLog
        )
        var files = datasetResult.files
        await onMetric(.createFilesPerSec(datasetResult.createFilesPerSec))
        await onLog(String(format: "Small-file create speed (%@): %.0f files/s",
                   config.useAtomicWriteForCreateTest ? "atomic" : "direct",
                   datasetResult.createFilesPerSec))

        await onProgress(0.22, "Folder scan throughput test (main dataset)")
        let datasetScan = traversalScanResult(of: runDir, fileManager: fileManager)
        let datasetTraversalFilesPerSec = datasetScan.filesPerSec
        await onMetric(.traversalFilesPerSec(datasetTraversalFilesPerSec))
        await onLog("Folder scan visited \(datasetScan.directoryCount) folders + \(datasetScan.fileCount) files")
        await onLog(String(format: "Folder scan throughput (main dataset): %.0f files/s", datasetTraversalFilesPerSec))

        await onProgress(0.24, "Running loop: Create / Read / Metadata Stat / Delete")

        let start = MachClock.now()
        let durationNs = UInt64(config.durationSeconds) * 1_000_000_000
        var lastSample = start
        var sampleOps = 0
        var sampleReadOps = 0
        var sampleWriteOps = 0
        var sampleSecond = 0
        var totalOps = 0

        var createOps = 0
        var createNs: UInt64 = 0
        var createIndex = config.fileCount
        var knownCreateDirs: Set<String> = []

        while MachClock.elapsedNanoseconds(from: start, to: MachClock.now()) < durationNs {
            if await isCancelled() { break }

            let createStart = MachClock.now()
            let created = try await createBatch(
                in: runDir,
                files: &files,
                startIndex: &createIndex,
                count: config.createPerRound,
                minSize: config.minFileSize,
                maxSize: config.maxFileSize,
                persona: config.persona,
                useAtomicWrite: config.useAtomicWriteForCreateTest,
                knownDirectories: &knownCreateDirs,
                isCancelled: isCancelled
            )
            let createEnd = MachClock.now()
            createOps += created
            createNs += MachClock.elapsedNanoseconds(from: createStart, to: createEnd)
            totalOps += created
            sampleOps += created

            if await isCancelled() { break }

            let reads = try readBatch(files: files, count: config.readPerRound)
            totalOps += reads
            sampleOps += reads
            sampleReadOps += reads

            let stats = try statBatch(files: files, count: config.statPerRound, fileManager: fileManager)
            totalOps += stats
            sampleOps += stats

            let deleted = try deleteBatch(files: &files, count: config.deletePerRound, fileManager: fileManager)
            totalOps += deleted
            sampleOps += deleted
            sampleWriteOps += created + deleted

            let now = MachClock.now()
            let sampleElapsed = MachClock.seconds(from: lastSample, to: now)
            if sampleElapsed >= 1 {
                sampleSecond += 1
                let mixedIOPS = Double(sampleOps) / sampleElapsed
                let readIOPS = Double(sampleReadOps) / sampleElapsed
                let writeIOPS = Double(sampleWriteOps) / sampleElapsed
                sampleOps = 0
                sampleReadOps = 0
                sampleWriteOps = 0
                lastSample = now

                await onSample(IOPSSample(second: sampleSecond, mixedIOPS: mixedIOPS, readIOPS: readIOPS, writeIOPS: writeIOPS))
                let progress = min(0.24 + (Double(sampleSecond) / Double(config.durationSeconds)) * 0.76, 1.0)
                await onProgress(progress, "Stability sampling: \(sampleSecond)s / \(config.durationSeconds)s")
                if sampleSecond % 5 == 0 {
                    await onLog(String(format: "%02ds IOPS mixed=%.0f read=%.0f write=%.0f", sampleSecond, mixedIOPS, readIOPS, writeIOPS))
                }
            }
        }

        let createFilesPerSec = datasetResult.createFilesPerSec
        let avgTraversalFilesPerSec = datasetTraversalFilesPerSec
        await onMetric(.traversalFilesPerSec(avgTraversalFilesPerSec))

        let interactiveScore = computeInteractiveScore(
            createFilesPerSec: createFilesPerSec,
            traversalFilesPerSec: avgTraversalFilesPerSec,
            metadataCreateOpsPerSec: metadataCreateOpsPerSec,
            fileEditOpsPerSec: fileEditOpsPerSec
        )
        let mediaScore = computeMediaScore(
            randomOptionIOPS: randomOptionResult.iops,
            randomOptionIOPSFsync: randomOptionResult.iopsFsync,
            throughputProfiles: throughputProfiles
        )
        await onMetric(.layeredScores(interactive: interactiveScore, media: mediaScore))

        try? fileManager.removeItem(at: runDir)

        return BenchmarkSummary(
            createFilesPerSec: createFilesPerSec,
            traversalFilesPerSec: avgTraversalFilesPerSec,
            fileEditOpsPerSec: fileEditOpsPerSec,
            randomOptionIOPS: randomOptionResult.iops,
            randomOptionIOPSFsync: randomOptionResult.iopsFsync,
            metadataCreateOpsPerSec: metadataCreateOpsPerSec,
            throughputProfiles: throughputProfiles,
            interactiveScore: interactiveScore,
            mediaScore: mediaScore,
            durationSeconds: config.durationSeconds,
            totalOperations: totalOps + extraOps
        )
    }

    private static func prepareDataset(
        config: BenchmarkConfig,
        in dir: URL,
        fileManager: FileManager,
        isCancelled: @escaping @Sendable () async -> Bool,
        onProgress: @escaping @Sendable (Double, String) async -> Void,
        onLog: @escaping @Sendable (String) async -> Void
    ) async throws -> (files: [URL], createFilesPerSec: Double) {
        var urls: [URL] = []
        var knownDirectories: Set<String> = []
        urls.reserveCapacity(config.fileCount)
        let start = MachClock.now()

        for i in 0..<config.fileCount {
            if i % 128 == 0 {
                if await isCancelled() {
                    await onLog("⏹ Dataset preparation canceled")
                    break
                }
            }
            let fileURL = fileURLForIndex(baseDir: dir, index: i, persona: config.persona, prefix: "seed")
            try createParentDirectoryIfNeeded(for: fileURL, fileManager: fileManager, knownDirectories: &knownDirectories)
            let size = Int.random(in: config.minFileSize...config.maxFileSize)
            let randomByte = UInt8.random(in: 0...255)
            let payload = Data(repeating: randomByte, count: size)
            try payload.write(to: fileURL, options: config.useAtomicWriteForCreateTest ? .atomic : [])
            urls.append(fileURL)

            if i % 5000 == 0 {
                let progress = 0.12 + (Double(i) / Double(config.fileCount)) * 0.12
                await onProgress(progress, "Preparing dataset: \(i)/\(config.fileCount)")
                await onLog("Preparing dataset: \(i)/\(config.fileCount)")
            }
        }

        let end = MachClock.now()
        let seconds = MachClock.seconds(from: start, to: end)
        let createSpeed = seconds > 0 ? Double(urls.count) / seconds : 0
        return (urls, createSpeed)
    }

    private static func runTraversalLatencyEarlyTest(
        in runDir: URL,
        config: BenchmarkConfig,
        fileManager: FileManager,
        isCancelled: @escaping @Sendable () async -> Bool,
        onProgress: @escaping @Sendable (Double, String) async -> Void,
        onLog: @escaping @Sendable (String) async -> Void
    ) async throws -> Double {
        let traversalDir = runDir.appendingPathComponent("traversal_latency_test")
        try recreateDirectory(traversalDir, fileManager: fileManager)

        let total = max(200, config.traversalSampleFileCount)
        for i in 0..<total {
            if i % 128 == 0 {
                if await isCancelled() {
                    await onLog("⏹ Traversal latency test canceled")
                    try? fileManager.removeItem(at: traversalDir)
                    return 0
                }
                let p = 0.11 + (Double(i) / Double(total)) * 0.01
                await onProgress(p, "Preparing traversal test: \(i)/\(total)")
            }

            let url = fileURLForIndex(baseDir: traversalDir, index: i, persona: config.persona, prefix: "traversal")
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = Data(repeating: UInt8(i % 255), count: 1024)
            try payload.write(to: url, options: .atomic)
        }

        let scanResult = traversalScanResult(of: traversalDir, fileManager: fileManager)
        let filesPerSec = scanResult.filesPerSec
        await onLog("Traversal scan visited \(scanResult.directoryCount) folders + \(scanResult.fileCount) files")
        try? fileManager.removeItem(at: traversalDir)
        return filesPerSec
    }

    private static func runTraversalLatencyQuickPreview(
        in runDir: URL,
        config: BenchmarkConfig,
        fileManager: FileManager,
        isCancelled: @escaping @Sendable () async -> Bool,
        onProgress: @escaping @Sendable (Double, String) async -> Void,
        onLog: @escaping @Sendable (String) async -> Void
    ) async throws -> Double {
        let previewDir = runDir.appendingPathComponent("traversal_quick_preview")
        try recreateDirectory(previewDir, fileManager: fileManager)

        let previewTotal = min(1_200, max(512, config.traversalSampleFileCount / 4))
        for i in 0..<previewTotal {
            if i % 32 == 0 {
                if await isCancelled() {
                    await onLog("⏹ Traversal quick preview canceled")
                    try? fileManager.removeItem(at: previewDir)
                    return 0
                }
                let p = 0.105 + (Double(i) / Double(previewTotal)) * 0.005
                await onProgress(p, "Traversal quick preview: \(i)/\(previewTotal)")
            }

            let url = fileURLForIndex(baseDir: previewDir, index: i, persona: config.persona, prefix: "preview")
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = Data(repeating: UInt8(i % 255), count: 512)
            try payload.write(to: url, options: .atomic)
        }

        let scanResult = traversalScanResult(of: previewDir, fileManager: fileManager)
        let filesPerSec = scanResult.filesPerSec
        await onLog("Quick scan visited \(scanResult.directoryCount) folders + \(scanResult.fileCount) files")
        try? fileManager.removeItem(at: previewDir)
        return filesPerSec
    }

    private static func runMetadataOperationsTest(
        in runDir: URL,
        fileManager: FileManager,
        isCancelled: @escaping @Sendable () async -> Bool
    ) async throws -> (createOpsPerSecond: Double, totalOperations: Int) {
        let testDir = runDir.appendingPathComponent("metadata_test")
        try recreateDirectory(testDir, fileManager: fileManager)
        let numFiles = 10_000

        let createStart = MachClock.now()
        for i in 0..<numFiles {
            if i % 1000 == 0 {
                if await isCancelled() { break }
            }
            let path = testDir.appendingPathComponent(String(format: "file_%05d.txt", i))
            fileManager.createFile(atPath: path.path, contents: Data(), attributes: nil)
        }
        let createEnd = MachClock.now()

        for i in 0..<numFiles {
            let path = testDir.appendingPathComponent(String(format: "file_%05d.txt", i))
            _ = try? fileManager.attributesOfItem(atPath: path.path)
        }

        for i in 0..<numFiles {
            let path = testDir.appendingPathComponent(String(format: "file_%05d.txt", i))
            try? fileManager.removeItem(at: path)
        }
        try? fileManager.removeItem(at: testDir)

        let createSeconds = MachClock.seconds(from: createStart, to: createEnd)
        let createOpsPerSec = createSeconds > 0 ? Double(numFiles) / createSeconds : 0
        return (createOpsPerSec, numFiles * 3)
    }

    private static func runFileEditOperationsTest(
        in runDir: URL,
        isCancelled: @escaping @Sendable () async -> Bool
    ) async throws -> Double {
        let testFile = runDir.appendingPathComponent("file_edit_test.dat")
        let fileSize = 100 * 1024 * 1024
        let blockSize = 4 * 1024
        let numEdits = 10_000

        let seedChunk = Data(repeating: 0x5A, count: 1024 * 1024)
        FileManager.default.createFile(atPath: testFile.path, contents: nil, attributes: nil)
        let initHandle = try FileHandle(forWritingTo: testFile)
        for _ in 0..<(fileSize / seedChunk.count) {
            try initHandle.write(contentsOf: seedChunk)
        }
        try initHandle.close()

        var positions: [UInt64] = []
        positions.reserveCapacity(numEdits)
        let maxOffset = fileSize - blockSize
        for _ in 0..<numEdits {
            positions.append(UInt64(Int.random(in: 0...maxOffset)))
        }

        let block = Data((0..<blockSize).map { _ in UInt8.random(in: 0...255) })
        let start = MachClock.now()
        let handle = try FileHandle(forUpdating: testFile)
        for (index, pos) in positions.enumerated() {
            if index % 512 == 0 {
                if await isCancelled() { break }
            }
            try handle.seek(toOffset: pos)
            try handle.write(contentsOf: block)
        }
        try handle.close()
        let end = MachClock.now()

        try? FileManager.default.removeItem(at: testFile)

        let seconds = MachClock.seconds(from: start, to: end)
        return seconds > 0 ? Double(numEdits) / seconds : 0
    }

    private static func runRandomOptionTest(
        in runDir: URL,
        isCancelled: @escaping @Sendable () async -> Bool
    ) async throws -> (iops: Double, iopsFsync: Double, totalOperations: Int, totalOperationsFsync: Int) {
        let testFile = runDir.appendingPathComponent("random_option_test.dat")
        let fileSize = 100 * 1024 * 1024
        let blockSize = 16 * 1024
        let numWrites = 10_000
        let maxOffset = fileSize - blockSize

        var positions: [UInt64] = []
        positions.reserveCapacity(numWrites)
        for _ in 0..<numWrites {
            positions.append(UInt64(Int.random(in: 0...maxOffset)))
        }
        let block = Data((0..<blockSize).map { _ in UInt8.random(in: 0...255) })

        FileManager.default.createFile(atPath: testFile.path, contents: Data(count: fileSize), attributes: nil)
        let start = MachClock.now()
        let handle = try FileHandle(forUpdating: testFile)
        var opCount = 0
        for (index, pos) in positions.enumerated() {
            if index % 512 == 0 {
                if await isCancelled() { break }
            }
            try handle.seek(toOffset: pos)
            try handle.write(contentsOf: block)
            opCount += 1
        }
        try handle.close()
        let end = MachClock.now()
        let t1 = MachClock.seconds(from: start, to: end)
        let iops = t1 > 0 ? Double(opCount) / t1 : 0

        try? FileManager.default.removeItem(at: testFile)
        FileManager.default.createFile(atPath: testFile.path, contents: Data(count: fileSize), attributes: nil)

        let startFsync = MachClock.now()
        let handleFsync = try FileHandle(forUpdating: testFile)
        var opCountFsync = 0
        for (index, pos) in positions.enumerated() {
            if index % 512 == 0 {
                if await isCancelled() { break }
            }
            try handleFsync.seek(toOffset: pos)
            try handleFsync.write(contentsOf: block)
            opCountFsync += 1
        }
        fsync(handleFsync.fileDescriptor)
        try handleFsync.close()
        let endFsync = MachClock.now()
        let t2 = MachClock.seconds(from: startFsync, to: endFsync)
        let iopsFsync = t2 > 0 ? Double(opCountFsync) / t2 : 0

        try? FileManager.default.removeItem(at: testFile)
        return (iops, iopsFsync, opCount, opCountFsync)
    }


    private static func createBatch(in dir: URL,
                                    files: inout [URL],
                                    startIndex: inout Int,
                                    count: Int,
                                    minSize: Int,
                                    maxSize: Int,
                                    persona: BenchmarkPersona,
                                    useAtomicWrite: Bool,
                                    knownDirectories: inout Set<String>,
                                    isCancelled: @escaping @Sendable () async -> Bool) async throws -> Int {
        var created = 0
        for index in 0..<count {
            if index % 32 == 0 {
                if await isCancelled() { break }
            }
            let fileURL = fileURLForIndex(baseDir: dir, index: startIndex, persona: persona, prefix: "live")
            try createParentDirectoryIfNeeded(for: fileURL, fileManager: FileManager.default, knownDirectories: &knownDirectories)
            startIndex += 1
            let size = Int.random(in: minSize...maxSize)
            let byte = UInt8.random(in: 0...255)
            let payload = Data(repeating: byte, count: size)
            try payload.write(to: fileURL, options: useAtomicWrite ? .atomic : [])
            files.append(fileURL)
            created += 1
        }
        return created
    }

    private static func fileURLForIndex(baseDir: URL, index: Int, persona: BenchmarkPersona, prefix: String) -> URL {
        switch persona {
        case .codeEditor:
            var current = baseDir.appendingPathComponent("repo", isDirectory: true)
            let depth = 2 + (index % 9)
            for level in 0..<depth {
                let bucket = (index / Int(pow(5.0, Double(level)))) % 5
                current = current.appendingPathComponent("lvl\(level)_\(bucket)", isDirectory: true)
            }
            return current.appendingPathComponent("\(prefix)_\(index).dat")
        case .fileEditor:
            let group = index % 200
            let sub = (index / 200) % 20
            var dir = baseDir.appendingPathComponent("docs_g\(group)", isDirectory: true)
            if (index % 4) != 0 {
                dir = dir.appendingPathComponent("sub_\(sub)", isDirectory: true)
                if (index % 10) == 0 {
                    dir = dir.appendingPathComponent("topic_\((index / 10) % 8)", isDirectory: true)
                }
            }
            return dir.appendingPathComponent("\(prefix)_\(index).dat")
        case .videoCreator:
            let day = index % 31
            let reel = (index / 31) % 12
            var dir = baseDir.appendingPathComponent("assets_day\(day)", isDirectory: true)
            if (index % 5) != 0 {
                dir = dir.appendingPathComponent("reel_\(reel)", isDirectory: true)
                if (index % 11) == 0 {
                    dir = dir.appendingPathComponent("clip_\((index / 11) % 6)", isDirectory: true)
                }
            }
            return dir.appendingPathComponent("\(prefix)_\(index).dat")
        }
    }

    private static func runSequentialThroughputTests(
        in runDir: URL,
        config: BenchmarkConfig,
        fileManager: FileManager
    ) throws -> [ThroughputProfile] {
        let sizes: [Int] = [1, 4]
        var profiles: [ThroughputProfile] = []

        for sizeGB in sizes {
            let fileURL = runDir.appendingPathComponent("seq_\(sizeGB)GB.bin")
            let sizeBytes = sizeGB * 1024 * 1024 * 1024
            var coldRead: [Double] = []
            var coldWrite: [Double] = []
            var warmRead: [Double] = []
            var warmWrite: [Double] = []

            let totalRounds = 1 + config.throughputWarmupRounds + config.throughputRounds
            for round in 0..<totalRounds {
                let blockSize = Int.random(in: (1 * 1024 * 1024)...(4 * 1024 * 1024))
                let chunk = Data(repeating: UInt8(round % 255), count: blockSize)

                let wStart = MachClock.now()
                fileManager.createFile(atPath: fileURL.path, contents: nil)
                let writeHandle = try FileHandle(forWritingTo: fileURL)
                var written = 0
                while written < sizeBytes {
                    try writeHandle.write(contentsOf: chunk)
                    written += chunk.count
                }
                try writeHandle.close()
                let wEnd = MachClock.now()
                let wSec = max(0.0001, MachClock.seconds(from: wStart, to: wEnd))
                let wMBps = (Double(sizeBytes) / wSec) / (1024 * 1024)

                let rStart = MachClock.now()
                let readHandle = try FileHandle(forReadingFrom: fileURL)
                while try readHandle.read(upToCount: blockSize)?.isEmpty == false { }
                try readHandle.close()
                let rEnd = MachClock.now()
                let rSec = max(0.0001, MachClock.seconds(from: rStart, to: rEnd))
                let rMBps = (Double(sizeBytes) / rSec) / (1024 * 1024)

                if round == 0 {
                    coldWrite.append(wMBps)
                    coldRead.append(rMBps)
                } else if round > config.throughputWarmupRounds {
                    warmWrite.append(wMBps)
                    warmRead.append(rMBps)
                }
            }

            try? fileManager.removeItem(at: fileURL)

            let merged = coldRead + coldWrite + warmRead + warmWrite
            let median = percentile(merged, p: 50)
            let p95 = percentile(merged, p: 95)
            profiles.append(
                ThroughputProfile(
                    sizeLabel: "\(sizeGB)GB",
                    coldReadMBps: average(coldRead),
                    coldWriteMBps: average(coldWrite),
                    warmReadMBps: average(warmRead),
                    warmWriteMBps: average(warmWrite),
                    medianMBps: median,
                    p95MBps: p95
                )
            )
        }

        return profiles
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let pos = Int((p / 100.0) * Double(max(0, sorted.count - 1)))
        return sorted[min(max(0, pos), sorted.count - 1)]
    }

    private static func computeInteractiveScore(
        createFilesPerSec: Double,
        traversalFilesPerSec: Double,
        metadataCreateOpsPerSec: Double,
        fileEditOpsPerSec: Double
    ) -> Double {
        let createPart = min(100, createFilesPerSec / 80)
        let traversalPart = min(100, traversalFilesPerSec / 50)
        let metadataPart = min(100, metadataCreateOpsPerSec / 80)
        let editPart = min(100, fileEditOpsPerSec / 40)
        return (createPart * 0.35) + (traversalPart * 0.2) + (metadataPart * 0.25) + (editPart * 0.2)
    }

    private static func computeMediaScore(
        randomOptionIOPS: Double,
        randomOptionIOPSFsync: Double,
        throughputProfiles: [ThroughputProfile]
    ) -> Double {
        let throughputMean = average(throughputProfiles.map { ($0.coldReadMBps + $0.coldWriteMBps + $0.warmReadMBps + $0.warmWriteMBps) / 4.0 })
        let randomMean = (randomOptionIOPS + randomOptionIOPSFsync) / 2

        func smoothScore(_ value: Double, midpoint: Double) -> Double {
            guard value > 0, midpoint > 0 else { return 0 }
            return 100 * (1 - exp(-value / midpoint))
        }

        let throughputPart = smoothScore(throughputMean, midpoint: 500)
        let randomPart = smoothScore(randomMean, midpoint: 4000)
        return throughputPart * 0.7 + randomPart * 0.3
    }

    private static func readBatch(files: [URL], count: Int) throws -> Int {
        guard !files.isEmpty else { return 0 }
        var reads = 0
        for _ in 0..<count {
            let index = Int.random(in: 0..<files.count)
            _ = try Data(contentsOf: files[index], options: .mappedIfSafe)
            reads += 1
        }
        return reads
    }

    private static func statBatch(files: [URL], count: Int, fileManager: FileManager) throws -> Int {
        guard !files.isEmpty else { return 0 }
        var stats = 0
        for _ in 0..<count {
            let index = Int.random(in: 0..<files.count)
            _ = try fileManager.attributesOfItem(atPath: files[index].path)
            stats += 1
        }
        return stats
    }

    private static func deleteBatch(files: inout [URL], count: Int, fileManager: FileManager) throws -> Int {
        guard !files.isEmpty else { return 0 }
        let actual = min(count, files.count)
        var deleted = 0
        for _ in 0..<actual {
            let index = Int.random(in: 0..<files.count)
            let target = files.remove(at: index)
            try fileManager.removeItem(at: target)
            deleted += 1
        }
        return deleted
    }

    private static func createParentDirectoryIfNeeded(
        for fileURL: URL,
        fileManager: FileManager,
        knownDirectories: inout Set<String>
    ) throws {
        let parent = fileURL.deletingLastPathComponent()
        let parentPath = parent.path
        if knownDirectories.contains(parentPath) {
            return
        }
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        knownDirectories.insert(parentPath)
    }

    private static func traversalScanResult(of dir: URL, fileManager: FileManager) -> (filesPerSec: Double, fileCount: Int, directoryCount: Int) {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let begin = MachClock.now()
        var fileCount = 0
        var directoryCount = 1

        if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: nil) {
            while let url = enumerator.nextObject() as? URL {
                if let values = try? url.resourceValues(forKeys: Set(resourceKeys)) {
                    if values.isDirectory == true {
                        directoryCount += 1
                    } else {
                        fileCount += 1
                    }
                } else {
                    fileCount += 1
                }
            }
        }

        let end = MachClock.now()
        let seconds = max(0.0001, MachClock.seconds(from: begin, to: end))
        let filesPerSec = Double(fileCount) / seconds
        return (filesPerSec, fileCount, directoryCount)
    }

    private static func recreateDirectory(_ url: URL, fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

enum MachClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func now() -> UInt64 {
        mach_absolute_time()
    }

    static func elapsedNanoseconds(from start: UInt64, to end: UInt64) -> UInt64 {
        let elapsed = end &- start
        let numer = UInt64(max(1, timebase.numer))
        let denom = UInt64(max(1, timebase.denom))
        return elapsed &* numer / denom
    }

    static func seconds(from start: UInt64, to end: UInt64) -> Double {
        Double(elapsedNanoseconds(from: start, to: end)) / 1_000_000_000
    }

    static func milliseconds(from start: UInt64, to end: UInt64) -> Double {
        Double(elapsedNanoseconds(from: start, to: end)) / 1_000_000
    }
}
