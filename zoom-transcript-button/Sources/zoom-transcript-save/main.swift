#!/usr/bin/env swift
import Foundation
import AppKit
import ApplicationServices
import OSLog

// MARK: - Configuration
let zoomBundleId = "us.zoom.xos"
let logger = Logger(subsystem: "com.user.zoomtranscript", category: "monitor")
var stdoutDebugEnabled = false

// MARK: - AX Helpers
func getChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard result == .success, let children = value as? [AXUIElement] else { return [] }
    return children
}

func getAttribute(_ element: AXUIElement, _ attr: String) -> String? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    guard result == .success, let str = value as? String else { return nil }
    return str
}

func clickElement(_ element: AXUIElement) -> Bool {
    AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}

private let maxAXSearchDepth = 50

/// Recursively find first element with matching description (searches ALL children, not just buttons)
func findElementByDescription(in element: AXUIElement, description: String, depth: Int = 0) -> AXUIElement? {
    guard depth < maxAXSearchDepth else { return nil }
    if getAttribute(element, kAXDescriptionAttribute as String) == description {
        return element
    }
    for child in getChildren(element) {
        if let found = findElementByDescription(in: child, description: description, depth: depth + 1) {
            return found
        }
    }
    return nil
}

/// Find element whose description starts with prefix and contains substring
func findElementByDescription(in element: AXUIElement, startsWith prefix: String, contains substring: String, depth: Int = 0) -> AXUIElement? {
    guard depth < maxAXSearchDepth else { return nil }
    if let desc = getAttribute(element, kAXDescriptionAttribute as String),
       desc.hasPrefix(prefix), desc.contains(substring) {
        return element
    }
    for child in getChildren(element) {
        if let found = findElementByDescription(in: child, startsWith: prefix, contains: substring, depth: depth + 1) {
            return found
        }
    }
    return nil
}

/// Find element whose description contains substring
func findElementByDescription(in element: AXUIElement, contains substring: String, depth: Int = 0) -> AXUIElement? {
    guard depth < maxAXSearchDepth else { return nil }
    if let desc = getAttribute(element, kAXDescriptionAttribute as String), desc.contains(substring) {
        return element
    }
    for child in getChildren(element) {
        if let found = findElementByDescription(in: child, contains: substring, depth: depth + 1) {
            return found
        }
    }
    return nil
}

// MARK: - Logging
func logInfo(_ msg: String) {
    logger.info("\(msg, privacy: .public)")
    if stdoutDebugEnabled {
        print(msg)
    }
}

func logWarning(_ msg: String) {
    logger.notice("WARNING: \(msg, privacy: .public)")
    if stdoutDebugEnabled {
        print("WARNING: \(msg)")
    }
}

func logError(_ msg: String) {
    logger.error("ERROR: \(msg, privacy: .public)")
    if stdoutDebugEnabled {
        print("ERROR: \(msg)")
    }
}

func logDebug(_ msg: String) {
    logger.debug("\(msg, privacy: .public)")
    if stdoutDebugEnabled {
        print(msg)
    }
}

// MARK: - Permission Check
func checkAccessibilityPermission() -> Bool {
    if AXIsProcessTrusted() {
        return true
    }
    logWarning("Waiting for Accessibility permission. Grant access in System Settings -> Privacy & Security -> Accessibility.")
    return false
}

// MARK: - Zoom Meeting Detection
func getZoomMeetingWindow() -> AXUIElement? {
    guard let zoomApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == zoomBundleId }) else {
        return nil
    }
    let pid = zoomApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)
    for window in getChildren(appElement) {
        if getAttribute(window, kAXRoleAttribute as String) == "AXWindow",
           getAttribute(window, kAXTitleAttribute as String) == "Zoom Meeting" {
            return window
        }
    }
    return nil
}

func isZoomMeetingActive() -> Bool {
    getZoomMeetingWindow() != nil
}

// MARK: - Transcript Panel
func isTranscriptPanelOpen() -> Bool {
    guard let window = getZoomMeetingWindow() else { return false }
    if findElementByDescription(in: window, description: "Save transcript") != nil {
        return true
    }
    if findElementByDescription(in: window, startsWith: "Transcript", contains: "close panel") != nil {
        return true
    }
    return false
}

