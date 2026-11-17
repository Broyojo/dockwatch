// dockwatch: detects the "invisible dock" bug — screen space reserved for the Dock
// while Dock autohide is ON — logs it with context, and (optionally) auto-fixes it.
//
// Build:  swiftc -O dockwatch.swift -o dockwatch
// Run:    ./dockwatch            (log only)
//         ./dockwatch --fix      (also toggle autohide off/on to clear it)
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser
let logDir = home.appendingPathComponent("Library/Logs/dockwatch")
try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
let mainLog = logDir.appendingPathComponent("dockwatch.log")
let autoFix = CommandLine.arguments.contains("--fix")
let stuckThreshold: TimeInterval = 4   // MC legitimately reserves space for ~2s; ignore shorter

let tsFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f }()
func log(_ s: String) {
    let line = "\(tsFmt.string(from: Date())) \(s)\n"
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
    if let h = try? FileHandle(forWritingTo: mainLog) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: mainLog, atomically: true, encoding: .utf8) }
}

func autohideOn() -> Bool {
    CFPreferencesAppSynchronize("com.apple.dock" as CFString)
    return (CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool) ?? false
}

struct Insets: Equatable { var bottom, left, right: CGFloat }
func describe() -> (String, [String: Insets]) {
    var out: [String: Insets] = [:]; var parts: [String] = []
    for s in NSScreen.screens {
        let f = s.frame, v = s.visibleFrame
        let i = Insets(bottom: v.minY - f.minY, left: v.minX - f.minX, right: f.maxX - v.maxX)
        out[s.localizedName] = i
        parts.append("[\(s.localizedName) \(Int(f.width))x\(Int(f.height)) b=\(Int(i.bottom)) l=\(Int(i.left)) r=\(Int(i.right))]")
    }
    return (parts.joined(separator: " "), out)
}

func run(_ path: String, _ args: [String]) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
    try? p.run(); let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
}

func captureEvidence(since: Date) {
    let start = tsFmt.string(from: since.addingTimeInterval(-90)).prefix(19)
    let pred = """
    (process == "Dock" AND (eventMessage CONTAINS "autoHide" OR eventMessage CONTAINS "Changing from mode" OR \
    eventMessage CONTAINS "space-change" OR eventMessage CONTAINS "SetBooleanPreference" OR eventMessage CONTAINS[c] "display" \
    OR eventMessage CONTAINS[c] "fullscreen" OR eventMessage CONTAINS "Hiding all")) OR \
    (process == "WindowManager" AND (eventMessage CONTAINS "expose mode" OR eventMessage CONTAINS "minimumDockReveal" OR eventMessage CONTAINS[c] "display")) OR \
    (process == "WindowServer" AND (eventMessage CONTAINS[c] "reconfig" OR eventMessage CONTAINS[c] "dock"))
    """
    let out = run("/usr/bin/log", ["show", "--style", "compact", "--start", String(start), "--predicate", pred])
    let f = logDir.appendingPathComponent("stuck-\(tsFmt.string(from: Date()).replacingOccurrences(of: " ", with: "_")).log")
    try? out.write(to: f, atomically: true, encoding: .utf8)
    log("  evidence saved: \(f.path)")
}

// Same private call System Settings makes; needs no Automation permission.
typealias CoreDockSetAutoHide = @convention(c) (Bool) -> Void
let coreDockSet: CoreDockSetAutoHide? = {
    guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
          let s = dlsym(h, "CoreDockSetAutoHideEnabled") else { return nil }
    return unsafeBitCast(s, to: CoreDockSetAutoHide.self)
}()

func toggleAutohide() {
    if let set = coreDockSet {
        set(false); usleep(600_000); set(true)
        log("  auto-fix: toggled autohide off/on via CoreDock")
        return
    }
    let r = run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell dock preferences to set autohide to false",
                                       "-e", "delay 0.6",
                                       "-e", "tell application \"System Events\" to tell dock preferences to set autohide to true"])
    log("  auto-fix: toggled autohide off/on \(r.isEmpty ? "" : "(osascript: \(r.trimmingCharacters(in: .whitespacesAndNewlines)))")")
}

var last = ""
var badSince: Date? = nil
var reported = false

func tick(_ reason: String) {
    let (desc, insets) = describe()
    let ah = autohideOn()
    if desc != last { log("\(reason) autohide=\(ah ? 1 : 0) \(desc)"); last = desc }
    // With autohide on, the Dock should reserve ~0 (it may leave a few px). >20pt = stuck reservation.
    let bad = ah && insets.values.contains { $0.bottom > 20 || $0.left > 20 || $0.right > 20 }
    if bad {
        if badSince == nil { badSince = Date(); reported = false }
        if !reported, Date().timeIntervalSince(badSince!) >= stuckThreshold {
            reported = true
            log("STUCK: space reserved for Dock while autohide=1 (since \(tsFmt.string(from: badSince!)))")
            if autoFix { toggleAutohide() }
            captureEvidence(since: badSince!)
        }
    } else {
        if let b = badSince, reported { log("CLEARED after \(Int(Date().timeIntervalSince(b)))s") }
        badSince = nil; reported = false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
log("dockwatch started (autoFix=\(autoFix))")
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in tick("screens-changed") }
let ws = NSWorkspace.shared.notificationCenter
ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in tick("wake") }
ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in tick("space-changed") }
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in tick("poll") }
tick("start")
app.run()
