import Cocoa

private enum ModernStyle {
    static let beige = NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.95, alpha: 1)
    static let paper = NSColor.white
    static let ink = NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.15, alpha: 1)
    static let screen = NSColor(calibratedRed: 0.91, green: 0.96, blue: 0.94, alpha: 1)
    static let phosphor = NSColor(calibratedRed: 0.09, green: 0.49, blue: 0.37, alpha: 1)
    static let dimPhosphor = NSColor(calibratedRed: 0.37, green: 0.44, blue: 0.41, alpha: 1)
    static let amber = NSColor(calibratedRed: 0.96, green: 0.88, blue: 0.85, alpha: 1)
    static let border = NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.87, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.14, green: 0.77, blue: 0.57, alpha: 1)

    static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func box(_ frame: NSRect, fill: NSColor) -> NSBox {
        let box = NSBox(frame: frame)
        box.boxType = .custom
        box.fillColor = fill
        box.borderColor = border
        box.borderWidth = 1
        box.cornerRadius = 16
        return box
    }
}

final class GradientProgressBar: NSProgressIndicator {
    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 1, dy: 1)
        ModernStyle.border.setFill()
        NSBezierPath(roundedRect: track, xRadius: 7, yRadius: 7).fill()
        let fraction = CGFloat(min(100, max(0, doubleValue)) / 100)
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        if fill.width > 0 {
            let path = NSBezierPath(roundedRect: fill, xRadius: min(7, fill.width / 2), yRadius: 7)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSGradient(colors: [ModernStyle.ink, ModernStyle.accent, NSColor(calibratedRed: 0.93, green: 0.98, blue: 0.41, alpha: 1)])?.draw(in: fill, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class RedwoodButton: NSButton {
    private var normalColor: NSColor
    private var hoverColor: NSColor
    private var pressedColor: NSColor
    private var textColor: NSColor
    private var borderColor: NSColor
    private let disabledColor = ModernStyle.beige
    private let disabledBorderColor = ModernStyle.border
    private let disabledTextColor = ModernStyle.dimPhosphor
    private let mutedTextColor = ModernStyle.dimPhosphor
    private var trackingAreaRef: NSTrackingArea?
    private var hovering = false

    var isMuted = false {
        didSet {
            if isMuted {
                hovering = false
            }
            refreshColor()
        }
    }

    override var title: String {
        didSet {
            refreshColor()
        }
    }

    override var isEnabled: Bool {
        didSet {
            refreshColor()
        }
    }

    init(title: String, target: AnyObject?, action: Selector?, normal: NSColor, hover: NSColor, pressed: NSColor, text: NSColor, border: NSColor) {
        self.normalColor = normal
        self.hoverColor = hover
        self.pressedColor = pressed
        self.textColor = text
        self.borderColor = border
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        self.isBordered = false
        self.wantsLayer = true
        self.font = ModernStyle.font(12, weight: .bold)
        self.contentTintColor = text
        self.layer?.cornerRadius = 12
        self.layer?.borderWidth = 1
        self.layer?.borderColor = border.cgColor
        refreshColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        trackingAreaRef = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        if !isEnabled || isMuted { return }
        hovering = true
        updateColor(hoverColor)
    }

    override func mouseExited(with event: NSEvent) {
        if !isEnabled || isMuted { return }
        hovering = false
        updateColor(normalColor)
    }

    override func mouseDown(with event: NSEvent) {
        if !isEnabled || isMuted { return }
        updateColor(pressedColor)
        super.mouseDown(with: event)
        refreshColor()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw the title explicitly so AppKit does not dim its disabled color.
        let size = attributedTitle.size()
        attributedTitle.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                         y: (bounds.height - size.height) / 2))
    }

    func configureColors(normal: NSColor, hover: NSColor, pressed: NSColor, text: NSColor, border: NSColor) {
        self.normalColor = normal
        self.hoverColor = hover
        self.pressedColor = pressed
        self.textColor = text
        self.borderColor = border
        refreshColor()
    }

    private func refreshColor() {
        if isMuted {
            contentTintColor = mutedTextColor
            setTitleColor(mutedTextColor)
            layer?.backgroundColor = disabledColor.cgColor
            layer?.borderColor = disabledBorderColor.cgColor
        } else if isEnabled {
            contentTintColor = textColor
            setTitleColor(textColor)
            updateColor(hovering ? hoverColor : normalColor)
        } else {
            contentTintColor = textColor
            setTitleColor(textColor)
            layer?.backgroundColor = normalColor.cgColor
            layer?.borderColor = borderColor.cgColor
        }
        needsDisplay = true
    }

    private func setTitleColor(_ color: NSColor) {
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: color,
                .font: font ?? ModernStyle.font(12, weight: .bold)
            ]
        )
    }

    private func updateColor(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
        layer?.borderColor = borderColor.cgColor
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var progressBar: GradientProgressBar!
    var statusLabel: NSTextField!
    var pathLabel: NSTextField!
    var detailLabel: NSTextField!
    var progressTitleLabel: NSTextField!
    var progressPercentLabel: NSTextField!
    var stageIcons: [NSTextField] = []
    var stageStates: [NSTextField] = []
    var completedStages = 0
    var activeStage: Int?
    var startButton: NSButton!
    var stopButton: NSButton!
    var process: Process?
    var outputPipe: Pipe?
    var backupDidFinish = false
    var stopRequested = false
    var outputBuffer = ""
    var setupWindow: NSWindow?
    var setupFields: [String: NSTextField] = [:]
    var skipHiddenCheckbox: NSButton?

    let setupKeys = [
        "SOURCE_DIRS",
        "DRIVE_FOLDER_NAME",
        "DRIVE_PARENT_ID",
        "SKIP_HIDDEN",
        "MAX_WORKERS",
        "UPLOAD_CHUNK_MB",
        "SMALL_FILE_LIMIT_MB",
        "MAX_RETRIES",
        "RETRY_DELAY_SECONDS",
        "HTTP_TIMEOUT_SECONDS",
        "CACHE_SAVE_EVERY"
    ]

    let setupDefaults: [String: String] = [
        "SOURCE_DIRS": "",
        "DRIVE_FOLDER_NAME": "MyBackup",
        "DRIVE_PARENT_ID": "",
        "SKIP_HIDDEN": "true",
        "MAX_WORKERS": "12",
        "UPLOAD_CHUNK_MB": "32",
        "SMALL_FILE_LIMIT_MB": "20",
        "MAX_RETRIES": "4",
        "RETRY_DELAY_SECONDS": "5",
        "HTTP_TIMEOUT_SECONDS": "300",
        "CACHE_SAVE_EVERY": "500"
    ]

    let home: String = {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0])
        let appBundle = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return appBundle.deletingLastPathComponent().path
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        importSetupIfNeeded()
        for key in ["MAIL_ENABLED", "MAIL_CLIENT_ID", "MAIL_TENANT_ID", "MAIL_DRIVE_FOLDER_NAME"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        setupApplicationMenu()
        buildWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func setupApplicationMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MyBackup")

        appMenu.addItem(NSMenuItem(title: "À propos de MyBackup", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Réglages", action: #selector(showSetup), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem(title: "Ouvrir les journaux", action: #selector(openLog), keyEquivalent: "l"))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quitter MyBackup", action: #selector(quit), keyEquivalent: "q"))

        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(NSMenuItem(title: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenêtres")
        windowMenu.addItem(NSMenuItem(title: "Réduire", action: #selector(minimizeMainWindow), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Fermer les fenêtres", action: #selector(closeWindows), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    func buildDateText() -> String {
        let exePath = CommandLine.arguments[0]
        if let attrs = try? FileManager.default.attributesOfItem(atPath: exePath),
           let date = attrs[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "Unknown"
    }

    func bundleDateText() -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundleURL.path),
              let date = attributes[.modificationDate] as? Date else {
            return "--/--/----"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    func appBuildText() -> String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1.0"
        return "Build \(build)"
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MyBackup"
        alert.informativeText = "\(appBuildText())\n\(buildDateText())"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func closeWindows() {
        NSApp.windows.forEach { $0.orderOut(nil) }
    }

    @objc func minimizeMainWindow() {
        window?.miniaturize(nil)
    }

    func parsedEnvFile() -> [String: String] {
        let path = home + "/MyBackup.env"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || !line.contains("=") { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                values[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return values
    }

    func importSetupIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "SETUP_IMPORTED") { return }
        let envValues = parsedEnvFile()
        for key in setupKeys {
            let value = envValues[key] ?? setupDefaults[key] ?? ""
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: "SETUP_IMPORTED")
    }

    func setupValue(_ key: String) -> String {
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        return setupDefaults[key] ?? ""
    }

    func setupEnvironment() -> [String: String] {
        var env = ["MYBACKUP_HOME": home, "PYTHONNOUSERSITE": "1"]
        for key in setupKeys {
            env[key] = setupValue(key)
        }
        return env
    }

    func sourceFolders(from value: String) -> [String] {
        let separators = CharacterSet(charactersIn: "|\n")
        var seen = Set<String>()
        var folders: [String] = []
        for raw in value.components(separatedBy: separators) {
            let folder = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if folder.isEmpty || seen.contains(folder) { continue }
            seen.insert(folder)
            folders.append(folder)
        }
        return folders
    }

    func sourceFoldersDisplayValue(_ value: String) -> String {
        return sourceFolders(from: value).joined(separator: "\n")
    }

    func sourceFoldersStorageValue(_ value: String) -> String {
        return sourceFolders(from: value).joined(separator: "|")
    }

    func setupTextField(_ key: String, y: CGFloat, parent: NSView, width: CGFloat = 440, height: CGFloat = 26, labelX: CGFloat = 28, fieldX: CGFloat = 205, labelWidth: CGFloat = 155) {
        let names: [String: String] = [
            "SOURCE_DIRS": "Dossiers source",
            "DRIVE_FOLDER_NAME": "Dossier Drive",
            "MAX_WORKERS": "Transferts parallèles",
            "UPLOAD_CHUNK_MB": "Bloc d’envoi (Mo)",
            "SMALL_FILE_LIMIT_MB": "Petit fichier (Mo)",
            "MAX_RETRIES": "Tentatives",
            "RETRY_DELAY_SECONDS": "Délai reprise (s)",
            "HTTP_TIMEOUT_SECONDS": "Délai réseau (s)",
            "CACHE_SAVE_EVERY": "Cache / fichiers"
        ]
        let title = label(names[key] ?? key, size: 12, weight: .medium, color: ModernStyle.ink)
        title.frame = NSRect(x: labelX, y: y + max(5, (height - 22) / 2), width: labelWidth, height: 22)
        parent.addSubview(title)

        let initialValue = key == "SOURCE_DIRS" ? sourceFoldersDisplayValue(setupValue(key)) : setupValue(key)
        let field = NSTextField(string: initialValue)
        field.font = ModernStyle.font(12)
        field.backgroundColor = ModernStyle.paper
        field.textColor = ModernStyle.ink
        field.frame = NSRect(x: fieldX, y: y, width: width, height: height)
        if key == "SOURCE_DIRS" {
            field.usesSingleLineMode = false
            field.lineBreakMode = .byWordWrapping
            field.cell?.wraps = true
            field.cell?.isScrollable = false
        }
        parent.addSubview(field)
        setupFields[key] = field
    }

    func addInfoButton(_ key: String, x: CGFloat, y: CGFloat, parent: NSView) {
        let button = NSButton(title: "i", target: self, action: #selector(showParameterHelp))
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.bezelStyle = .regularSquare
        button.font = ModernStyle.font(11, weight: .bold)
        button.frame = NSRect(x: x, y: y + 1, width: 22, height: 22)
        parent.addSubview(button)
    }

    @objc func showParameterHelp(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        let titles: [String: String] = [
            "MAX_WORKERS": "Transferts parallèles",
            "UPLOAD_CHUNK_MB": "Bloc d’envoi",
            "SMALL_FILE_LIMIT_MB": "Petit fichier",
            "MAX_RETRIES": "Tentatives",
            "RETRY_DELAY_SECONDS": "Délai de reprise",
            "HTTP_TIMEOUT_SECONDS": "Délai réseau",
            "CACHE_SAVE_EVERY": "Fréquence du cache"
        ]
        let messages: [String: String] = [
            "MAX_WORKERS": "Nombre maximal de fichiers traités simultanément. Une valeur trop élevée peut ralentir Drive.",
            "UPLOAD_CHUNK_MB": "Taille des blocs utilisés pour les fichiers volumineux.",
            "SMALL_FILE_LIMIT_MB": "Au-dessous de ce seuil, le fichier est envoyé en une seule requête.",
            "MAX_RETRIES": "Nombre d’essais avant de signaler un échec de transfert.",
            "RETRY_DELAY_SECONDS": "Attente de base entre deux essais, augmentée à chaque nouvel essai.",
            "HTTP_TIMEOUT_SECONDS": "Durée maximale d’une requête vers Google Drive.",
            "CACHE_SAVE_EVERY": "Nombre de fichiers traités entre deux écritures du cache local."
        ]
        let alert = NSAlert()
        alert.messageText = titles[key] ?? key
        alert.informativeText = messages[key] ?? ""
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func showSetup() {
        if let existingSetupWindow = setupWindow {
            existingSetupWindow.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Réglages MyBackup"
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = ModernStyle.beige
        panel.delegate = self

        let content = NSView(frame: panel.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        setupFields = [:]

        let title = label("Réglages MyBackup", size: 23, weight: .semibold, color: ModernStyle.ink)
        title.frame = NSRect(x: 30, y: 844, width: 762, height: 29)
        content.addSubview(title)
        let hint = label("Les fichiers supprimés de vos dossiers locaux restent conservés dans Google Drive.", size: 12, color: ModernStyle.dimPhosphor)
        hint.frame = NSRect(x: 31, y: 820, width: 761, height: 19)
        content.addSubview(hint)

        let sourcesHeading = label("Dossiers à sauvegarder", size: 12, weight: .bold, color: ModernStyle.ink)
        sourcesHeading.frame = NSRect(x: 30, y: 770, width: 250, height: 20)
        content.addSubview(sourcesHeading)
        content.addSubview(ModernStyle.box(NSRect(x: 28, y: 559, width: 764, height: 204), fill: ModernStyle.paper))

        setupTextField("SOURCE_DIRS", y: 674, parent: content, width: 470, height: 58, labelX: 48, fieldX: 210, labelWidth: 155)
        let chooseButton = NSButton(title: "Ajouter", target: self, action: #selector(chooseSourceFolder))
        chooseButton.frame = NSRect(x: 691, y: 695, width: 85, height: 29)
        chooseButton.bezelStyle = .regularSquare
        chooseButton.font = ModernStyle.font(11, weight: .bold)
        content.addSubview(chooseButton)

        setupTextField("DRIVE_FOLDER_NAME", y: 628, parent: content, width: 470, height: 29, labelX: 48, fieldX: 210, labelWidth: 155)
        let skip = NSButton(checkboxWithTitle: "Ignorer les fichiers cachés", target: nil, action: nil)
        skip.frame = NSRect(x: 205, y: 582, width: 250, height: 27)
        skip.font = ModernStyle.font(12)
        skip.state = setupValue("SKIP_HIDDEN").lowercased() == "true" ? .on : .off
        skipHiddenCheckbox = skip
        content.addSubview(skip)
        let retentionNote = label("Conservation des suppressions dans Drive", size: 10, color: ModernStyle.ink)
        retentionNote.frame = NSRect(x: 460, y: 586, width: 310, height: 20)
        content.addSubview(retentionNote)

        for view in content.subviews {
            view.frame.origin.y -= 170
        }

        let performanceHeading = label("Transfert et performance", size: 12, weight: .bold, color: ModernStyle.ink)
        performanceHeading.frame = NSRect(x: 30, y: 365, width: 410, height: 20)
        content.addSubview(performanceHeading)
        content.addSubview(ModernStyle.box(NSRect(x: 28, y: 161, width: 764, height: 193), fill: ModernStyle.paper))

        setupTextField("MAX_WORKERS", y: 307, parent: content, width: 92, labelX: 48, fieldX: 225, labelWidth: 170)
        addInfoButton("MAX_WORKERS", x: 323, y: 307, parent: content)
        setupTextField("UPLOAD_CHUNK_MB", y: 267, parent: content, width: 92, labelX: 48, fieldX: 225, labelWidth: 170)
        addInfoButton("UPLOAD_CHUNK_MB", x: 323, y: 267, parent: content)
        setupTextField("SMALL_FILE_LIMIT_MB", y: 227, parent: content, width: 92, labelX: 48, fieldX: 225, labelWidth: 170)
        addInfoButton("SMALL_FILE_LIMIT_MB", x: 323, y: 227, parent: content)
        setupTextField("MAX_RETRIES", y: 187, parent: content, width: 92, labelX: 48, fieldX: 225, labelWidth: 170)
        addInfoButton("MAX_RETRIES", x: 323, y: 187, parent: content)

        setupTextField("RETRY_DELAY_SECONDS", y: 307, parent: content, width: 88, labelX: 422, fieldX: 650, labelWidth: 220)
        addInfoButton("RETRY_DELAY_SECONDS", x: 747, y: 307, parent: content)
        setupTextField("HTTP_TIMEOUT_SECONDS", y: 267, parent: content, width: 88, labelX: 422, fieldX: 650, labelWidth: 220)
        addInfoButton("HTTP_TIMEOUT_SECONDS", x: 747, y: 267, parent: content)
        setupTextField("CACHE_SAVE_EVERY", y: 227, parent: content, width: 88, labelX: 422, fieldX: 650, labelWidth: 220)
        addInfoButton("CACHE_SAVE_EVERY", x: 747, y: 227, parent: content)

        for view in content.subviews {
            view.frame.origin.y -= 80
        }

        let cancel = secondaryButton("Annuler", action: #selector(closeSetup))
        cancel.frame = NSRect(x: 555, y: 18, width: 105, height: 34)
        content.addSubview(cancel)
        let save = primaryButton("Enregistrer", action: #selector(saveSetup))
        save.frame = NSRect(x: 672, y: 18, width: 120, height: 34)
        content.addSubview(save)

        setupWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func chooseSourceFolder() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.prompt = "Choisir"
        if picker.runModal() == .OK {
            let existing = sourceFolders(from: setupFields["SOURCE_DIRS"]?.stringValue ?? "")
            let selected = picker.urls.map { $0.path }
            let combined = sourceFolders(from: (existing + selected).joined(separator: "\n"))
            setupFields["SOURCE_DIRS"]?.stringValue = combined.joined(separator: "\n")
        }
    }

    @objc func saveSetup() {
        let defaults = UserDefaults.standard
        for key in setupKeys where key != "SKIP_HIDDEN" && key != "DRIVE_PARENT_ID" {
            let rawValue = setupFields[key]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = key == "SOURCE_DIRS" ? sourceFoldersStorageValue(rawValue) : rawValue
            defaults.set(value, forKey: key)
        }
        defaults.set("", forKey: "DRIVE_PARENT_ID")
        defaults.set(skipHiddenCheckbox?.state == .on ? "true" : "false", forKey: "SKIP_HIDDEN")
        defaults.set(true, forKey: "SETUP_IMPORTED")
        defaults.synchronize()
        closeSetup()
    }

    @objc func closeSetup() {
        setupWindow?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === setupWindow {
            sender.orderOut(nil)
            return false
        }
        return true
    }

    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
        return NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
    }

    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = ModernStyle.font(size, weight: weight)
        field.textColor = color
        field.alignment = alignment
        field.lineBreakMode = .byTruncatingTail
        field.drawsBackground = false
        field.isBordered = false
        field.isEditable = false
        return field
    }

    func primaryButton(_ title: String, action: Selector) -> NSButton {
        return RedwoodButton(
            title: title,
            target: self,
            action: action,
            normal: ModernStyle.ink,
            hover: NSColor(calibratedRed: 0.23, green: 0.29, blue: 0.27, alpha: 1),
            pressed: ModernStyle.phosphor,
            text: ModernStyle.paper,
            border: ModernStyle.ink
        )
    }

    func secondaryButton(_ title: String, action: Selector) -> NSButton {
        return RedwoodButton(
            title: title,
            target: self,
            action: action,
            normal: ModernStyle.paper,
            hover: ModernStyle.beige,
            pressed: ModernStyle.border,
            text: ModernStyle.ink,
            border: ModernStyle.border
        )
    }

    func dangerButton(_ title: String, action: Selector) -> NSButton {
        return RedwoodButton(
            title: title,
            target: self,
            action: action,
            normal: ModernStyle.paper,
            hover: ModernStyle.amber,
            pressed: ModernStyle.amber.withAlphaComponent(0.8),
            text: ModernStyle.ink,
            border: ModernStyle.border
        )
    }

    func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 645, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "MyBackup"
        window.minSize = NSSize(width: 645, height: 480)
        window.backgroundColor = ModernStyle.beige
        window.delegate = self
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(quit)

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let title = label("MyBackup", size: 23, weight: .semibold, color: ModernStyle.ink)
        title.frame = NSRect(x: 30, y: 430, width: 360, height: 29)
        content.addSubview(title)
        let subtitle = label("Sauvegarde des fichiers vers Google Drive", size: 12, color: ModernStyle.dimPhosphor)
        subtitle.frame = NSRect(x: 31, y: 406, width: 380, height: 19)
        content.addSubview(subtitle)
        let settings = NSButton(title: "Réglages", target: self, action: #selector(showSetup))
        settings.frame = NSRect(x: 520, y: 426, width: 101, height: 31)
        settings.bezelStyle = .rounded
        settings.font = ModernStyle.font(12, weight: .medium)
        settings.toolTip = "Réglages"
        content.addSubview(settings)

        statusLabel = label("Prêt à sauvegarder", size: 19, weight: .semibold, color: ModernStyle.ink)
        statusLabel.frame = NSRect(x: 44, y: 357, width: 553, height: 27)
        content.addSubview(statusLabel)
        detailLabel = label("Vos fichiers seront copiés vers Google Drive.", size: 12, color: ModernStyle.dimPhosphor)
        detailLabel.frame = NSRect(x: 44, y: 333, width: 553, height: 20)
        content.addSubview(detailLabel)
        pathLabel = label("", size: 11, color: ModernStyle.dimPhosphor)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.frame = NSRect(x: 44, y: 310, width: 553, height: 18)
        content.addSubview(pathLabel)
        progressTitleLabel = label("Progression", size: 11, weight: .medium, color: ModernStyle.dimPhosphor)
        progressTitleLabel.frame = NSRect(x: 44, y: 282, width: 250, height: 18)
        content.addSubview(progressTitleLabel)
        progressPercentLabel = label("—", size: 12, weight: .semibold, color: ModernStyle.ink, alignment: .right)
        progressPercentLabel.frame = NSRect(x: 510, y: 282, width: 87, height: 18)
        content.addSubview(progressPercentLabel)
        progressBar = GradientProgressBar(frame: NSRect(x: 44, y: 260, width: 553, height: 14))
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0
        progressBar.isIndeterminate = false
        content.addSubview(progressBar)

        content.addSubview(ModernStyle.box(NSRect(x: 24, y: 40, width: 597, height: 203), fill: ModernStyle.paper))
        let stagesTitle = label("Étapes de la sauvegarde", size: 14, weight: .semibold, color: ModernStyle.ink)
        stagesTitle.frame = NSRect(x: 45, y: 210, width: 390, height: 21)
        content.addSubview(stagesTitle)
        let stageNames = ["Analyser les dossiers", "Préparer Google Drive", "Sauvegarder les fichiers"]
        stageIcons = []
        stageStates = []
        for (index, name) in stageNames.enumerated() {
            let y = CGFloat(174 - index * 32)
            let icon = label("○", size: 18, weight: .medium, color: ModernStyle.dimPhosphor, alignment: .center)
            icon.frame = NSRect(x: 45, y: y - 1, width: 25, height: 24)
            content.addSubview(icon)
            stageIcons.append(icon)
            let stageName = label(name, size: 12, weight: .medium, color: ModernStyle.ink)
            stageName.frame = NSRect(x: 80, y: y, width: 365, height: 20)
            content.addSubview(stageName)
            let state = label("À venir", size: 11, color: ModernStyle.dimPhosphor, alignment: .right)
            state.frame = NSRect(x: 484, y: y, width: 113, height: 20)
            content.addSubview(state)
            stageStates.append(state)
        }

        startButton = primaryButton("Lancer la sauvegarde", action: #selector(startBackup))
        startButton.frame = NSRect(x: 44, y: 54, width: 382, height: 40)
        content.addSubview(startButton)
        stopButton = secondaryButton("Fermer", action: #selector(quit))
        stopButton.frame = NSRect(x: 438, y: 54, width: 159, height: 40)
        content.addSubview(stopButton)

        let footer = label("Dossiers locaux  →  Google Drive", size: 10, color: ModernStyle.dimPhosphor)
        footer.frame = NSRect(x: 30, y: 8, width: 330, height: 18)
        content.addSubview(footer)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let buildLabel = label("\(bundleDateText()) - Bundle \(build)", size: 10, color: ModernStyle.dimPhosphor, alignment: .right)
        buildLabel.frame = NSRect(x: 385, y: 8, width: 236, height: 18)
        content.addSubview(buildLabel)
    }

    @objc func startBackup() {
        if process != nil { return }
        backupDidFinish = false
        stopRequested = false
        outputBuffer = ""
        setProgress(0, title: "Progression")
        completedStages = 0
        updateStages(active: 0)
        statusLabel.stringValue = "Démarrage de la sauvegarde"
        pathLabel.stringValue = ""
        detailLabel.stringValue = ""
        setBackupControls(isRunning: true)

        let exe = URL(fileURLWithPath: CommandLine.arguments[0])
        let contents = exe.deletingLastPathComponent().deletingLastPathComponent()
        let python = contents.appendingPathComponent("Resources/venv/bin/python").path
        let backend = contents.appendingPathComponent("Resources/backend/backend.py").path

        appendLaunchLog("Backend startup\nPYTHON=\(python)\nBACKEND=\(backend)\n")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [backend]
        p.currentDirectoryURL = URL(fileURLWithPath: home)
        p.environment = setupEnvironment()

        let pipe = Pipe()
        outputPipe = pipe
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.consume(text)
                }
            }
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                if let handle = self?.outputPipe?.fileHandleForReading {
                    handle.readabilityHandler = nil
                    try? handle.close()
                }
                self?.outputPipe = nil
                self?.process = nil
                self?.setBackupControls(isRunning: false)
                if self?.backupDidFinish == true {
                    self?.showCloseButton()
                } else if self?.stopRequested == true {
                    self?.statusLabel.stringValue = "Sauvegarde arrêtée"
                    self?.pathLabel.stringValue = ""
                    self?.detailLabel.stringValue = "Arrêt demandé par l’utilisateur"
                    self?.updateStages(active: nil)
                    self?.backupDidFinish = false
                    self?.stopRequested = false
                } else if proc.terminationStatus != 0 && self?.backupDidFinish != true {
                    self?.statusLabel.stringValue = "Sauvegarde interrompue"
                    self?.detailLabel.stringValue = "Consultez les journaux pour comprendre l’erreur."
                    self?.updateStages(active: self?.activeStage, failed: true)
                }
            }
        }

        do {
            try p.run()
            process = p
        } catch {
            setBackupControls(isRunning: false)
            statusLabel.stringValue = "Impossible de démarrer la sauvegarde"
            detailLabel.stringValue = error.localizedDescription
            updateStages(active: 0, failed: true)
            appendLaunchLog("Launch failed: \(error)\n")
        }
    }

    @objc func stopBackup() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        statusLabel.stringValue = "Arrêt en cours…"
        pathLabel.stringValue = ""
        stopButton.isEnabled = false
        process.terminate()
    }

    func setBackupControls(isRunning: Bool) {
        startButton.title = isRunning ? "Sauvegarde en cours" : "Lancer la sauvegarde"
        if let startButton = startButton as? RedwoodButton {
            startButton.isMuted = false
        }
        startButton.isEnabled = !isRunning
        if !isRunning {
            showCloseButton()
            return
        }
        if let stopButton = stopButton as? RedwoodButton {
            stopButton.configureColors(
                normal: ModernStyle.paper,
                hover: ModernStyle.amber,
                pressed: ModernStyle.amber.withAlphaComponent(0.8),
                text: ModernStyle.ink,
                border: ModernStyle.border
            )
        }
        stopButton.title = "Arrêter"
        stopButton.target = self
        stopButton.action = #selector(stopBackup)
        stopButton.isEnabled = isRunning
    }

    func showCloseButton() {
        if let stopButton = stopButton as? RedwoodButton {
            stopButton.configureColors(
                normal: ModernStyle.paper,
                hover: ModernStyle.beige,
                pressed: ModernStyle.border,
                text: ModernStyle.ink,
                border: ModernStyle.border
            )
        }
        stopButton.title = "Fermer"
        stopButton.target = self
        stopButton.action = #selector(quit)
        stopButton.isEnabled = true
    }

    func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    func setProgress(_ value: Double, title: String) {
        let percentage = min(100, max(0, value))
        progressBar.doubleValue = percentage
        progressBar.needsDisplay = true
        progressTitleLabel.stringValue = title
        progressPercentLabel.stringValue = percentage == 0 ? "—" : "\(Int(percentage.rounded())) %"
    }

    func updateStages(active: Int?, completed: Int? = nil, failed: Bool = false) {
        if let completed { completedStages = completed }
        activeStage = active
        for index in stageIcons.indices {
            let icon = stageIcons[index]
            let state = stageStates[index]
            if index < completedStages {
                icon.stringValue = "✓"
                icon.textColor = ModernStyle.phosphor
                state.stringValue = "Terminé"
                state.textColor = ModernStyle.phosphor
            } else if index == active {
                icon.stringValue = failed ? "!" : "●"
                icon.textColor = failed ? NSColor.systemRed : ModernStyle.phosphor
                state.stringValue = failed ? "Erreur" : "En cours"
                state.textColor = icon.textColor
            } else {
                icon.stringValue = "○"
                icon.textColor = ModernStyle.dimPhosphor
                state.stringValue = "À venir"
                state.textColor = ModernStyle.dimPhosphor
            }
        }
    }

    func consume(_ text: String) {
        outputBuffer += text
        while let range = outputBuffer.range(of: "\n") {
            let line = String(outputBuffer[..<range.lowerBound])
            outputBuffer = String(outputBuffer[range.upperBound...])
            handleLine(line)
        }
    }

    func localizedStatus(_ message: String) -> String {
        let messages: [String: String] = [
            "Authenticating with Google Drive...": "Connexion à Google Drive…",
            "Finding the Drive root folder...": "Recherche du dossier Drive…",
            "Scanning local folders and files...": "Analyse des dossiers…",
            "Detecting changed files...": "Détection des modifications…",
            "Preparing Drive folders...": "Préparation des dossiers Drive…",
            "Backing up files...": "Sauvegarde des fichiers…"
        ]
        return messages[message] ?? message
    }

    func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String else {
            appendLaunchLog(line + "\n")
            return
        }

        if event == "status" {
            let message = obj["message"] as? String ?? "Traitement en cours…"
            statusLabel.stringValue = localizedStatus(message)
            if message == "Preparing Drive folders..." {
                updateStages(active: 1, completed: 1)
            } else if message == "Backing up files..." {
                updateStages(active: 2, completed: 2)
            }
        } else if event == "scan_done" {
            let folders = obj["folders"] as? Int ?? 0
            let files = obj["files"] as? Int ?? 0
            let elapsed = obj["elapsed"] as? Int ?? 0
            detailLabel.stringValue = "\(folders) dossiers · \(files) fichiers · \(formatDuration(elapsed))"
        } else if event == "folder_progress" {
            let checked = obj["checked"] as? Int ?? 0
            let total = obj["total"] as? Int ?? 0
            let created = obj["created"] as? Int ?? 0
            let elapsed = obj["elapsed"] as? Int ?? 0
            let current = obj["current"] as? String ?? ""
            statusLabel.stringValue = "Préparation des dossiers Drive…"
            updateStages(active: 1, completed: 1)
            pathLabel.stringValue = current
            setProgress(total > 0 ? Double(checked) * 100.0 / Double(total) : 0, title: "Progression des dossiers")
            detailLabel.stringValue = "\(checked)/\(total) dossiers · \(created) créés · \(formatDuration(elapsed))"
        } else if event == "upload_progress" {
            let pct = obj["percent"] as? Double ?? Double(obj["percent"] as? Int ?? 0)
            let done = obj["done"] as? Int ?? 0
            let total = obj["total"] as? Int ?? 0
            let created = obj["created"] as? Int ?? 0
            let updated = obj["updated"] as? Int ?? 0
            let skipped = obj["skipped"] as? Int ?? 0
            let errors = obj["errors"] as? Int ?? 0
            let elapsed = obj["elapsed"] as? Int ?? 0
            statusLabel.stringValue = "Sauvegarde des fichiers…"
            updateStages(active: 2, completed: 2)
            pathLabel.stringValue = ""
            setProgress(pct, title: "Progression des fichiers")
            detailLabel.stringValue = "\(done)/\(total) fichiers · \(created) créés · \(updated) mis à jour · \(skipped) ignorés · \(errors) erreurs · \(formatDuration(elapsed))"
        } else if event == "done" {
            let elapsed = obj["elapsed"] as? Int ?? 0
            let stats = obj["stats"] as? [String: Any] ?? [:]
            let total = stats["total"] as? Int ?? 0
            let copied = stats["created"] as? Int ?? 0
            let updated = stats["updated"] as? Int ?? 0
            let skipped = stats["skipped"] as? Int ?? 0
            let errors = stats["errors"] as? Int ?? 0
            setProgress(100, title: "Sauvegarde terminée")
            updateStages(active: nil, completed: 3)
            statusLabel.stringValue = errors > 0 ? "Sauvegarde terminée avec erreurs" : "Sauvegarde terminée"
            pathLabel.stringValue = "\(copied) créés · \(updated) mis à jour · \(skipped) ignorés · \(errors) erreurs"
            detailLabel.stringValue = "\(total) fichiers · \(formatDuration(elapsed))"
            backupDidFinish = true
            stopRequested = false
            setBackupControls(isRunning: false)
            showCloseButton()
        } else if event == "error" {
            statusLabel.stringValue = "Une erreur est survenue"
            pathLabel.stringValue = obj["message"] as? String ?? ""
            detailLabel.stringValue = "Consultez les journaux pour en savoir plus."
            updateStages(active: activeStage, failed: true)
            backupDidFinish = false
            setBackupControls(isRunning: false)
        }
    }

    func appendLaunchLog(_ text: String) {
        let path = home + "/MyBackup.launch.log"
        let prefix = "\(Date()) "
        let data = (prefix + text).data(using: .utf8)!
        if FileManager.default.fileExists(atPath: path), let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            fh.seekToEndOfFile()
            fh.write(data)
            try? fh.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    @objc func openLog() {
        let path = home + "/MyBackup.log"
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: Data(), attributes: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func quit() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