func openTranscriptPanel() -> Bool {
    guard let window = getZoomMeetingWindow(),
          let zoomApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == zoomBundleId }) else {
        return false
    }
    let appElement = AXUIElementCreateApplication(zoomApp.processIdentifier)

    if let openBtn = findElementByDescription(in: window, startsWith: "Transcript", contains: "open panel") {
        if clickElement(openBtn) {
            Thread.sleep(forTimeInterval: 1)
            return true
        }
    }

    if let moreBtn = findElementByDescription(in: window, contains: "More meeting controls") {
        if clickElement(moreBtn) {
            Thread.sleep(forTimeInterval: 1)
            for win in getChildren(appElement) {
                if let title = getAttribute(win, kAXTitleAttribute as String), title.contains("More meeting controls") {
                    if let transcriptBtn = findElementByDescription(in: win, contains: "Transcript") {
                        if clickElement(transcriptBtn) {
                            Thread.sleep(forTimeInterval: 1)
                            return true
                        }
                    }
                }
            }
        }
    }

    if findElementByDescription(in: window, startsWith: "Transcript", contains: "close panel") != nil {
        return true
    }
    return false
}

// MARK: - Save Transcript
func clickSaveTranscript() -> Bool {
    guard let window = getZoomMeetingWindow() else { return false }
    guard let saveBtn = findElementByDescription(in: window, description: "Save transcript") else {
        return false
    }
    return clickElement(saveBtn)
}

// MARK: - Helpers
func getTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: Date())
}

// MARK: - Test Mode
func runSingleSave(debug: Bool) {
    stdoutDebugEnabled = debug
    logInfo("Running single save test...")
    if !checkAccessibilityPermission() {
        logError("No permission")
        return
    }
    if !isZoomMeetingActive() {
        logError("No active Zoom meeting")
        return
    }
    logInfo("Zoom meeting detected")
    if !isTranscriptPanelOpen() {
        logInfo("Opening transcript panel...")
        _ = openTranscriptPanel()
    }
    if clickSaveTranscript() {
        logInfo("Transcript saved at \(getTimestamp())")
        logInfo("SUCCESS: Transcript saved!")
    } else {
        logError("Could not save transcript")
    }
}

// MARK: - CLI Parsing
func parseArguments(_ args: [String]) -> (testMode: Bool, intervalSeconds: Int, debug: Bool) {
    var testMode = false
    var intervalSeconds = 10
    var debug = false
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--test", "-t":
            testMode = true
        case "--debug", "-d":
            debug = true
        case "--no-debug":
            debug = false
        case "--interval", "-i":
            if i + 1 < args.count, let n = Int(args[i + 1]), n > 0 {
                intervalSeconds = n
                i += 1
            }
        case "--help", "-h":
            print("Usage: zoom-transcript-save [OPTIONS]")
            print("  --interval SECONDS, -i    Save interval in seconds (default: 10)")
            print("  --debug, -d               Enable debug logging")
            print("  --no-debug                Disable debug logging")
            print("  --test, -t                Run single save test and exit")
            print("  --help, -h                Show this help")
            exit(0)
        default:
            break
        }
        i += 1
    }
    return (testMode, intervalSeconds, debug)
}

private func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let monitor = Unmanaged<ZoomMeetingMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleAXNotification(element: element, notification: notification as String)
}

final class ZoomMeetingMonitor {
    let intervalSeconds: Double
    let debugEnabled: Bool

    private var observedPid: pid_t = 0
    private var axObserver: AXObserver?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var saveTimer: Timer?
    private var meetingActive = false
    private var activeMeetingWindow: AXUIElement?

    init(intervalSeconds: Int, debug: Bool) {
        self.intervalSeconds = Double(intervalSeconds)
        self.debugEnabled = debug
    }

    deinit {
        stopMeeting(logEnd: false)
        detachAXObserver()
        removeWorkspaceObservers()
    }

