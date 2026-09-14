import AppKit

final class Overlay {
    private var windows: [NSWindow] = []

    var isVisible: Bool { !windows.isEmpty }

    func show(message: String) {
        hide()
        // Debajo del nivel de la barra de menú: tapa todo menos los íconos de estado,
        // que son la salida de emergencia con el mouse mientras el teclado está bloqueado.
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = level
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = Overlay.makeContentView(message: message, size: screen.frame.size)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private static func makeContentView(message: String, size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: message)
        label.alignment = .center
        label.textColor = .white
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = .systemFont(ofSize: fittingFontSize(for: message, in: size), weight: .heavy)

        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.9)
        ])
        return container
    }

    private static func fittingFontSize(for message: String, in size: NSSize) -> CGFloat {
        let longestWord = message.split(separator: " ").map(\.count).max() ?? message.count
        let byWidth = (size.width * 0.9) / CGFloat(max(longestWord, 1)) * 1.6
        return min(max(byWidth, 48), size.height * 0.3)
    }
}
