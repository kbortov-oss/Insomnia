import Foundation
import Darwin

private var interrupted: Int32 = 0

@main
struct Guardian {
    static func main() {
        let args = CommandLine.arguments
        if args.count == 2 && args[1] == "--self-test" {
            let b = Battery(percent: 80, onBattery: true)
            precondition(!shouldStop(now: 100, heartbeat: 99, deadline: 200, battery: b, threshold: 15))
            precondition(shouldStop(now: 100, heartbeat: 84, deadline: 200, battery: b, threshold: 15))
            precondition(shouldStop(now: 100, heartbeat: nil, deadline: 200, battery: b, threshold: 15))
            precondition(shouldStop(now: 100, heartbeat: 100, deadline: 100, battery: b, threshold: 15))
            precondition(shouldStop(now: 100, heartbeat: 100, deadline: 0, battery: Battery(percent: 15, onBattery: true), threshold: 15))
            precondition(!shouldStop(now: 100, heartbeat: 100, deadline: 0, battery: Battery(percent: 10, onBattery: false), threshold: 15))
            precondition(shouldStop(now: 100, heartbeat: 100, deadline: 0, battery: nil, threshold: 15))
            precondition(shouldStop(now: 100, heartbeat: 106, deadline: 0, battery: b, threshold: 15))
            print("PASS: heartbeat expiry, missing heartbeat, timer, battery cutoff, AC power, unavailable battery, future timestamp")
            return
        }
        guard geteuid() == 0 else { fputs("Administrator authorization is required.\n", stderr); exit(1) }
        if args.count == 2 && args[1] == "--restore" {
            guard restoreSleep() else { print("RESTORE_FAILED"); exit(2) }
            print("RESTORED")
            return
        }
        guard args.count == 6, args[1] == "--session",
              let parent = Int32(args[2]), parent > 1,
              let threshold = Int(args[4]), (10...50).contains(threshold),
              let mode = Mode(rawValue: args[5]), mode != .normal else { exit(3) }
        let heartbeatURL = URL(fileURLWithPath: args[3])
        var endReason = "activationFailed"
        sessionLog("Guardian starting mode=\(mode.rawValue) pid=\(getpid())")
        func stop() -> Bool {
            if interrupted != 0 || kill(parent, 0) != 0 { endReason = "parentExited"; return true }
            guard let lease = SessionLease.read(from: heartbeatURL) else { endReason = "leaseRemoved"; return true }
            if let reason = sessionEnd(now: Date().timeIntervalSince1970,
                heartbeat: lease.heartbeat, deadline: lease.deadline, battery: batteryState(),
                threshold: threshold, requiresAC: mode == .server) {
                endReason = reason.rawValue
                return true
            }
            return false
        }
        // Never take ownership of a sleep prohibition set by another application.
        guard sleepDisabled() == false, !stop() else {
            sessionLog("Guardian not started reason=\(endReason) state=\(String(describing: sleepDisabled()))")
            print("NOT_STARTED\nREASON \(endReason)")
            exit(4)
        }
        signal(SIGTERM) { _ in interrupted = 1 }
        signal(SIGINT) { _ in interrupted = 1 }
        signal(SIGHUP) { _ in interrupted = 1 }
        let result = run("/usr/bin/pmset", ["-a", "disablesleep", "1"])
        // Even an unsuccessful command may have partially changed a setting.
        sessionLog("Activation command code=\(result.0) output=\(result.1.prefix(300))")
        if sleepDisabled() == true {
            // Per-session acknowledgment: the UI must not infer readiness from
            // the global flag, which another process can also change.
            var ready = false
            do { try createReadyAcknowledgement(in: heartbeatURL.deletingLastPathComponent()); ready = true }
            catch { sessionLog("Ready acknowledgment failed") }
            sessionLog("Guardian active mode=\(mode.rawValue)")
            var displayPolicy = LidDisplaySleepPolicy()
            var stateMonitor = SleepStateMonitor()
            while ready && !stop() {
                if let reason = stateMonitor.endReason(state: sleepDisabled(), now: ProcessInfo.processInfo.systemUptime) {
                    endReason = reason.rawValue; break
                }
                if displayPolicy.shouldRequest(now: ProcessInfo.processInfo.systemUptime,
                                               mode: mode, lidClosed: lidIsClosed()) {
                    // Recheck after the countdown and immediately before issuing the request.
                    if !stop(), lidIsClosed() == true {
                        let displayResult = run("/usr/bin/pmset", ["displaysleepnow"])
                        sessionLog("Display sleep request code=\(displayResult.0)")
                    }
                }
                Thread.sleep(forTimeInterval: 1)
            }
        }
        // Retry temporary powerd failures, but return control to recovery UI
        // instead of leaving all mode choices locked indefinitely.
        sessionLog("Guardian stopping reason=\(endReason)")
        guard restoreSleep() else {
            sessionLog("Restore failed reason=\(endReason) state=\(String(describing: sleepDisabled()))")
            print("RESTORE_FAILED\nREASON \(endReason)")
            exit(2)
        }
        sessionLog("Restore confirmed reason=\(endReason)")
        print("RESTORED\nREASON \(endReason)")
        if endReason == "activationFailed" { exit(5) }
    }
}