    func start() {
        installWorkspaceObservers()
        guard let zoomApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == zoomBundleId }) else {
            logInfo("Waiting for Zoom to launch...")
            return
        }

        logInfo("Zoom already running, attaching AX observer...")
        attachAXObserver(pid: zoomApp.processIdentifier)
    }

    private func installWorkspaceObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let launchToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleWorkspaceAppLaunch(note)
        }
        let terminateToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleWorkspaceAppTermination(note)
        }

        workspaceTokens = [launchToken, terminateToken]
    }

    private func removeWorkspaceObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens {
            workspaceCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
    }

    private func handleWorkspaceAppLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == zoomBundleId else {
            return
        }
        logInfo("Zoom launched, attaching AX observer...")
        attachAXObserver(pid: app.processIdentifier)
    }

    private func handleWorkspaceAppTermination(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == zoomBundleId else {
            return
        }
        logInfo("Zoom terminated, detaching AX observer...")
        stopMeeting(logEnd: false)
        detachAXObserver()
        logInfo("Waiting for Zoom to launch...")
    }

    private func attachAXObserver(pid: pid_t) {
        if observedPid == pid, axObserver != nil {
            return
        }

        detachAXObserver()

        var observerRef: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &observerRef)
        guard createResult == .success, let observer = observerRef else {
            logError("Could not create AX observer for Zoom process (AXError \(createResult.rawValue))")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let windowCreateResult = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        guard windowCreateResult == .success || windowCreateResult == .notificationAlreadyRegistered else {
            logError("Could not register window-created observer (AXError \(windowCreateResult.rawValue))")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedPid = pid

        if debugEnabled {
            logDebug("AX observer attached for pid \(pid)")
        }

        if let existingMeetingWindow = getZoomMeetingWindow() {
            logInfo("Meeting already active at startup")
            startMeeting(window: existingMeetingWindow)
        } else {
            logInfo("Waiting for Zoom meeting window...")
        }
    }

    private func detachAXObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        axObserver = nil
        observedPid = 0
        activeMeetingWindow = nil
    }

    private func registerWindowDestroyedNotification(for window: AXUIElement) {
        guard let observer = axObserver else { return }
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        if result != .success && result != .notificationAlreadyRegistered {
            logWarning("Could not register meeting window destroy observer (AXError \(result.rawValue))")
        }
    }

    private func isZoomMeetingWindow(_ element: AXUIElement) -> Bool {
        getAttribute(element, kAXRoleAttribute as String) == "AXWindow" &&
            getAttribute(element, kAXTitleAttribute as String) == "Zoom Meeting"
    }

    func handleAXNotification(element: AXUIElement, notification: String) {
        switch notification {
        case String(kAXWindowCreatedNotification):
            guard isZoomMeetingWindow(element) else { return }
            startMeeting(window: element)
        case String(kAXUIElementDestroyedNotification):
            if let activeWindow = activeMeetingWindow, CFEqual(activeWindow, element) {
                stopMeeting(logEnd: true)
            } else if meetingActive && !isZoomMeetingActive() {
                stopMeeting(logEnd: true)
            }
        default:
            break
        }
    }

    private func startMeeting(window: AXUIElement) {
        registerWindowDestroyedNotification(for: window)
        if meetingActive {
            activeMeetingWindow = window
            return
        }

        meetingActive = true
        activeMeetingWindow = window
        logInfo("Meeting detected at \(getTimestamp())")

        if !isTranscriptPanelOpen() {
            logInfo("Opening transcript panel...")
            if openTranscriptPanel() {
                logInfo("Transcript panel opened")
            } else {
                logWarning("Could not open transcript panel")
            }
        } else {
            logInfo("Transcript panel already open")
        }

        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.saveTimerFired()
        }

        if debugEnabled {
            logDebug("Save timer started with interval \(Int(intervalSeconds))s")
        }
    }

    private func stopMeeting(logEnd: Bool) {
        guard meetingActive || saveTimer != nil else { return }
        saveTimer?.invalidate()
        saveTimer = nil
        meetingActive = false
        activeMeetingWindow = nil
        if logEnd {
            logInfo("Meeting ended at \(getTimestamp())")
            logInfo("Waiting for next meeting...")
        }
    }

    @objc private func saveTimerFired() {
        if !isZoomMeetingActive() {
            stopMeeting(logEnd: true)
            return
        }

        if !isTranscriptPanelOpen() {
            logWarning("Transcript panel closed, re-opening...")
            if openTranscriptPanel() {
                logInfo("Transcript panel opened")
            } else {
                logWarning("Could not open transcript panel, will retry")
                return
            }
        }

        if clickSaveTranscript() {
            logInfo("Transcript saved at \(getTimestamp())")
        } else {
            logWarning("Could not save transcript, will retry")
        }
    }
}

// MARK: - Main
func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    let (testMode, intervalSeconds, debug) = parseArguments(args)

    if testMode {
        runSingleSave(debug: debug)
        return
    }

    stdoutDebugEnabled = debug
    logInfo("Zoom Transcript Auto-Save - Starting")
    logInfo("  Interval: \(intervalSeconds) sec, Debug: \(debug)")

    while !checkAccessibilityPermission() {
        Thread.sleep(forTimeInterval: 10)
    }
    logInfo("Permission OK, monitoring for meetings...")

    let monitor = ZoomMeetingMonitor(intervalSeconds: intervalSeconds, debug: debug)
    monitor.start()
    RunLoop.main.run()
}

main()
