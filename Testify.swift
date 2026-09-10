// ============================================================
// Testify
// ============================================================
//
// A Swift command-line tool that captures evidence of macOS
// security controls for BYOD policy compliance and compiles
// screenshots into a single dated PDF.
//
// Build (compiles, bundles, and signs Testify.app):
//   ./create-signing-cert.sh   # one time per machine
//   ./package.sh
//
// Run (must launch via LaunchServices so the APP — not Terminal —
// is the TCC responsible process that owns the permissions):
//   open dist/Testify.app
//
// Permissions (grant to Testify.app, not Terminal):
//   System Settings > Privacy & Security > Accessibility
//   System Settings > Privacy & Security > Screen Recording
//   System Settings > Privacy & Security > Automation
//
// Output: ~/Desktop/2026-03-09 BYOD Device Controls Attestation.pdf
// ============================================================

import Cocoa
import PDFKit
import ApplicationServices

// MARK: - Shell

@discardableResult
func shell(_ cmd: String) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-c", cmd]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// MARK: - App Management

let systemSettingsID = "com.apple.systempreferences"

func quitApp(_ bundleID: String) {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .forEach { $0.terminate() }
    while !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
        Thread.sleep(forTimeInterval: 0.5)
    }
    Thread.sleep(forTimeInterval: 0.5)
}

func waitForWindow(_ appName: String, timeout: TimeInterval = 15) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if windowID(for: appName) != nil { return }
        Thread.sleep(forTimeInterval: 0.5)
    }
}

// MARK: - Window Capture

func windowID(for appName: String) -> CGWindowID? {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return nil }

    for w in list {
        if let name = w[kCGWindowOwnerName as String] as? String,
           let wid = w[kCGWindowNumber as String] as? CGWindowID,
           let layer = w[kCGWindowLayer as String] as? Int,
           layer == 0, name == appName {
            return wid
        }
    }
    return nil
}

func captureWindow(_ appName: String, to path: String) -> Bool {
    guard let wid = windowID(for: appName) else { return false }
    shell("screencapture -x -o -l\(wid) \(shellQuote(path))")
    return FileManager.default.fileExists(atPath: path)
}

// MARK: - Keyboard Events

let kVK_A: CGKeyCode = 0
let kVK_F: CGKeyCode = 3
let kVK_I: CGKeyCode = 34
let kVK_Tab: CGKeyCode = 48
let kVK_PageDown: CGKeyCode = 121

func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
    if let dn = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
       let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) {
        dn.flags = flags
        dn.post(tap: .cghidEventTap)
        up.flags = flags
        up.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.05)
}

func typeString(_ s: String) {
    for ch in s.utf16 {
        var c = ch
        if let dn = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            dn.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            dn.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.03)
    }
}

// MARK: - Accessibility Helpers

func axApp(_ bundleID: String) -> AXUIElement? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func axStr(_ el: AXUIElement, _ attr: String) -> String? {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(el, attr as CFString, &ref)
    return ref as? String
}

func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref)
    return ref as? [AXUIElement] ?? []
}

/// Recursively search the AX tree for an element matching a text value
func axFind(_ root: AXUIElement, value: String) -> AXUIElement? {
    if axStr(root, kAXValueAttribute) == value { return root }
    if axStr(root, kAXTitleAttribute) == value { return root }
    if axStr(root, kAXDescriptionAttribute) == value { return root }
    for child in axChildren(root) {
        if let found = axFind(child, value: value) { return found }
    }
    return nil
}

/// Recursively search the AX tree for an element matching a role and subrole/description
func axFindByRole(_ root: AXUIElement, role: String, subrole: String? = nil) -> AXUIElement? {
    if axStr(root, kAXRoleAttribute) == role {
        if let sub = subrole {
            if axStr(root, kAXSubroleAttribute) == sub { return root }
        } else {
            return root
        }
    }
    for child in axChildren(root) {
        if let found = axFindByRole(child, role: role, subrole: subrole) { return found }
    }
    return nil
}

/// Set the value of an AX text field
func axSetValue(_ element: AXUIElement, value: String) -> Bool {
    AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
}

/// Scroll an element into view within its scroll container
func axScrollToVisible(_ element: AXUIElement) -> Bool {
    AXUIElementPerformAction(element, "AXScrollToVisible" as CFString) == .success
}

