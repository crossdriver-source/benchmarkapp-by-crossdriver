# Benchmark by CrossDriver — User Guide

This guide is for people who **use the app** (not developers).

## What this app does

Benchmark by CrossDriver measures file-system performance with real-world style workloads, including:

- Small-file create speed
- Folder scan speed
- Metadata operations
- File edit speed
- Random write IOPS
- Stability over time (1-minute curve)

## Before you start

- Make sure the target disk has enough free space.
- Close heavy background tasks for more stable results.
- Keep the same test scenario when comparing runs.

## Quick start (3 steps)

1. Open the app.
2. Select a target disk in **Disk**.
3. Select a scenario and click **Run All**.

Wait until status changes to **Completed**.

## Scenarios

### Code Editor
- Uses a larger dataset (100,000 files)
- Best for code/project-style small-file workloads

### File Editor
- Uses a medium dataset (10,000 files)
- Best for document-heavy workflows

### Video Creator
- Uses a medium dataset (10,000 files)
- Emphasizes media-related throughput and random I/O behavior

## Main metrics (how to read)

- **Small-file Create Speed** (`files/s`): higher is better
- **Folder Scan Throughput** (`files/s`): higher is better
- **Metadata Create** (`ops/s`): higher is better
- **File Edit** (`ops/s`): higher is better
- **Random Option (Write / Write+fsync)** (`IOPS`): higher is better
- **Interactive Score**: overall responsiveness-oriented score
- **Media Score**: media/throughput-oriented score

## Test item meaning and why it matters

### Small-file Create Speed (`files/s`)
- **Meaning**: How quickly the disk can create many small files.
- **Why it matters**: Reflects project indexing, unpacking archives, package installs, cache generation, and build-system file bursts.

### Folder Scan Throughput (`files/s`)
- **Meaning**: How fast the system traverses the full benchmark dataset recursively.
- **Why it matters**: Impacts directory browsing, searching, file-tree refresh, and tools that walk large folder structures.

### Metadata Create (`ops/s`)
- **Meaning**: Throughput of metadata-heavy operations (create/stat/delete patterns).
- **Why it matters**: Affects workflows that touch many file attributes and directory entries rather than large payload writes.

### File Edit (`ops/s`)
- **Meaning**: Random in-place edit performance on existing file content.
- **Why it matters**: Represents frequent partial updates such as document edits, incremental saves, and patch-style updates.

### Random Option (Write / Write+fsync) (`IOPS`)
- **Meaning**: Random write rate with and without explicit flush (`fsync`).
- **Why it matters**: Shows the trade-off between raw speed and durability-safety behavior under sync-heavy applications.

### IOPS Stability Curve (1 minute)
- **Meaning**: Time-series behavior of mixed/read/write IOPS during sustained load.
- **Why it matters**: Reveals whether performance is stable or drops over time due to cache effects, throttling, or contention.

## Composite score meaning and significance

### Interactive Score
- **What it represents**: User-perceived responsiveness for file-heavy interactive work.
- **Built from**: small-file create + folder scan + metadata + file edit (weighted blend).
- **How to use it**: Prioritize this score when evaluating coding/document workflows and day-to-day file navigation responsiveness.

### Media Score
- **What it represents**: Media/content throughput capability under larger stream and random I/O pressure.
- **Built from**: sequential throughput + random write behavior (weighted blend).
- **How to use it**: Prioritize this score when evaluating content creation, large asset processing, and throughput-sensitive pipelines.

### Interpreting composite scores safely
- Compare scores **within the same scenario** and similar machine load.
- Treat scores as **relative indicators** (A vs B trend), not absolute universal ratings.
- A better workflow fit may come from one score being higher even if the other is lower.

## Compare two runs

- Run at least two completed tests.
- After the second run, **Compare with Previous** becomes active (blue).
- Click it, enter names for previous/current runs, then open comparison.

In the comparison view, you can see:

- Interactive Score vs Media Score
- Detailed metric rows
- Bar comparison chart
- IOPS curve comparison

Ratio values are shown as multipliers (for example `1.25x`).

## Export images

- **Save Snapshot**: saves the current main window view
- **Export Comparison Image**: exports the comparison report image

Use exported images for reports, presentations, or blog posts.

## Best practice for fair comparison

- Use the same disk, scenario, and similar system load.
- Run 2–3 times and compare the trend, not just one run.
- Avoid changing power mode, thermal conditions, or heavy apps between runs.

## FAQ

### Why is Compare disabled?
You need two completed runs first.

### Why are results different between runs?
Background load, thermal state, and disk cache can all affect results.

### What if I stop a test?
That run may be incomplete. Re-run for a clean comparison.
