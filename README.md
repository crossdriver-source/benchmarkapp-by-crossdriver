# Benchmark by CrossDriver

A macOS SwiftUI benchmark app focused on file-system behavior for small-file and mixed I/O workloads.

## Documentation

- Detailed usage guide: [USAGE.md](USAGE.md)
- End-user guide: [USER_GUIDE.md](USER_GUIDE.md)

## What it measures

- Small-file create throughput (`files/s`)
- Folder scan throughput (`files/s`, higher is better)
- Metadata create throughput (`ops/s`)
- File edit throughput (`ops/s`)
- Random write IOPS and random write + fsync IOPS
- Sequential throughput profiles (cold/warm read/write for 1GB and 4GB, scenario-dependent)
- 1-minute mixed/read/write IOPS stability curve

## Run flow

1. Creates a temporary run directory under your selected target volume.
2. Runs optional pre-tests (metadata create, file edit, random write tests).
3. Builds the main small-file dataset:
	- Code Editor: `100,000` files
	- File Editor / Video Creator: `10,000` files
4. Runs folder scan throughput on that full main dataset.
5. Runs the main 60-second loop: `Create / Read / Metadata Stat / Delete`.
6. Computes layered scores and keeps snapshots for comparison.

## Folder Scan metric details

- `Folder Scan Throughput` scans the full main dataset created for the selected scenario.
- Dataset size is scenario-based:
	- Code Editor: `100,000` files
	- File Editor: `10,000` files
	- Video Creator: `10,000` files
- The scanner traverses files and directories recursively; throughput is reported as `files/s` (higher is better).

## UI features

- Mounted volume picker (`/` and `/Volumes/*`) with writable-volume filtering
- Save snapshot (captures current app window)
- Compare with previous run (named labels, separate comparison window)
- Comparison image export for blog/promo usage

## Build

```bash
cd benchmarkapp
xcodebuild -project BenchmarkApp.xcodeproj -scheme BenchmarkApp -configuration Debug build
```
