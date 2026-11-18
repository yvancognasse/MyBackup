// Appended to MyBackupApp.swift by run_ui_checks.py; never starts a backup.
let application = NSApplication.shared
let subject = AppDelegate()
subject.buildWindow()
func settleLayout() {
    subject.window.contentView!.layoutSubtreeIfNeeded()
    subject.dashboardScroll.layout()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
}
settleLayout()
let initialFrame = subject.window.frame
assert(subject.window.contentView!.bounds.width == 660)
assert(subject.window.contentView!.bounds.height == 470)
let veryLongPath = String(repeating: "Dossier très long/", count: 100) + "fichier.pdf"
for index in 1...60 {
    let events: [[String: Any]] = [
        ["event": "folder_progress", "checked": index, "total": 100000, "created": index, "elapsed": index, "current": veryLongPath],
        ["event": "upload_progress", "percent": index, "done": index * 10000, "total": 1000000, "created": index, "updated": 200000, "skipped": 1000000, "errors": 0, "elapsed": 999999],
        ["event": "error", "message": veryLongPath]
    ]
    for event in events {
        let data = try JSONSerialization.data(withJSONObject: event)
        subject.handleLine(String(data: data, encoding: .utf8)!)
        settleLayout()
        assert(subject.window.frame == initialFrame, "Progress messages resized the window")
    }
}
let details = NSButton()
for state: NSControl.StateValue in [.on, .off, .on] {
    details.state = state
    subject.toggleDetails(details)
    settleLayout()
    assert(subject.window.frame == initialFrame, "Disclosure resized the window")
}
for width in [580.0, 900.0, 660.0] {
    subject.window.setContentSize(NSSize(width: width, height: 470))
    subject.windowDidResize(Notification(name: NSWindow.didResizeNotification))
    settleLayout()
    assert(subject.workspace.orientation == (width < 620 ? .vertical : .horizontal))
}
assert(subject.startButton is BackupStartButton)
assert(subject.startButton.intrinsicContentSize == NSSize(width: 164, height: 30))
let button = subject.startButton!
button.frame = NSRect(origin: .zero, size: button.intrinsicContentSize)
let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 164, pixelsHigh: 30,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pixels)
button.draw(button.bounds)
NSGraphicsContext.restoreGraphicsState()
var whitePixels = 0
var greenPixels = 0
for y in 0..<30 {
    for x in 0..<164 {
        guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if color.alphaComponent > 0.9 && color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95 { whitePixels += 1 }
        if color.alphaComponent > 0.9 && color.greenComponent > color.redComponent + 0.2 { greenPixels += 1 }
    }
}
assert(whitePixels > 20 && greenPixels > 500, "Primary button must render white text on green")
print("UI checks passed: 180 progress/error updates and disclosure keep window size; compact/wide layouts and primary button verified")
