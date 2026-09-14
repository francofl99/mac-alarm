import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSave: ((Config) -> Void)?
    var onPreviewSound: ((Config) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private var config: Config
    private let delayField = NSTextField()
    private let messageField = NSTextField()
    private let soundField = NSTextField()
    private let repeatField = NSTextField()
    private let volumeSlider = NSSlider()
    private let blockCheckbox = NSButton(checkboxWithTitle: "Bloquear el teclado mientras suena", target: nil, action: nil)
    private let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    private var recordingMonitor: Any?

    init(config: Config) {
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacAlarm — Configuración"
        super.init(window: window)
        window.delegate = self
        window.contentView = buildForm()
        window.center()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func buildForm() -> NSView {
        [delayField, messageField, soundField, repeatField].forEach {
            $0.isEditable = true
            $0.isBezeled = true
            $0.bezelStyle = .roundedBezel
        }
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        hotKeyButton.target = self
        hotKeyButton.action = #selector(startRecording)
        hotKeyButton.bezelStyle = .rounded

        let chooseButton = NSButton(title: "Elegir…", target: self, action: #selector(chooseSound))
        let testButton = NSButton(title: "Probar", target: self, action: #selector(testSound))
        let soundRow = NSStackView(views: [soundField, chooseButton, testButton])
        soundRow.orientation = .horizontal
        soundField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let grid = NSGridView(views: [
            [label("Segundos hasta armarse:"), delayField],
            [label("Mensaje en pantalla:"), messageField],
            [label("Sonido:"), soundRow],
            [label("Repetir cada (seg, 0 = continuo):"), repeatField],
            [label("Volumen:"), volumeSlider],
            [label("Atajo:"), hotKeyButton],
            [NSGridCell.emptyContentView, blockCheckbox]
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "Guardar", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancelar", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(grid)
        root.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        return root
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func loadValues() {
        delayField.stringValue = String(format: "%g", config.delaySeconds)
        messageField.stringValue = config.message
        soundField.stringValue = config.soundPath
        repeatField.stringValue = String(format: "%g", config.repeatIntervalSeconds)
        volumeSlider.doubleValue = config.volume
        blockCheckbox.state = config.blockKeyboard ? .on : .off
        hotKeyButton.title = config.hotKeyDescription
    }

    private func collect() -> Config {
        var updated = config
        updated.delaySeconds = max(1, Double(delayField.stringValue) ?? config.delaySeconds)
        updated.message = messageField.stringValue.isEmpty ? config.message : messageField.stringValue
        updated.soundPath = soundField.stringValue
        updated.repeatIntervalSeconds = max(0, Double(repeatField.stringValue) ?? config.repeatIntervalSeconds)
        updated.volume = volumeSlider.doubleValue
        updated.blockKeyboard = blockCheckbox.state == .on
        return updated
    }

    @objc private func chooseSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.directoryURL = URL(fileURLWithPath: "/System/Library/Sounds")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        soundField.stringValue = url.path
    }

    @objc private func testSound() {
        onPreviewSound?(collect())
    }

    @objc private func save() {
        config = collect()
        onSave?(config)
        close()
    }

    @objc private func cancel() {
        close()
    }

    // El atajo global de Carbon se traga la combinación, así que hay que soltarlo mientras se graba.
    @objc private func startRecording() {
        guard recordingMonitor == nil else { return stopRecording() }
        onRecordingChange?(true)
        hotKeyButton.title = "Presioná la combinación…"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event: event)
            return nil
        }
    }

    private func capture(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var names: [String] = []
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.option) { names.append("option") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.command) { names.append("command") }

        guard !names.isEmpty else {
            hotKeyButton.title = "Usá al menos un modificador…"
            return
        }
        config.hotKey = HotKeyConfig(key: KeyCodes.name(for: UInt32(event.keyCode)), modifiers: names)
        stopRecording()
        hotKeyButton.title = config.hotKeyDescription
    }

    private func stopRecording() {
        if let monitor = recordingMonitor { NSEvent.removeMonitor(monitor) }
        recordingMonitor = nil
        onRecordingChange?(false)
        hotKeyButton.title = config.hotKeyDescription
    }
}
