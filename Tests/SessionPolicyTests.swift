import Foundation

@main
struct SessionPolicyTests {
    static func main() throws {
        var stateMonitor = SleepStateMonitor()
        precondition(stateMonitor.endReason(state: true, now: 0) == nil)
        precondition(stateMonitor.endReason(state: nil, now: 1) == nil)
        precondition(stateMonitor.endReason(state: true, now: 2) == nil, "One unavailable sample must not end a session")
        precondition(stateMonitor.endReason(state: nil, now: 10) == nil)
        precondition(stateMonitor.endReason(state: nil, now: 19) == nil)
        precondition(stateMonitor.endReason(state: nil, now: 20) == .sleepStateUnavailable)
        precondition(stateMonitor.endReason(state: true, now: 21) == nil)
        precondition(stateMonitor.endReason(state: false, now: 22) == nil)
        precondition(stateMonitor.endReason(state: true, now: 23) == nil)
        precondition(stateMonitor.endReason(state: false, now: 30) == nil)
        precondition(stateMonitor.endReason(state: false, now: 32) == .sleepProhibitionRemoved)
        let commandStart = ProcessInfo.processInfo.systemUptime
        let command = run("/bin/sleep", ["10"], timeout: 0.1)
        precondition(command.0 == -2 && ProcessInfo.processInfo.systemUptime - commandStart < 3, "Stalled commands must time out")
        let echo = run("/usr/bin/printf", ["verified-output"])
        precondition(echo.0 == 0 && echo.1 == "verified-output")
        print("PASS: transient read failure, persistent unavailable state, external reset, command timeout and captured output")
        var writes = 0
        var pauses = 0
        precondition(restoreSleep(read: { false }, restore: { writes += 1; return (1, "error") }, pause: { pauses += 1 }))
        precondition(writes == 0 && pauses == 0, "Already-restored state must not retry or write")
        var reads = 0
        precondition(restoreSleep(read: { reads += 1; return reads == 1 ? true : false },
                                  restore: { writes += 1; return (1, "partial error") }, pause: {}))
        precondition(writes == 1, "Verified state wins over command exit status")
        writes = 0
        precondition(!restoreSleep(attempts: 3, read: { nil }, restore: { writes += 1; return (0, "") }, pause: { pauses += 1 }))
        precondition(writes == 3 && pauses == 2, "Unavailable state must return failure after bounded retries")
        precondition(!restoreSleep(attempts: 2, read: { true }, restore: { (0, "") }, pause: {}))
        print("PASS: already-restored state, partial command failure, bounded retries, unavailable state, prohibition still active")
        var display = LidDisplaySleepPolicy()
        precondition(!display.shouldRequest(now: 0, mode: .travel, lidClosed: false))
        precondition(!display.shouldRequest(now: 10, mode: .travel, lidClosed: true))
        precondition(!display.shouldRequest(now: 129, mode: .travel, lidClosed: true))
        precondition(display.shouldRequest(now: 130, mode: .travel, lidClosed: true))
        precondition(!display.shouldRequest(now: 131, mode: .travel, lidClosed: true), "One request per closure")
        precondition(!display.shouldRequest(now: 140, mode: .travel, lidClosed: false))
        precondition(!display.shouldRequest(now: 150, mode: .travel, lidClosed: true))
        precondition(!display.shouldRequest(now: 200, mode: .travel, lidClosed: nil))
        precondition(!display.shouldRequest(now: 270, mode: .travel, lidClosed: true), "Unknown lid state cancels countdown")
        precondition(!display.shouldRequest(now: 300, mode: .normal, lidClosed: true))
        precondition(!display.shouldRequest(now: 400, mode: .travel, lidClosed: true))
        precondition(!display.shouldRequest(now: 519, mode: .travel, lidClosed: true), "Mode exit cancels countdown")
        precondition(display.shouldRequest(now: 520, mode: .travel, lidClosed: true))
        precondition(display.shouldRequest(now: 600, mode: .server, lidClosed: true))
        precondition(!display.shouldRequest(now: 601, mode: .server, lidClosed: true))
        var reopened = LidDisplaySleepPolicy()
        precondition(!reopened.shouldRequest(now: 0, mode: .travel, lidClosed: true))
        precondition(!reopened.shouldRequest(now: 119, mode: .travel, lidClosed: false))
        precondition(!reopened.shouldRequest(now: 120, mode: .travel, lidClosed: true))
        precondition(!reopened.shouldRequest(now: 239, mode: .travel, lidClosed: true))
        precondition(reopened.shouldRequest(now: 240, mode: .travel, lidClosed: true))
        print("PASS: travel display delay 120s, reopen cancellation, fresh closure countdown, mode exit, unknown sensor, server display sleep, one request per closure")
        let ac = Battery(percent: 10, onBattery: false)
        let charged = Battery(percent: 80, onBattery: true)
        func reason(_ battery: Battery?, server: Bool = false, deadline: Double = 200, heartbeat: Double? = 100) -> SessionEnd? {
            sessionEnd(now: 100, heartbeat: heartbeat, deadline: deadline,
                       battery: battery, threshold: 15, requiresAC: server)
        }
        precondition(reason(ac, server: true) == nil, "Server works while plugged in even at low battery charge")
        precondition(reason(charged, server: true) == .powerDisconnected, "Server must end immediately after unplugging")
        precondition(reason(charged) == nil, "Travel must continue after unplugging")
        precondition(reason(Battery(percent: 15, onBattery: true)) == .batteryLow)
        precondition(reason(ac) == nil, "Battery cutoff must not stop AC-powered travel")
        precondition(reason(nil, server: true) == .batteryUnavailable)
        precondition(reason(ac, server: true, deadline: 100) == .timerExpired)
        precondition(reason(charged, deadline: 100) == .timerExpired)
        precondition(reason(charged, deadline: 0) == nil, "Unlimited duration must not expire")
        precondition(reason(charged, heartbeat: 84) == .heartbeatLost, "Watchdog must work for every mode")
        precondition(reason(ac, server: true, heartbeat: nil) == .heartbeatLost)
        let original = deadlineAfter(minutes: 1, now: 100)
        let extended = deadlineAfter(minutes: 2, now: 120)
        precondition(original == 160 && extended == 240)
        precondition(sessionEnd(now: 161, heartbeat: 161, deadline: extended, battery: charged, threshold: 15) == nil,
                     "Editing the timer must replace the old deadline")
        precondition(sessionEnd(now: 240, heartbeat: 240, deadline: extended, battery: charged, threshold: 15) == .timerExpired)
        precondition(deadlineAfter(minutes: 0, now: 500) == 0)
        let lease = SessionLease(heartbeat: 100, deadline: extended)
        let decoded = try JSONDecoder().decode(SessionLease.self, from: JSONEncoder().encode(lease))
        precondition(decoded.isValid && decoded.deadline == extended)
        precondition(!SessionLease(heartbeat: 100, deadline: -1).isValid)
        precondition(!SessionLease(heartbeat: .infinity, deadline: 0).isValid)
        // The privileged helper reads changes from the atomic lease file, not an old CLI deadline.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("insomnia-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(lease).write(to: url, options: .atomic)
        precondition(SessionLease.read(from: url)?.deadline == extended)
        try Data("broken".utf8).write(to: url, options: .atomic)
        precondition(SessionLease.read(from: url) == nil, "Malformed lease must fail closed")
        precondition(Mode.allCases == [.normal, .server, .travel])
        print("PASS: server AC-only, travel battery operation, low battery, AC at low charge, missing power data, timer expiry for both modes, unlimited duration, watchdog, live timer replacement, atomic lease and corrupt lease")
    }
}
