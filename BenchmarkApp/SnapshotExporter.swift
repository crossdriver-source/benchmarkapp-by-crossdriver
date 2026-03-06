import SwiftUI
import AppKit
import CoreGraphics

enum SnapshotExporter {
    @MainActor
    static func exportCurrentWindow() -> String {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return "❌ Capture failed: active window not found"
        }

        let windowID = CGWindowID(window.windowNumber)
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return "❌ Capture failed: unable to capture benchmark window"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "benchmark_\(timestamp()).png"
        panel.title = "Save Benchmark Image"

        guard panel.runModal() == .OK, let url = panel.url else {
            return "Save canceled"
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:])
        else {
            return "❌ Export failed: image encoding error"
        }

        do {
            try png.write(to: url)
            return "✅ Benchmark image saved to: \(url.path)"
        } catch {
            return "❌ Save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    static func exportViewImage<V: View>(
        _ view: V,
        size: CGSize,
        fileNamePrefix: String = "benchmark",
        panelTitle: String = "Save Benchmark Image"
    ) -> String {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return "❌ Export failed: unable to initialize bitmap renderer"
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

        guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
            return "❌ Export failed: image encoding error"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(fileNamePrefix)_\(timestamp()).png"
        panel.title = panelTitle

        guard panel.runModal() == .OK, let url = panel.url else {
            return "Save canceled"
        }

        do {
            try png.write(to: url)
            return "✅ Benchmark image saved to: \(url.path)"
        } catch {
            return "❌ Save failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    static func exportViewImageAutoSized<V: View>(
        _ view: V,
        width: CGFloat,
        minHeight: CGFloat = 0,
        maxHeight: CGFloat = 4096,
        fileNamePrefix: String = "benchmark",
        panelTitle: String = "Save Benchmark Image"
    ) -> String {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: maxHeight)
        hostingView.layoutSubtreeIfNeeded()

        var contentHeight = hostingView.fittingSize.height
        if !contentHeight.isFinite || contentHeight <= 0 {
            contentHeight = maxHeight
        }
        let finalHeight = min(max(max(contentHeight, minHeight), 1), maxHeight)
        let finalSize = CGSize(width: width, height: finalHeight)
        hostingView.frame = NSRect(origin: .zero, size: finalSize)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(finalSize.width),
            pixelsHigh: Int(finalSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return "❌ Export failed: unable to initialize bitmap renderer"
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

        guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
            return "❌ Export failed: image encoding error"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(fileNamePrefix)_\(timestamp()).png"
        panel.title = panelTitle

        guard panel.runModal() == .OK, let url = panel.url else {
            return "Save canceled"
        }

        do {
            try png.write(to: url)
            return "✅ Benchmark image saved to: \(url.path)"
        } catch {
            return "❌ Save failed: \(error.localizedDescription)"
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