/// Recursively find all scroll areas in the AX tree
func axFindScrollAreas(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    var results: [AXUIElement] = []
    if depth > 10 { return results }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &role)
    if let r = role as? String, r == kAXScrollAreaRole {
        results.append(root)
    }
    for child in axChildren(root) {
        results.append(contentsOf: axFindScrollAreas(child, depth: depth + 1))
    }
    return results
}

/// Scroll a scroll area to the bottom by setting its vertical scroll bar value to 1.0
func axScrollToBottom(_ scrollArea: AXUIElement) -> Bool {
    for child in axChildren(scrollArea) {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
        guard let r = role as? String, r == kAXScrollBarRole else { continue }
        var orient: CFTypeRef?
        AXUIElementCopyAttributeValue(child, kAXOrientationAttribute as CFString, &orient)
        if let o = orient as? String, o == "AXVerticalOrientation" {
            AXUIElementSetAttributeValue(child, kAXValueAttribute as CFString, 1.0 as CFTypeRef)
            return true
        }
    }
    return false
}

/// Find a UI element by its text and click it (tries element, parent, grandparent)
func axClick(_ bundleID: String, value: String) -> Bool {
    guard let appEl = axApp(bundleID),
          let el = axFind(appEl, value: value) else { return false }

    if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success {
        return true
    }

    // Try parent (the row/group containing the text)
    var ref: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &ref) == .success {
        let parent = ref as! AXUIElement
        if AXUIElementPerformAction(parent, kAXPressAction as CFString) == .success {
            return true
        }
        // Try grandparent
        if AXUIElementCopyAttributeValue(parent, kAXParentAttribute as CFString, &ref) == .success {
            let gp = ref as! AXUIElement
            if AXUIElementPerformAction(gp, kAXPressAction as CFString) == .success {
                return true
            }
        }
    }
    return false
}

/// Synthesize a real mouse click at the centre of the first AX element matching
/// `value`. SwiftUI rows (e.g. profiles in Device Management) often ignore
/// AXPress but open on an actual click. `clickCount: 2` performs a double-click.
func axMouseClick(_ bundleID: String, value: String, clickCount: Int = 1) -> Bool {
    guard let appEl = axApp(bundleID), let el = axFind(appEl, value: value) else { return false }
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posV = posRef, let sizeV = sizeRef else { return false }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &point)
    AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
    // AX position is screen coordinates (top-left origin), matching CGEvent.
    let center = CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
    let src = CGEventSource(stateID: .hidSystemState)
    for i in 1...max(1, clickCount) {
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                           mouseCursorPosition: center, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                         mouseCursorPosition: center, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
        up?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
    }
    return true
}

// MARK: - AppleScript Helper

/// Execute AppleScript on the main thread. The capture flow runs on a background
/// thread (so the progress window stays live), but NSAppleScript wants the main
/// thread, so we always marshal there.
@discardableResult
func runAppleScript(_ source: String) -> NSDictionary? {
    var error: NSDictionary?
    let work: () -> Void = { _ = NSAppleScript(source: source)?.executeAndReturnError(&error) }
    if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    return error
}

// MARK: - Terminal Helper

func runInTerminal(_ command: String) {
    let escaped = command
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    runAppleScript("""
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
    """)
}

func closeTerminal() {
    runAppleScript("""
        tell application "Terminal"
            close every window saving no
            quit
        end tell
    """)
}

// MARK: - Finder Helper

/// Reveal an app bundle in Finder and open its Get Info panel. The panel becomes
/// the frontmost Finder window, so captureWindow("Finder", …) grabs it. Closing
/// every window first is what makes this safe to call in a loop - each call
/// clears the previous Get Info panel before opening the next.
func openFinderGetInfo(_ path: String) {
    runAppleScript("""
        tell application "Finder"
            activate
            close every window
            reveal (POSIX file "\(path)" as alias)
        end tell
    """)
    Thread.sleep(forTimeInterval: 1.5)
    postKey(kVK_I, flags: .maskCommand)
    Thread.sleep(forTimeInterval: 1.5)
}

func closeFinderWindows() {
    runAppleScript("tell application \"Finder\" to close every window")
}

// MARK: - System Settings Helper

func openSettings(_ url: String) {
    quitApp(systemSettingsID)
    NSWorkspace.shared.open(URL(string: url)!)
    waitForWindow("System Settings")
    Thread.sleep(forTimeInterval: 2)
}

