# Benchmark by CrossDriver — Usage Guide

This guide explains how to run benchmarks, compare two runs, and export images for reports/blog posts.

## 1) Build and Launch

From the `benchmarkapp` folder:

```bash
xcodebuild -project BenchmarkApp.xcodeproj -scheme BenchmarkApp -configuration Debug build
open "DerivedData/BenchmarkApp/Build/Products/Debug/Benchmark by CrossDriver.app"
```

If your local DerivedData path is different, launch from Xcode:

- Open `BenchmarkApp.xcodeproj`
- Select scheme: `BenchmarkApp`
- Press Run

## 2) Basic Workflow

1. Select a writable target volume from the **Disk** picker.
2. Choose a **Scenario**.
3. Click **Run All**.
4. Wait for status to become **Completed**.

The app creates a temporary benchmark working directory under your selected volume and removes temporary run data at the end.

## 3) Scenario Behavior

### Code Editor
- Main dataset size: **100,000 files**
- Focus: small-file behavior + metadata + random write behavior + folder scan throughput

### File Editor
- Main dataset size: **10,000 files**
- Focus: small-file behavior + metadata + file edit + folder scan throughput

### Video Creator
- Main dataset size: **10,000 files**
- Focus: sequential throughput + mixed IOPS + random write behavior

## 4) Key Metrics

- **Small-file Create Speed**: file creation throughput (`files/s`)
- **Folder Scan Throughput**: recursive scan speed over the full main dataset (`files/s`, higher is better)
- **Metadata Create**: metadata operation throughput (`ops/s`)
- **File Edit**: random in-place file edits (`ops/s`)
- **Random Option (Write / Write+fsync)**: random write performance (`IOPS`)
- **Interactive Score**: weighted score from create, folder scan, metadata, file edit
- **Media Score**: weighted score from throughput + random IOPS (with smooth scoring to avoid always hitting 100)

### What each test item means in practice

- **Small-file Create Speed**
	- Measures burst small-file creation capability.
	- Useful for code checkout/build cache/package extraction style workloads.

- **Folder Scan Throughput**
	- Measures recursive traversal speed over the benchmark dataset.
	- Useful for finder/file-tree browsing, indexing, and search-like scans.

- **Metadata Create**
	- Measures metadata-heavy file-system operations.
	- Useful for workflows with many file entries/attribute touches.

- **File Edit**
	- Measures random in-place update throughput.
	- Useful for frequent partial-save and patch-like file updates.

- **Random Option (Write / Write+fsync)**
	- Measures random write speed with/without explicit durability flush.
	- Useful for understanding performance vs data-safety flush cost.

### Composite score meaning

- **Interactive Score**
	- Meaning: responsiveness-oriented capability for day-to-day interactive file workflows.
	- Significance: prioritize for code/document-centric usage.

- **Media Score**
	- Meaning: throughput-oriented capability for larger stream + random write workloads.
	- Significance: prioritize for media/content-production style usage.

### How to interpret scores correctly

- Compare runs under the same scenario and similar system load.
- Use scores as relative ranking signals, not absolute universal ratings.
- Choose by workload fit: higher Interactive is not always better than higher Media for every user.

## 5) Compare Two Runs

- You need at least **two completed runs**.
- After the second run, **Compare with Previous** becomes a highlighted blue button.
- Click it, enter labels, then open the comparison window.

Comparison window includes:

- Always-visible **Interactive Score** and **Media Score** comparison cards
- Detailed metric rows
- Core metrics bar chart
- Mixed IOPS curve comparison

Trend values are displayed as multipliers (`x`) rather than percent.

## 6) Export Images

- **Save Snapshot** (main window): captures the current visible app window.
- **Export Comparison Image** (comparison window): exports full comparison content for sharing.

## 7) Tips for Stable Results

- Close heavy background tasks before benchmarking.
- Use the same disk and same scenario when comparing two runs.
- Run at least 2–3 times and compare median behavior.
- Avoid changing system power/thermal state between runs.

## 8) Troubleshooting

### Compare button stays disabled
You do not have two completed snapshots yet. Run **Run All** again and wait for completion.

### Export image missing expected content
Use export from the comparison window after layout settles (scroll position and folded sections matter).

### Scores look too similar
Use the latest build (Media score mapping has been adjusted to reduce score saturation).
