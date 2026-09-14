import AppKit

extension Notification.Name {
    static let macAlarmOpenSettings = Notification.Name("com.franco.macalarm.openSettings")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: AlarmController!
    private var settingsWindow: SettingsWindowController?
    private var stateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // `--settings` desde la terminal es la vía de entrada cuando el ícono no entra en la barra.
        if CommandLine.arguments.contains("--check") {
            print(AXIsProcessTrusted() ? "trusted" : "NOT trusted")
            NSApp.terminate(nil)
            return
        }

        let wantsSettings = CommandLine.arguments.contains("--settings")
        if wantsSettings, !otherInstances().isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                .macAlarmOpenSettings, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        enforceSingleInstance()

        DistributedNotificationCenter.default().addObserver(
            forName: .macAlarmOpenSettings, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettings()
        }

        controller = AlarmController(config: Config.load())
        controller.onStateChange = { [weak self] _ in self?.refreshUI() }

        // Con la barra llena macOS ubica el ítem nuevo en el centro, es decir detrás de la notch.
        // Forzar la posición preferida al extremo derecho lo saca de ahí en el primer arranque.
        let autosaveName = "MacAlarm"
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(0, forKey: positionKey)
        }
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(autosaveName)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = autosaveName
        statusItem.behavior = []
        statusItem.isVisible = true
        statusItem.menu = buildMenu()

        registerHotKey()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.controller.state == .arming else { return }
            self.refreshUI()
        }
        refreshUI()
        warnIfStatusItemHidden()
        if wantsSettings { openSettings() }
    }

    // MARK: - Estado

    private func refreshUI() {
        guard let button = statusItem.button else { return }
        let (symbol, suffix): (String, String)
        switch controller.state {
        case .idle: (symbol, suffix) = ("bell.slash", "")
        case .arming: (symbol, suffix) = ("timer", " \(controller.secondsRemaining)")
        case .armed: (symbol, suffix) = ("bell.fill", "")
        case .firing: (symbol, suffix) = ("bell.and.waves.left.and.right.fill", "")
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacAlarm")
        button.image?.isTemplate = true
        button.imagePosition = suffix.isEmpty ? .imageOnly : .imageLeading
        button.title = suffix
        button.toolTip = "MacAlarm — \(controller.config.hotKeyDescription)"
        stateItem.title = stateTitle
        toggleItem.title = (controller.state == .idle ? "Activar alarma" : "Desactivar alarma")
            + "  (\(controller.config.hotKeyDescription))"
    }

    private var stateTitle: String {
        guard controller.isTrusted else { return "⚠︎ Falta permiso de accesibilidad" }
        switch controller.state {
        case .idle: return "Inactiva"
        case .arming: return "Armándose — \(controller.secondsRemaining)s"
        case .armed: return "Armada — esperando una tecla"
        case .firing: return "¡SONANDO!"
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        toggleItem = item("Activar alarma", #selector(toggleAlarm))
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(item("Configuración…", #selector(openSettings)))
        menu.addItem(item("Abrir config.json", #selector(editConfig)))
        menu.addItem(item("Permisos de accesibilidad…", #selector(openAccessibility)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    // MARK: - Acciones

    @objc private func toggleAlarm() { controller.toggle() }

    @objc private func openSettings() {
        let window = SettingsWindowController(config: controller.config)
        window.onSave = { [weak self] config in
            config.save()
            self?.controller.reload(config: config)
            self?.registerHotKey()
            self?.refreshUI()
        }
        window.onPreviewSound = { [weak self] config in
            let previous = self?.controller.config
            self?.controller.config = config
            self?.controller.previewSound()
            if let previous { self?.controller.config = previous }
        }
        window.onRecordingChange = { recording in
            if recording { HotKeyCenter.shared.unregister() } else { self.registerHotKey() }
        }
        settingsWindow = window
        window.present()
    }

    @objc private func editConfig() {
        _ = Config.load()
        NSWorkspace.shared.open(Config.url)
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Infraestructura

    private func registerHotKey() {
        HotKeyCenter.shared.onTrigger = { [weak self] in self?.controller.toggle() }
        guard let code = controller.config.hotKey.carbonKeyCode,
              HotKeyCenter.shared.register(keyCode: code, modifiers: controller.config.hotKey.carbonModifiers) else {
            notify("MacAlarm", "No se pudo registrar el atajo \(controller.config.hotKeyDescription). Elegí otro en Configuración.")
            return
        }
    }

    private func otherInstances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    private func enforceSingleInstance() {
        otherInstances().forEach { $0.terminate() }
    }

    // NSStatusItem queda oculto sin aviso cuando la barra no tiene espacio o un gestor
    // tipo Ice/Bartender se la queda: sin este chequeo la app parece no haber arrancado.
    private func warnIfStatusItemHidden() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let width = self.statusItem.button?.window?.frame.width ?? 0
            guard !self.statusItem.isVisible || width == 0 else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "MacAlarm está corriendo, pero su ícono no entra en la barra"
            alert.informativeText = "Liberá espacio en la barra de menú (o revisá tu gestor de íconos: Ice, Bartender, etc.).\n\nEl atajo \(self.controller.config.hotKeyDescription) y la configuración funcionan igual."
            alert.addButton(withTitle: "Abrir configuración")
            alert.addButton(withTitle: "Cerrar")
            if alert.runModal() == .alertFirstButtonReturn { self.openSettings() }
        }
    }

    private func notify(_ title: String, _ body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.runModal()
    }
}