// MARK: - Progress UI

/// A small always-visible window with a status line, progress bar, and a
/// scrolling log — so progress is visible when launched as an .app (no stdout).
final class ProgressUI: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let statusLabel: NSTextField
    private let progress: NSProgressIndicator
    private let textView: NSTextView

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Testify"
        window.isReleasedWhenClosed = false

        statusLabel = NSTextField(labelWithString: "Starting…")
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progress = NSProgressIndicator()
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 8
        progress.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView = NSTextView()
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        scroll.documentView = textView

        super.init()
        window.delegate = self

        let content = window.contentView!
        [statusLabel, progress, scroll].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            progress.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            progress.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            progress.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        // Park it in the top-left, away from the centered windows we capture.
        if let screen = NSScreen.main {
            window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 20,
                                                y: screen.visibleFrame.maxY - 20))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func append(_ line: String) {
        textView.textStorage?.append(NSAttributedString(
            string: line + "\n",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         .foregroundColor: NSColor.labelColor]))
        textView.scrollToEndOfDocument(nil)
    }

    func setStep(_ n: Int, total: Int, _ title: String) {
        progress.maxValue = Double(total)
        progress.doubleValue = Double(n)
        statusLabel.stringValue = "Step \(n)/\(total): \(title)"
    }

    func finish(_ message: String) {
        progress.doubleValue = progress.maxValue
        statusLabel.stringValue = message
    }

    // Closing the window ends the run (the app has no Dock icon / menu).
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

/// Global UI handle and helpers. `log`/`step` are safe to call from the
/// background capture thread; UI mutations are marshalled to the main thread.
var ui: ProgressUI?

func log(_ message: String) {
    print(message)
    DispatchQueue.main.async { ui?.append(message) }
}

func step(_ n: Int, _ title: String) {
    log("[\(n)/8] \(title)")
    DispatchQueue.main.async { ui?.setStep(n, total: 8, title) }
}

// MARK: - Main

