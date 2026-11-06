import Foundation
import IOKit.ps
import OSLog
import Darwin

enum Mode: String, CaseIterable {
    case normal, server, travel
    var title: String {
        switch self {
        case .normal: return "Обычный"
        case .server: return "Сервер"
        case .travel: return "В пути"
        }
    }
}

struct SessionLease: Codable {
    let heartbeat: TimeInterval
    let deadline: TimeInterval
    var isValid: Bool { heartbeat.isFinite && deadline.isFinite && deadline >= 0 }
    static func read(from url: URL) -> SessionLease? {
        guard let data = try? Data(contentsOf: url), data.count <= 4096,
              let lease = try? JSONDecoder().decode(SessionLease.self, from: data), lease.isValid else { return nil }
        return lease
    }
}

func deadlineAfter(minutes: Int, now: TimeInterval) -> TimeInterval {
    minutes == 0 ? 0 : now + Double(minutes) * 60
}

enum SessionEnd: String {
    case heartbeatLost, timerExpired, batteryUnavailable, batteryLow, powerDisconnected
    case sleepStateUnavailable, sleepProhibitionRemoved, activationFailed
}

func sessionEnd(now: TimeInterval, heartbeat: TimeInterval?, deadline: TimeInterval,
                battery: Battery?, threshold: Int, requiresAC: Bool = false) -> SessionEnd? {
    guard let heartbeat, heartbeat.isFinite, heartbeat <= now + 5, now - heartbeat <= 15 else { return .heartbeatLost }
    guard deadline.isFinite, deadline >= 0 else { return .timerExpired }
    if deadline > 0 && now >= deadline { return .timerExpired }
    guard let battery else { return .batteryUnavailable }
    if requiresAC && battery.onBattery { return .powerDisconnected }
    if battery.onBattery && battery.percent <= threshold { return .batteryLow }
    return nil
}

struct Battery {
    let percent: Int
    let onBattery: Bool
}

func batteryState() -> Battery? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for source in sources {
        guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = d[kIOPSCurrentCapacityKey] as? Int,
              let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
        return Battery(percent: current * 100 / maximum,
                       onBattery: d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue)
    }
    return nil
}

private let sessionLogger = Logger(subsystem: "local.insomnia", category: "session")
func sessionLog(_ message: String) {
    sessionLogger.notice("\(message, privacy: .public)")
}

private final class CommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

// pmset is only used to change settings. A stalled powerd must not block forever.
@discardableResult
func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe; p.standardError = pipe
    let exited = DispatchSemaphore(value: 0)
    p.terminationHandler = { _ in exited.signal() }
    do {
        try p.run()
        let reader = DispatchGroup()
        let output = CommandOutput()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output.set(data)
            reader.leave()
        }
        let timedOut = exited.wait(timeout: .now() + max(0.01, timeout)) == .timedOut
        if timedOut {
            if p.isRunning { p.terminate() }
            if exited.wait(timeout: .now() + 1) == .timedOut, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        p.waitUntilExit()
        reader.wait()
        let data = output.get()
        let text = String(data: data, encoding: .utf8) ?? ""
        return timedOut ? (-2, "Command timed out. " + text) : (p.terminationStatus, text)
    } catch { return (-1, error.localizedDescription) }
}

// Read the kernel's actual flag directly, without spawning pmset and depending
// on powerd/CFPreferences output for every watchdog poll and restore attempt.
func rootDomainBoolean(_ key: String) -> Bool? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    return IORegistryEntryCreateCFProperty(service, key as CFString,
                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
}
func sleepDisabled() -> Bool? { rootDomainBoolean("SleepDisabled") }

// A single unavailable reading is not evidence that the setting was removed.
// Persistent loss still ends the session; this never re-enables an external reset.
struct SleepStateMonitor {
    private var unavailableSince: TimeInterval?
    private var disabledSince: TimeInterval?
    mutating func endReason(state: Bool?, now: TimeInterval) -> SessionEnd? {
        if state == true { unavailableSince = nil; disabledSince = nil; return nil }
        if state == false {
            unavailableSince = nil
            if disabledSince == nil { disabledSince = now }
            return now - disabledSince! >= 2 ? .sleepProhibitionRemoved : nil
        }
        disabledSince = nil
        if unavailableSince == nil { unavailableSince = now }
        return now - unavailableSince! >= 10 ? .sleepStateUnavailable : nil
    }
}

func shouldStop(now: TimeInterval, heartbeat: TimeInterval?, deadline: TimeInterval,
                battery: Battery?, threshold: Int) -> Bool {
    sessionEnd(now: now, heartbeat: heartbeat, deadline: deadline, battery: battery, threshold: threshold) != nil
}

// Check the actual setting, including before the first write. A command error
// does not imply the setting remained unchanged; unavailable state is not success.
func restoreSleep(attempts: Int = 15, read: () -> Bool? = sleepDisabled,
                  restore: () -> (Int32, String) = { run("/usr/bin/pmset", ["-a", "disablesleep", "0"]) },
                  pause: () -> Void = { Thread.sleep(forTimeInterval: 2) }) -> Bool {
    if read() == false { return true }
    for attempt in 0..<max(0, attempts) {
        _ = restore()
        if read() == false { return true }
        if attempt + 1 < attempts { pause() }
    }
    return false
}

// Only the active session's Guardian owns this policy. Ending the session
// discards its countdown, including when the lid was already closed at startup.
struct LidDisplaySleepPolicy {
    private var closedSince: TimeInterval?
    private var requested = false
    private var previousMode: Mode?

    mutating func shouldRequest(now: TimeInterval, mode: Mode, lidClosed: Bool?) -> Bool {
        if previousMode != mode {
            closedSince = nil; requested = false; previousMode = mode
        }
        guard mode != .normal, lidClosed == true, now.isFinite else {
            closedSince = nil; requested = false
            return false
        }
        if closedSince == nil { closedSince = now }
        let delay: TimeInterval = mode == .travel ? 120 : 0
        guard !requested, now - closedSince! >= delay else { return false }
        requested = true
        return true
    }
}

func lidIsClosed() -> Bool? { rootDomainBoolean("AppleClamshellState") }
