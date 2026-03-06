import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard !coordinator.didConfigure else { return }
        guard let window = view.window else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.height = visible.height

        if frame.size.width > visible.width {
            frame.size.width = visible.width * 0.96
        }

        frame.origin.y = visible.minY
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))

        window.setFrame(frame, display: true, animate: false)
        coordinator.didConfigure = true
    }

    final class Coordinator {
        var didConfigure = false
    }
}