func main() {
    log("Testify — BYOD Device Controls Attestation")
    log("==========================================\n")

    // Check accessibility permission
    if !AXIsProcessTrusted() {
        log("Accessibility permission required.")
        log("A system dialog will appear to grant access.")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        log("After granting access, reopen this app.")
        DispatchQueue.main.async {
            ui?.finish("Accessibility access needed — grant it, then reopen this app.")
        }
        return
    }

    // Check Screen Recording permission. Captures are taken by a `screencapture`
    // child process, which never raises a prompt of its own — it just writes
    // nothing — so the app has to ask on its own behalf.
    //
    // Two macOS facts shape what follows. This permission is never granted
    // inline the way Camera or Microphone are: the system prompt only offers to
    // open System Settings. And it is shown at most once per app identity, so
    // once TCC has recorded any decision the request below returns false
    // silently. Make it anyway — it registers Testify in the Screen Recording
    // list, so there is a toggle to flip instead of a manual drag-in.
    if !CGPreflightScreenCaptureAccess() {
        log("Screen Recording permission required.")
        _ = CGRequestScreenCaptureAccess()
        log("macOS won't grant this one from a dialog. Switch on Testify in")
        log("System Settings > Privacy & Security > Screen Recording (opening now),")
        log("then reopen this app.")
        log("")
        log("If Testify isn't in that list, macOS already recorded a decision for it.")
        log("Clear the record, then relaunch:")
        log("  tccutil reset ScreenCapture biz.stack.testify")
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        DispatchQueue.main.async {
            ui?.finish("Screen Recording access needed — see the log, then reopen this app.")
        }
        return
    }

    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    let dateStr = df.string(from: Date())

    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.path
    let tmpDir = shell("mktemp -d /tmp/testify_XXXXXX")
    var pageNum = 0

    func capture(_ appName: String, _ label: String) {
        pageNum += 1
        let path = "\(tmpDir)/page_\(String(format: "%03d", pageNum)).png"
        if captureWindow(appName, to: path) {
            log("  \u{2713} \(label)")
        } else {
            // Distinguish "the window wasn't there" from "screencapture refused",
            // since the second is almost always a missing Screen Recording grant.
            let reason = windowID(for: appName) == nil
                ? "no on-screen \(appName) window"
                : "screencapture wrote nothing - is Screen Recording granted to Testify?"
            log("  \u{2717} \(label) - \(reason)")
            pageNum -= 1
        }
    }

    // --- PAGE 1: Software Update ---
    step(1, "Software Update")
    openSettings("x-apple.systempreferences:com.apple.Software-Update-Settings.extension")
    Thread.sleep(forTimeInterval: 8)
    capture("System Settings", "Software Update")

    // --- PAGE 2: Lock Screen ---
    step(2, "Lock Screen")
    openSettings("x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension")
    capture("System Settings", "Lock Screen")

    // --- PAGE 3: Privacy & Security (scrolled to show Security + FileVault) ---
    step(3, "Privacy & Security")
    openSettings("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
    // Scroll content pane to bottom to show "Allow applications from" and FileVault status
    if let ssApp = axApp(systemSettingsID) {
        let scrollAreas = axFindScrollAreas(ssApp)
        // The last scroll area is the content pane (right side)
        if let contentScroll = scrollAreas.last {
            _ = axScrollToBottom(contentScroll)
        }
    }
    Thread.sleep(forTimeInterval: 2)
    capture("System Settings", "Security & FileVault")

    // --- PAGE 4: System Integrity Protection ---
    step(4, "System Integrity Protection")
    quitApp(systemSettingsID)
    runInTerminal("clear && echo '$ csrutil status' && csrutil status")
    Thread.sleep(forTimeInterval: 2)
    capture("Terminal", "csrutil status")

    // --- PAGE 5: Gatekeeper ---
    step(5, "Gatekeeper")
    runInTerminal("clear && echo '$ spctl --status' && spctl --status")
    Thread.sleep(forTimeInterval: 2)
    capture("Terminal", "spctl --status")

    // --- PAGE 6: XProtect (Activity Monitor) ---
    step(6, "XProtect processes")
    runAppleScript("tell application \"Terminal\" to close every window saving no")
    Thread.sleep(forTimeInterval: 0.5)
    shell("open -a 'Activity Monitor'")
    waitForWindow("Activity Monitor")
    Thread.sleep(forTimeInterval: 3)
    // Use AX API to find the search/filter field and set its value directly
    let amBundleID = "com.apple.ActivityMonitor"
    if let amApp = axApp(amBundleID),
       let searchField = axFindByRole(amApp, role: kAXTextFieldRole, subrole: kAXSearchFieldSubrole) {
        AXUIElementSetAttributeValue(searchField, kAXFocusedAttribute as CFString, true as CFTypeRef)
        Thread.sleep(forTimeInterval: 0.3)
        _ = axSetValue(searchField, value: "xpro")
    } else {
        // Fallback: try finding any text field
        if let amApp = axApp(amBundleID),
           let textField = axFindByRole(amApp, role: kAXTextFieldRole) {
            AXUIElementSetAttributeValue(textField, kAXFocusedAttribute as CFString, true as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.3)
            _ = axSetValue(textField, value: "xpro")
        } else {
            log("  \u{26A0} Could not find Activity Monitor search field")
        }
    }
    Thread.sleep(forTimeInterval: 5)
    capture("Activity Monitor", "XProtect processes")
    quitApp("com.apple.ActivityMonitor")

    // --- PAGE 7: Password Policy (managed configuration profile) ---
    // Screenshot the actual enforced policy from System Settings > General >
    // Device Management. Clicking the profile opens its detail sheet, showing
    // the description, install date, and payload values - authoritative,
    // OS-rendered evidence rather than hand-parsed terminal output.
    step(7, "Password Policy (configuration profile)")
    openSettings("x-apple.systempreferences:com.apple.Profiles-Settings.extension")
    Thread.sleep(forTimeInterval: 3)
    // Open the profile's detail sheet so its payload values are visible. The row
    // ignores AXPress, and a single click only selects it, so double-click it
    // (both clicks land before any sheet appears, so nothing gets dismissed).
    if !axMouseClick(systemSettingsID, value: "BYOD Password Policy", clickCount: 2) {
        log("  \u{26A0} BYOD Password Policy profile not found - is it installed?")
    }
    Thread.sleep(forTimeInterval: 2.5)
    capture("System Settings", "Password policy profile")
    quitApp(systemSettingsID)

    // --- PAGE 8: Password manager (proof of installation only) ---
    // We deliberately DO NOT launch the password manager: its window could
    // expose vault contents / other clients' logins depending on its current
    // state. A Finder "Get Info" window proves the app is installed and shows
    // its version, straight from the bundle metadata, without ever opening it.
    //
    // Every installed manager is evidenced, so a machine with two produces two
    // pages. This is still one step - page count varies, step count does not.
    step(8, "Password manager (proof of installation)")

    // Display name -> candidate bundle names. 1Password 7 shipped under a
    // versioned bundle name; 1Password 8 and both Bitwarden builds (direct
    // download and Mac App Store) use the unversioned name.
    let passwordManagers: [(name: String, bundles: [String])] = [
        ("1Password", ["1Password.app", "1Password 7.app"]),
        ("Bitwarden", ["Bitwarden.app"]),
    ]
    let appDirs = ["/Applications", "\(NSHomeDirectory())/Applications"]

    var foundManager = false
    for pm in passwordManagers {
        let candidates = appDirs.flatMap { dir in pm.bundles.map { "\(dir)/\($0)" } }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { continue }
        foundManager = true
        openFinderGetInfo(path)
        capture("Finder", "\(pm.name) installed (Get Info)")
    }
    if foundManager {
        closeFinderWindows()
    } else {
        let names = passwordManagers.map(\.name).joined(separator: " or ")
        log("  i No password manager found (\(names)) - skipping")
    }

    // Cleanup running apps
    closeTerminal()
    Thread.sleep(forTimeInterval: 0.5)

    // --- Merge screenshots into PDF ---
    log("\nMerging to PDF...")
    let pdfName = "\(dateStr) BYOD Device Controls Attestation.pdf"
    let pdfPath = "\(desktop)/\(pdfName)"

    let pdfDoc = PDFDocument()
    let files = (try? FileManager.default.contentsOfDirectory(atPath: tmpDir))?
        .filter { $0.hasPrefix("page_") && $0.hasSuffix(".png") }
        .sorted() ?? []

    for (i, file) in files.enumerated() {
        if let img = NSImage(contentsOfFile: "\(tmpDir)/\(file)"),
           let page = PDFPage(image: img) {
            pdfDoc.insert(page, at: i)
        }
    }

    // A zero-page PDFDocument still writes a structurally valid file - one blank
    // page, evidencing nothing. That looks like a successful run, so fail loudly.
    guard pdfDoc.pageCount > 0 else {
        log("\n\u{2717} No screenshots captured - no PDF written.")
        log("  The usual cause is a missing Screen Recording grant. Add Testify.app in")
        log("  System Settings > Privacy & Security > Screen Recording, then re-run.")
        try? FileManager.default.removeItem(atPath: tmpDir)
        DispatchQueue.main.async {
            ui?.finish("No screenshots captured - check Screen Recording permission.")
        }
        return
    }

    if pdfDoc.write(toFile: pdfPath) {
        log("\u{2713} ~/Desktop/\(pdfName)")
        NSWorkspace.shared.open(URL(fileURLWithPath: pdfPath))
    } else {
        log("\u{2717} Failed to write PDF")
    }

    // Cleanup temp files
    try? FileManager.default.removeItem(atPath: tmpDir)
    log("Done!")
    DispatchQueue.main.async {
        ui?.finish("Done — PDF saved to your Desktop. You can close this window.")
    }
}

// MARK: - Entry point

/// Build a minimal menu bar (programmatic apps get none by default), with the
/// standard application menu so the app shows in the menu bar and is quittable
/// (Cmd-Q / Quit / Hide), plus an Edit menu so the log text can be copied.
func buildMainMenu(appName: String) -> NSMenu {
    let mainMenu = NSMenu()

    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(withTitle: "Hide \(appName)",
                    action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: "Hide Others",
                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        .keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit \(appName)",
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    return mainMenu
}

// Show the progress window, then run the capture work on a background thread so
// the window stays responsive (the capture flow is full of blocking sleeps).
let app = NSApplication.shared
app.setActivationPolicy(.regular)     // normal app: Dock icon + menu bar, quittable
app.mainMenu = buildMainMenu(appName: "Testify")
ui = ProgressUI()
app.activate(ignoringOtherApps: true)

DispatchQueue.global(qos: .userInitiated).async {
    main()
}

app.run()
