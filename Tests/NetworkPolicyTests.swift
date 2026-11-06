import Foundation

@main
struct NetworkPolicyTests {
    static func main() {
        // Real travel scenarios: preserve a healthy USB route, fall back after cable
        // removal, wait during a coverage outage, and respect user-disabled Wi-Fi.
        func decision(_ online: Bool, _ permission: Bool = true, _ power: Bool = true, _ ssid: String? = nil, wired: Bool = false) -> RecoveryAction {
            recoveryAction(internet: online, wifiAuthorized: permission, wifiOn: power,
                           currentSSID: ssid, targetSSID: "My iPhone", wiredRoute: wired)
        }
        precondition(decision(true, false, false, wired: true) == .keepWorkingConnection, "Working USB requires no Wi-Fi permission")
        precondition(decision(true, true, true, "Home") == .joinHotspot, "Travel mode must leave healthy home Wi-Fi for iPhone")
        precondition(decision(false) == .joinHotspot, "Cable removed, hotspot available: attempt fallback")
        precondition(decision(false, true, true, "My iPhone") == .waitForInternet, "Coverage outage must not reset Wi-Fi")
        precondition(decision(false, true, true, "Hotel") == .joinHotspot, "Captive or dead network may fall back to iPhone")
        precondition(decision(false, false) == .needWiFiPermission, "Missing SSID permission must not mean disconnected")
        precondition(decision(false, true, false) == .wifiOff, "Respect manually disabled Wi-Fi")
        precondition(decision(true, true, true, "My iPhone") == .keepWorkingConnection, "Do not rejoin an already-connected iPhone")
        precondition(decision(true, true, true, "Home", wired: true) == .keepWorkingConnection, "Working USB wins over Wi-Fi preference")
        precondition(decision(false, true, true, "Home", wired: true) == .joinHotspot, "A connected but offline cable must not prevent Wi-Fi fallback")
        precondition(decision(true, false, true, "Home") == .needWiFiPermission, "Explain blocked iPhone preference even while home internet works")
        let saved = ["My iPhone", "Office", "Home", "Cafe", "Home"]
        precondition(returnNetworkOrder(known: saved, visible: ["Home", "Office", "My iPhone", "Stranger"], previous: "Home", hotspot: "My iPhone") == ["Home", "Office"], "Return to previous saved network first, never iPhone or unknown Wi-Fi")
        precondition(returnNetworkOrder(known: saved, visible: ["Office", "Cafe"], previous: "Home", hotspot: "My iPhone") == ["Office", "Cafe"], "Unavailable previous network must not block other saved networks")
        precondition(returnNetworkOrder(known: saved, visible: ["My iPhone", "Stranger"], previous: "Home", hotspot: "My iPhone").isEmpty, "No known networks must leave iPhone untouched")
        precondition(returnNetworkOrder(known: ["Office"], visible: ["Home", "Office"], previous: "Home", hotspot: "My iPhone") == ["Office"], "A forgotten previous network must not be rejoined")
        precondition(returnNetworkOrder(known: saved, visible: ["Home", "Office"], previous: nil, hotspot: "My iPhone") == ["Office", "Home"], "Without a previous network use the macOS saved order")
        var schedule = ReconnectSchedule()
        var now = 0.0
        for delay in [5, 10, 20, 40, 60, 60, 60] {
            schedule.failed(at: now)
            precondition(schedule.remaining(at: now) == delay, "Retry backoff must be bounded")
            now += Double(delay)
            precondition(schedule.remaining(at: now) == 0)
        }
        schedule.reset()
        schedule.failed(at: now)
        precondition(schedule.remaining(at: now) == 5, "Recovery starts a new retry sequence")
        print("PASS: iPhone preferred over healthy home Wi-Fi, healthy USB preserved, offline USB fallback, existing iPhone preserved, coverage outage, permission, Wi-Fi power, bounded retries, previous-network return, saved-network fallback, unknown-network exclusion")
    }
}
