import Cocoa

private enum ModernStyle {
    static let beige = NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.95, alpha: 1)
    static let paper = NSColor.white
    static let ink = NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.15, alpha: 1)
    static let phosphor = NSColor(calibratedRed: 0.09, green: 0.49, blue: 0.37, alpha: 1)
    static let dimPhosphor = NSColor(calibratedRed: 0.37, green: 0.44, blue: 0.41, alpha: 1)
    static let border = NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.87, alpha: 1)

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

final class TopAlignedView: NSView {
    override var isFlipped: Bool { true }
}

final class BackupProgressBar: NSProgressIndicator {
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
            ModernStyle.phosphor.setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var progressBar: BackupProgressBar!
    var statusLabel: NSTextField!
    var pathLabel: NSTextField!
    var detailLabel: NSTextField!
    var progressTitleLabel: NSTextField!
    var progressPercentLabel: NSTextField!
    var stageIcons: [NSTextField] = []
    var stageStates: [NSTextField] = []
    var metrics: [NSTextField] = []
    var elapsedLabel: NSTextField!
    var sourcesLabel: NSTextField!
    var destinationLabel: NSTextField!
    var retentionLabel: NSTextField!
    var detailsStack: NSStackView!
    var workspace: NSStackView!
    var mainCard: NSView!
    var sidePanel: NSStackView!
    var sideWidth: NSLayoutConstraint!
    var compactConstraints: [NSLayoutConstraint] = []
    var compactLayout: Bool?
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
    var keepRemovedCheckbox: NSButton?

