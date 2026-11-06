import Foundation

enum RecoveryAction: Equatable {
    case keepWorkingConnection, needWiFiPermission, wifiOff, waitForInternet, joinHotspot
}

func recoveryAction(internet: Bool, wifiAuthorized: Bool, wifiOn: Bool,
                    currentSSID: String?, targetSSID: String, wiredRoute: Bool = false) -> RecoveryAction {
    // Travel mode prefers the selected iPhone over other Wi-Fi even when the
    // current network works. A working wired default route (including USB) stays.
    if internet && wiredRoute { return .keepWorkingConnection }
    if !wifiAuthorized { return .needWiFiPermission }
    if !wifiOn { return .wifiOff }
    if currentSSID == targetSSID { return internet ? .keepWorkingConnection : .waitForInternet }
    return .joinHotspot
}

struct ReconnectSchedule {
    private(set) var failures = 0
    private(set) var nextAttempt: TimeInterval = 0
    mutating func reset() { failures = 0; nextAttempt = 0 }
    mutating func failed(at now: TimeInterval) {
        let delay = min(60.0, 5.0 * pow(2.0, Double(min(failures, 4))))
        failures = min(failures + 1, 5)
        nextAttempt = now + delay
    }
    func remaining(at now: TimeInterval) -> Int { max(0, Int(ceil(nextAttempt - now))) }
}

// Preserve the user's preferred order; only networks already saved in macOS may
// be chosen. The iPhone is excluded even if it is a preferred saved network.
func returnNetworkOrder(known: [String], visible: Set<String>, previous: String?, hotspot: String) -> [String] {
    var result: [String] = []
    let preferred = previous.map { [$0] } ?? []
    let saved = Set(known)
    for name in preferred + known where name != hotspot && saved.contains(name) && visible.contains(name) {
        if !result.contains(name) { result.append(name) }
    }
    return result
}
