import AppKit
import AVFoundation

enum AlarmState {
    case idle, arming, armed, firing
}

final class AlarmController {
    private(set) var state: AlarmState = .idle { didSet { onStateChange?(state) } }

    var onStateChange: ((AlarmState) -> Void)?
    var config: Config

    private let watcher = KeyWatcher()
    private let overlay = Overlay()
    private var player: AVAudioPlayer?
    private var armTimer: Timer?
    private var repeatTimer: Timer?
    private var spaceObserver: NSObjectProtocol?

    init(config: Config) {
        self.config = config
        watcher.onEvent = { [weak self] type, keyCode, flags in
            self?.handle(type: type, keyCode: keyCode, flags: flags) ?? false
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.config.triggerOnSpaceChange else { return }
            self.fire()
        }
    }

    deinit {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    var secondsRemaining: Int {
        guard let fire = armTimer?.fireDate else { return 0 }
        return max(0, Int(fire.timeIntervalSinceNow.rounded(.up)))
    }

    func toggle() {
        switch state {
        case .idle: activate()
        case .arming, .armed, .firing: deactivate()
        }
    }

    func activate() {
        guard state == .idle else { return }
        guard ensureAccessibility(), watcher.start() else {
            NSSound.beep()
            return
        }
        state = .arming
        armTimer?.invalidate()
        let timer = Timer(timeInterval: config.delaySeconds, repeats: false) { [weak self] _ in
            guard let self, self.state == .arming else { return }
            self.state = .armed
        }
        armTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func deactivate() {
        armTimer?.invalidate()
        armTimer = nil
        stopSound()
        overlay.hide()
        watcher.stop()
        state = .idle
    }

    /// Corre en el hilo del event tap: debe decidir sincrónicamente si traga la tecla.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        let isHotKey = isDeactivationShortcut(keyCode: keyCode, flags: flags)

        switch state {
        case .idle, .arming:
            return false

        case .armed:
            guard type == .keyDown, !isHotKey else { return false }
            DispatchQueue.main.async { [weak self] in self?.fire() }
            return config.blockKeyboard

        case .firing:
            // Con el teclado bloqueado el atajo no llega a Carbon: hay que desactivar acá.
            guard config.blockKeyboard else { return false }
            if isHotKey && type == .keyDown {
                DispatchQueue.main.async { [weak self] in self?.deactivate() }
            }
            return true
        }
    }

    private func isDeactivationShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard let hotKeyCode = config.hotKey.carbonKeyCode, Int64(hotKeyCode) == keyCode else { return false }
        var pressed: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { pressed.insert(.command) }
        if flags.contains(.maskAlternate) { pressed.insert(.option) }
        if flags.contains(.maskControl) { pressed.insert(.control) }
        if flags.contains(.maskShift) { pressed.insert(.shift) }
        return pressed == config.hotKey.cocoaFlags
    }

    private func fire() {
        guard state == .armed else { return }
        state = .firing
        overlay.show(message: config.message)
        startSound()
    }

    private func startSound() {
        playOnce()
        guard config.repeatIntervalSeconds > 0 else { return }
        let timer = Timer(timeInterval: config.repeatIntervalSeconds, repeats: true) { [weak self] _ in
            self?.playOnce()
        }
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func playOnce() {
        let url = URL(fileURLWithPath: (config.soundPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path), let player = try? AVAudioPlayer(contentsOf: url) else {
            NSSound.beep()
            return
        }
        player.numberOfLoops = config.repeatIntervalSeconds > 0 ? 0 : -1
        player.volume = Float(max(0, min(1, config.volume)))
        player.prepareToPlay()
        player.play()
        self.player = player
    }

    private func stopSound() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        player?.stop()
        player = nil
    }

    func previewSound() {
        stopSound()
        playOnce()
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func ensureAccessibility(prompt: Bool = true) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func reload(config: Config) {
        let wasActive = state != .idle
        deactivate()
        self.config = config
        if wasActive { activate() }
    }
}