    let setupKeys = [
        "SOURCE_DIRS",
        "DRIVE_FOLDER_NAME",
        "DRIVE_PARENT_ID",
        "SKIP_HIDDEN",
        "DELETE_REMOVED",
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
        "DELETE_REMOVED": "false",
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
        // Older versions imported this dormant flag without offering a choice.
        // Require an explicit save in the new UI before enabling remote cleanup.
        if key == "DELETE_REMOVED" && !UserDefaults.standard.bool(forKey: "RETENTION_CHOICE_SAVED") {
            return "false"
        }
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

    @objc func showSetup() {
        if let existingSetupWindow = setupWindow {
            existingSetupWindow.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Réglages MyBackup"
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = ModernStyle.beige
        panel.appearance = NSAppearance(named: .aqua)
        panel.delegate = self
        setupFields = [:]
        let content = panel.contentView!
        let sourcesTitle = label("Dossiers à sauvegarder", size: 14, weight: .semibold, color: ModernStyle.ink)
        let sources = NSTextField(string: sourceFoldersDisplayValue(setupValue("SOURCE_DIRS")))
        sources.font = ModernStyle.font(13)
        sources.usesSingleLineMode = false
        sources.lineBreakMode = .byWordWrapping
        sources.cell?.wraps = true
        sources.cell?.isScrollable = false
        sources.heightAnchor.constraint(equalToConstant: 76).isActive = true
        sources.setAccessibilityLabel("Dossiers à sauvegarder, un chemin par ligne")
        setupFields["SOURCE_DIRS"] = sources
        let add = NSButton(title: "Ajouter un dossier…", target: self, action: #selector(chooseSourceFolder))
        add.bezelStyle = .rounded
        let sourceBody = stack([sourcesTitle, sources, label("Un chemin par ligne. Le bouton Ajouter ouvre le Finder.", size: 12, color: ModernStyle.dimPhosphor), add], spacing: 10)
        fillWidth(sources, in: sourceBody)
        let destinationTitle = label("Dossier de destination dans Google Drive", size: 14, weight: .semibold, color: ModernStyle.ink)
        let destination = NSTextField(string: setupValue("DRIVE_FOLDER_NAME"))
        destination.font = ModernStyle.font(13)
        destination.setAccessibilityLabel("Nom du dossier de destination dans Google Drive")
        setupFields["DRIVE_FOLDER_NAME"] = destination
        let skip = NSButton(checkboxWithTitle: "Ignorer les fichiers cachés", target: nil, action: nil)
        skip.state = setupValue("SKIP_HIDDEN").lowercased() == "true" ? .on : .off
        skipHiddenCheckbox = skip
        let keep = NSButton(checkboxWithTitle: "Conserver dans Drive les fichiers supprimés de la source", target: nil, action: nil)
        keep.state = setupValue("DELETE_REMOVED").lowercased() == "true" ? .off : .on
        keepRemovedCheckbox = keep
        let explanation = label("Si cette option est décochée, les copies suivies sont mises à la corbeille Drive après une sauvegarde sans erreur. Les dossiers sont conservés.", size: 12, color: ModernStyle.dimPhosphor)
        explanation.maximumNumberOfLines = 3
        explanation.lineBreakMode = .byWordWrapping
        let options = stack([destinationTitle, destination, skip, keep, explanation], spacing: 12)
        fillWidth(destination, in: options)
        fillWidth(explanation, in: options)
        let cancel = NSButton(title: "Annuler", target: self, action: #selector(closeSetup))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Enregistrer", target: self, action: #selector(saveSetup))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let flexible = NSView()
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = stack([flexible, cancel, save], horizontal: true, spacing: 12)
        let root = stack([card(sourceBody), card(options), actions], spacing: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        root.arrangedSubviews.forEach { fillWidth($0, in: root) }
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)
        ])

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
        for key in setupKeys where key != "SKIP_HIDDEN" && key != "DELETE_REMOVED" && key != "DRIVE_PARENT_ID" {
            guard let field = setupFields[key] else { continue }
            let rawValue = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = key == "SOURCE_DIRS" ? sourceFoldersStorageValue(rawValue) : rawValue
            defaults.set(value, forKey: key)
        }
        defaults.set("", forKey: "DRIVE_PARENT_ID")
        defaults.set(skipHiddenCheckbox?.state == .on ? "true" : "false", forKey: "SKIP_HIDDEN")
        defaults.set(keepRemovedCheckbox?.state == .off ? "true" : "false", forKey: "DELETE_REMOVED")
        defaults.set(true, forKey: "RETENTION_CHOICE_SAVED")
        defaults.set(true, forKey: "SETUP_IMPORTED")
        defaults.synchronize()
        refreshLocation()
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

    // Auto Layout keeps the same hierarchy in the compact and wide layouts.
    func stack(_ views: [NSView], horizontal: Bool = false, spacing: CGFloat = 16) -> NSStackView {
        let result = NSStackView(views: views)
        result.orientation = horizontal ? .horizontal : .vertical
        result.alignment = horizontal ? .centerY : .leading
        result.spacing = spacing
        return result
    }

    func fillWidth(_ view: NSView, in parent: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
    }

    func card(_ body: NSStackView) -> NSView {
        let box = ModernStyle.box(.zero, fill: ModernStyle.paper)
        box.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        box.contentView!.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 22),
            body.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -22),
            body.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 22),
            body.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -22)
        ])
        return box
    }

    func separator() -> NSBox {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MyBackup"
        window.minSize = NSSize(width: 640, height: 600)
        window.backgroundColor = ModernStyle.beige
        window.appearance = NSAppearance(named: .aqua)
        window.delegate = self
        window.center()
        let content = window.contentView!
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        let document = TopAlignedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let title = label("MyBackup", size: 25, weight: .semibold, color: ModernStyle.ink)
        let subtitle = label("Vos dossiers, sauvegardés sur Google Drive.", size: 13, color: ModernStyle.dimPhosphor)
        let heading = stack([title, subtitle], spacing: 4)
        let settings = NSButton(title: "Réglages", target: self, action: #selector(showSetup))
        settings.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = stack([heading, spacer, settings], horizontal: true)

        statusLabel = label("Prêt à sauvegarder", size: 25, weight: .semibold, color: ModernStyle.ink)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.setAccessibilityRole(.staticText)
        detailLabel = label("Lancez la sauvegarde de vos dossiers vers Google Drive.", size: 13, color: ModernStyle.dimPhosphor)
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 3
        progressPercentLabel = label("—", size: 48, weight: .semibold, color: ModernStyle.ink)
        progressTitleLabel = label("En attente du démarrage", size: 13, color: ModernStyle.dimPhosphor)
        progressBar = BackupProgressBar()
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.isIndeterminate = false
        progressBar.setAccessibilityLabel("Progression de l’étape actuelle")
        progressBar.heightAnchor.constraint(equalToConstant: 10).isActive = true
        metrics = []
        let metricViews = ["Créés", "Mis à jour", "Inchangés", "Erreurs"].map { name -> NSView in
            let value = label("—", size: 23, weight: .semibold, color: ModernStyle.ink)
            value.setAccessibilityLabel(name)
            metrics.append(value)
            return stack([value, label(name, size: 12, color: ModernStyle.dimPhosphor)], spacing: 5)
        }
        let metricRow = stack(metricViews, horizontal: true)
        metricRow.distribution = .fillEqually
        elapsedLabel = label("Temps écoulé : —", size: 13, color: ModernStyle.dimPhosphor)
        let body = stack([statusLabel, detailLabel, progressPercentLabel, progressTitleLabel, progressBar, metricRow, separator(), elapsedLabel], spacing: 18)
        for view in [statusLabel!, detailLabel!, progressBar!, metricRow, body.arrangedSubviews[6]] { fillWidth(view, in: body) }
        mainCard = card(body)

        stageIcons = []
        stageStates = []
        let stages = stack([label("Parcours de sauvegarde", size: 15, weight: .semibold, color: ModernStyle.ink)], spacing: 20)
        for name in ["Analyse des dossiers", "Préparation de Drive", "Sauvegarde des fichiers"] {
            let icon = label("○", size: 19, color: ModernStyle.dimPhosphor)
            icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
            icon.setAccessibilityElement(false)
            let state = label("À venir", size: 12, color: ModernStyle.dimPhosphor)
            let row = stack([icon, stack([label(name, size: 13, weight: .medium, color: ModernStyle.ink), state], spacing: 4)], horizontal: true, spacing: 10)
            stages.addArrangedSubview(row)
            stageIcons.append(icon)
            stageStates.append(state)
        }
        sourcesLabel = label("", size: 13, color: ModernStyle.ink)
        sourcesLabel.maximumNumberOfLines = 3
        sourcesLabel.lineBreakMode = .byWordWrapping
        destinationLabel = label("", size: 13, weight: .medium, color: ModernStyle.ink)
        destinationLabel.lineBreakMode = .byTruncatingMiddle
        destinationLabel.isSelectable = true
        let location = stack([label("Emplacement", size: 15, weight: .semibold, color: ModernStyle.ink), sourcesLabel, separator(), label("Vers Google Drive", size: 12, color: ModernStyle.dimPhosphor), destinationLabel], spacing: 12)
        for view in [sourcesLabel!, destinationLabel!, location.arrangedSubviews[2]] { fillWidth(view, in: location) }
        sidePanel = stack([card(stages), card(location)], spacing: 16)
        sidePanel.translatesAutoresizingMaskIntoConstraints = false
        sidePanel.arrangedSubviews.forEach { fillWidth($0, in: sidePanel) }
        sideWidth = sidePanel.widthAnchor.constraint(equalToConstant: 300)
        sideWidth.isActive = true
        workspace = stack([mainCard, sidePanel], horizontal: true, spacing: 18)
        workspace.distribution = .fill
        workspace.alignment = .top
        mainCard.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        let details = NSButton(checkboxWithTitle: "Afficher les détails", target: self, action: #selector(toggleDetails(_:)))
        details.setButtonType(.switch)
        pathLabel = label("Aucun détail pour le moment.", size: 12, color: ModernStyle.dimPhosphor)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.isSelectable = true
        let logs = NSButton(title: "Ouvrir les journaux", target: self, action: #selector(openLog))
        logs.bezelStyle = .rounded
        detailsStack = stack([pathLabel, logs], spacing: 8)
        fillWidth(pathLabel, in: detailsStack)
        detailsStack.isHidden = true
        startButton = NSButton(title: "Sauvegarder maintenant", target: self, action: #selector(startBackup))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.bezelColor = ModernStyle.phosphor
        startButton.contentTintColor = .white
        stopButton = NSButton(title: "Arrêter la sauvegarde", target: self, action: #selector(stopBackup))
        stopButton.bezelStyle = .rounded
        stopButton.isHidden = true
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = stack([details, actionSpacer, startButton, stopButton], horizontal: true, spacing: 12)
        retentionLabel = label("", size: 12, color: ModernStyle.dimPhosphor)
        retentionLabel.maximumNumberOfLines = 3
        retentionLabel.lineBreakMode = .byWordWrapping
        let root = stack([header, workspace, actions, detailsStack, separator(), retentionLabel], spacing: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        root.arrangedSubviews.forEach { fillWidth($0, in: root) }
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 28),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        refreshLocation()
        windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
    }

    @objc func toggleDetails(_ sender: NSButton) {
        detailsStack.isHidden = sender.state != .on
    }

    func refreshLocation() {
        guard sourcesLabel != nil else { return }
        let folders = sourceFolders(from: setupValue("SOURCE_DIRS"))
        sourcesLabel.stringValue = folders.isEmpty ? "Aucun dossier sélectionné · Ouvrez Réglages" : folders.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: " · ")
        sourcesLabel.toolTip = folders.joined(separator: "\n")
        destinationLabel.stringValue = "Mon Drive / " + setupValue("DRIVE_FOLDER_NAME")
        destinationLabel.toolTip = destinationLabel.stringValue
        retentionLabel.stringValue = setupValue("DELETE_REMOVED").lowercased() == "true"
            ? "Conservation Drive : les copies suivies des fichiers supprimés sont mises à la corbeille après une sauvegarde sans erreur."
            : "Conservation Drive : les fichiers supprimés de la source restent sauvegardés."
    }

    func windowDidResize(_ notification: Notification) {
        guard workspace != nil else { return }
        let compact = window.contentView!.bounds.width < 900
        guard compactLayout != compact else { return }
        compactLayout = compact
        NSLayoutConstraint.deactivate(compactConstraints)
        compactConstraints = []
        sideWidth.isActive = !compact
        workspace.orientation = compact ? .vertical : .horizontal
        workspace.alignment = compact ? .leading : .top
        if compact {
            compactConstraints = [mainCard!, sidePanel!].map { $0.widthAnchor.constraint(equalTo: workspace.widthAnchor) }
            NSLayoutConstraint.activate(compactConstraints)
        }
    }

    func updateMetrics(_ event: [String: Any]) {
        for (index, key) in ["created", "updated", "skipped", "errors"].enumerated() {
            metrics[index].stringValue = String(event[key] as? Int ?? 0)
        }
        elapsedLabel.stringValue = "Temps écoulé : " + formatDuration(event["elapsed"] as? Int ?? 0)
    }

    @objc func startBackup() {
        if process != nil { return }
        backupDidFinish = false
        stopRequested = false
        metrics.forEach { $0.stringValue = "—" }
        elapsedLabel.stringValue = "Temps écoulé : —"
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
        startButton.isHidden = isRunning
        startButton.isEnabled = !isRunning
        stopButton.isHidden = !isRunning
        stopButton.isEnabled = isRunning
        stopButton.title = "Arrêter la sauvegarde"
        stopButton.target = self
        stopButton.action = #selector(stopBackup)
    }

    func showCloseButton() {
        setBackupControls(isRunning: false)
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
            "Reading Drive file checksums...": "Vérification des fichiers Drive…",
            "Moving removed files to Drive trash...": "Traitement des fichiers supprimés…",
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
            } else if message == "Reading Drive file checksums..." {
                updateStages(active: 1, completed: 1)
                pathLabel.stringValue = ""
                setProgress(0, title: "Lecture des dossiers Drive")
            } else if message == "Backing up files..." {
                updateStages(active: 2, completed: 2)
            }
        } else if event == "check_progress" {
            let checked = obj["checked"] as? Int ?? 0
            let total = obj["total"] as? Int ?? 0
            let unchanged = obj["unchanged"] as? Int ?? 0
            pathLabel.stringValue = obj["current"] as? String ?? ""
            detailLabel.stringValue = "\(checked)/\(total) fichiers vérifiés · \(unchanged) inchangés"
            setProgress(total > 0 ? Double(checked) * 100 / Double(total) : 100, title: "Détection des modifications")
        } else if event == "drive_read_progress" {
            let checked = obj["checked"] as? Int ?? 0
            let total = obj["total"] as? Int ?? 0
            detailLabel.stringValue = "\(checked)/\(total) dossiers lus"
            setProgress(total > 0 ? Double(checked) * 100 / Double(total) : 100, title: "Lecture des dossiers Drive")
        } else if event == "deletion_progress" {
            let checked = obj["checked"] as? Int ?? 0
            let total = obj["total"] as? Int ?? 0
            let deleted = obj["deleted"] as? Int ?? 0
            pathLabel.stringValue = ""
            detailLabel.stringValue = "\(checked)/\(total) suppressions vérifiées · \(deleted) fichiers placés dans la corbeille Drive"
            setProgress(total > 0 ? Double(checked) * 100 / Double(total) : 100, title: "Traitement des suppressions")
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
            updateMetrics(obj)
            let pct = obj["percent"] as? Double ?? Double(obj["percent"] as? Int ?? 0)
            let done = obj["done"] as? Int ?? 0
            let total = obj["total"] as? Int ?? 0
            let errors = obj["errors"] as? Int ?? 0
            statusLabel.stringValue = "Sauvegarde des fichiers…"
            updateStages(active: 2, completed: 2)
            pathLabel.stringValue = ""
            setProgress(pct, title: "Progression des fichiers")
            detailLabel.stringValue = "\(done) fichiers traités sur \(total) · \(errors) erreur(s)"
        } else if event == "done" {
            let elapsed = obj["elapsed"] as? Int ?? 0
            let stats = obj["stats"] as? [String: Any] ?? [:]
            var summary = stats
            summary["elapsed"] = elapsed
            updateMetrics(summary)
            let total = stats["total"] as? Int ?? 0
            let copied = stats["created"] as? Int ?? 0
            let updated = stats["updated"] as? Int ?? 0
            let skipped = stats["skipped"] as? Int ?? 0
            let errors = stats["errors"] as? Int ?? 0
            let deleted = stats["deleted"] as? Int ?? 0
            setProgress(100, title: "Sauvegarde terminée")
            updateStages(active: errors > 0 ? 2 : nil, completed: errors > 0 ? 2 : 3, failed: errors > 0)
            statusLabel.stringValue = errors > 0 ? "Sauvegarde terminée avec erreurs" : "Sauvegarde terminée"
            pathLabel.stringValue = "\(copied) créés · \(updated) mis à jour · \(skipped) ignorés · \(deleted) à la corbeille · \(errors) erreurs"
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
