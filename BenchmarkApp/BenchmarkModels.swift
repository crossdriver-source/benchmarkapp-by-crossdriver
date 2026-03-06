import Foundation

enum BenchmarkPersona: String, CaseIterable, Identifiable {
    case codeEditor
    case fileEditor
    case videoCreator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codeEditor: return "Code Editor"
        case .fileEditor: return "File Editor"
        case .videoCreator: return "Video Creator"
        }
    }

    var enabledTestsDescription: String {
        switch self {
        case .codeEditor:
            return "Small-file IOPS + metadata create + file edit + random options + deep directory traversal"
        case .fileEditor:
            return "Small-file IOPS + metadata create + file edit + directory traversal"
        case .videoCreator:
            return "Sequential throughput (1GB/4GB, cold/warm) + mixed IOPS + random options"
        }
    }
}

struct MountedVolume: Identifiable, Hashable {
    let id: String
    let name: String
    let mountPath: String
    let freeBytes: Int64?

    var subtitle: String {
        if let freeBytes {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useGB, .useTB]
            formatter.countStyle = .file
            return "\(mountPath) · Free \(formatter.string(fromByteCount: freeBytes))"
        }
        return mountPath
    }
}

struct BenchmarkConfig {
    var rootPath: String
    var persona: BenchmarkPersona = .codeEditor
    var fileCount: Int = 100_000
    var minFileSize: Int = 4 * 1024
    var maxFileSize: Int = 16 * 1024
    var enableFileEditTest: Bool = true
    var enableRandomOptionTest: Bool = true
    var enableMetadataCreateTest: Bool = true
    var durationSeconds: Int = 60
    var createPerRound: Int = 120
    var readPerRound: Int = 420
    var statPerRound: Int = 420
    var deletePerRound: Int = 120
    var runSequentialThroughput: Bool = false
    var throughputRounds: Int = 3
    var throughputWarmupRounds: Int = 1
    var traversalSampleFileCount: Int = 4_000
    var useAtomicWriteForCreateTest: Bool = true
}

struct ThroughputProfile: Identifiable {
    let id = UUID()
    let sizeLabel: String
    let coldReadMBps: Double
    let coldWriteMBps: Double
    let warmReadMBps: Double
    let warmWriteMBps: Double
    let medianMBps: Double
    let p95MBps: Double
}

struct IOPSSample: Identifiable {
    let id = UUID()
    let second: Int
    let mixedIOPS: Double
    let readIOPS: Double
    let writeIOPS: Double
}

struct BenchmarkSummary {
    let createFilesPerSec: Double
    let traversalFilesPerSec: Double
    let fileEditOpsPerSec: Double
    let randomOptionIOPS: Double
    let randomOptionIOPSFsync: Double
    let metadataCreateOpsPerSec: Double
    let throughputProfiles: [ThroughputProfile]
    let interactiveScore: Double
    let mediaScore: Double
    let durationSeconds: Int
    let totalOperations: Int
}

enum BenchmarkLiveMetric {
    case metadataCreate(Double)
    case fileEdit(Double)
    case randomOption(Double, Double)
    case createFilesPerSec(Double)
    case traversalFilesPerSec(Double)
    case throughput([ThroughputProfile])
    case layeredScores(interactive: Double, media: Double)
}

struct BenchmarkSnapshot: Identifiable {
    let id = UUID()
    let persona: BenchmarkPersona
    let capturedAt: Date
    let createFilesPerSec: Double
    let traversalFilesPerSec: Double
    let fileEditOpsPerSec: Double
    let randomOptionIOPS: Double
    let randomOptionIOPSFsync: Double
    let metadataCreateOpsPerSec: Double
    let throughputProfiles: [ThroughputProfile]
    let interactiveScore: Double
    let mediaScore: Double
    let totalOperations: Int
    let iopsSamples: [IOPSSample]
}

struct BenchmarkComparisonReport {
    let leftLabel: String
    let rightLabel: String
    let left: BenchmarkSnapshot
    let right: BenchmarkSnapshot
}
