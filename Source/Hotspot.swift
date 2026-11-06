import Foundation
import CoreWLAN
import Network
import Security

struct HotspotError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum HotspotKeychain {
    private static let service = "local.insomnia.hotspot"
    private static func query(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: ssid]
    }
    static func save(_ password: String, ssid: String) throws {
        var q = query(ssid)
        let data = Data(password.utf8)
        let result = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            q[kSecValueData as String] = data
            q[kSecAttrLabel as String] = "Insomnia · раздача iPhone"
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw HotspotError("Связка ключей: \(added). Пароль не сохранён.") }
        } else if result != errSecSuccess {
            throw HotspotError("Связка ключей: \(result). Пароль не сохранён.")
        }
    }
    static func load(ssid: String) throws -> String {
        var q = query(ssid)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = SecItemCopyMatching(q as CFDictionary, &result)
        guard code == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw HotspotError("Не удалось получить пароль раздачи из Связки ключей (\(code)). Укажи пароль в настройках раздачи Insomnia.")
        }
        return value
    }
    static func forget(ssid: String) throws {
        let code = SecItemDelete(query(ssid) as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else {
            throw HotspotError("Не удалось удалить пароль из Связки ключей: \(code).")
        }
    }
}

struct ConnectionStatus {
    var title: String
    var detail: String
    var online: Bool?
    static let disabled = ConnectionStatus(title: "Подключение к iPhone выключено", detail: "", online: nil)
}

final class HotspotController {
    private struct Session {
        let id: UUID
        let ssid: String
        let password: String
    }
    private let queue = DispatchQueue(label: "Insomnia.connection", qos: .utility)
    private let lock = NSLock()
    private var session: Session?
    private var wifiAuthorized = false
    private var returnID: UUID?
    private var previousSSID: String?
    private var timer: DispatchSourceTimer?
    private let pathMonitor = NWPathMonitor()
    private let wifi = CWWiFiClient.shared()
    private let urlSession: URLSession
    private var schedule = ReconnectSchedule()
    private var lastCheck: TimeInterval = -.infinity
    private var lastOnline: Bool?
    private var outageSince: Date?
    private var pathDescription = "текущее подключение"
    private var lastDetail = ""
    var onChange: ((ConnectionStatus) -> Void)?

    static var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Insomnia", isDirectory: true).appendingPathComponent("network-events.jsonl")
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 7
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        urlSession = URLSession(configuration: config)
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.usesInterfaceType(.wiredEthernet) { self.pathDescription = "проводное подключение" }
            else if path.usesInterfaceType(.wifi) { self.pathDescription = "Wi‑Fi" }
            else { self.pathDescription = "текущее подключение / VPN" }
            // Coalesce bursts of route notifications. The periodic timer retries as well.
            self.check(minimumInterval: 3)
        }
        pathMonitor.start(queue: queue)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 5, leeway: .seconds(1))
        t.setEventHandler { [weak self] in self?.check(minimumInterval: self?.lastOnline == true ? 20 : 8) }
        timer = t
        t.resume()
    }

    var isEnabled: Bool {
        lock.lock(); defer { lock.unlock() }
        return session != nil
    }
    var isRestoring: Bool {
        lock.lock(); defer { lock.unlock() }
        return returnID != nil
    }
    func setWiFiAuthorized(_ value: Bool) {
        lock.lock(); wifiAuthorized = value; let activeID = session?.id; lock.unlock()
        guard let activeID else { return }
        queue.async { [weak self] in
            guard let self, self.current(activeID) else { return }
            self.lastCheck = -.infinity; self.check(minimumInterval: 0)
        }
    }
    func start(ssid: String, password: String) {
        let s = Session(id: UUID(), ssid: ssid, password: password)
        lock.lock(); returnID = nil; session = s; lock.unlock()
        onChange?(ConnectionStatus(title: "Интернет: проверяю…", detail: "Приоритет iPhone включён · ищу выбранную раздачу", online: nil))
        queue.async { [weak self] in
            guard let self, self.current(s.id) else { return }
            self.schedule.reset(); self.lastCheck = -.infinity
            self.lastOnline = nil; self.outageSince = nil; self.lastDetail = ""
            self.previousSSID = nil
            if self.snapshot().1, let origin = self.wifi.interface()?.ssid(), origin != s.ssid {
                self.previousSSID = origin
            }
            self.record("monitor_started", detail: "version=0.6.2 policy=prefer_iphone")
            self.check(minimumInterval: 0)
        }
    }
    func stop(restoreWiFi: Bool = false) {
        // Invalidate immediately, including a scan already in progress.
        lock.lock()
        let old = session
        let id = restoreWiFi && old != nil ? UUID() : nil
        session = nil; returnID = id
        lock.unlock()
        onChange?(id == nil ? .disabled : ConnectionStatus(title: "Возвращаюсь на обычный Wi‑Fi…", detail: "Проверяю доступные сохранённые сети", online: nil))
        queue.async { [weak self] in
            guard let self else { return }
            self.record("monitor_stopped")
            if let id, let old { self.restoreKnownWiFi(id, from: old) }
        }
    }
    func checkNow() {
        queue.async { [weak self] in self?.lastCheck = -.infinity; self?.schedule.reset(); self?.check(minimumInterval: 0) }
    }
    private func snapshot() -> (Session?, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (session, wifiAuthorized)
    }
    private func current(_ id: UUID, needsAuthorization: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return session?.id == id && (!needsAuthorization || wifiAuthorized)
    }
    private func publish(_ s: Session, _ status: ConnectionStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(s.id) else { return }
            self.onChange?(status)
        }
    }

    private func internetAvailable(_ id: UUID) -> Bool {
        // Two independent HTTPS probes. No AI prompts, account tokens, or cookies are sent.
        let probes: [(String, Int)] = [("https://www.apple.com/library/test/success.html", 200),
                                       ("https://cp.cloudflare.com/generate_204", 204)]
        let group = DispatchGroup()
        let resultLock = NSLock()
        var passed = false
        var tasks: [URLSessionDataTask] = []
        for (address, expected) in probes {
            group.enter()
            var request = URLRequest(url: URL(string: address)!)
            request.timeoutInterval = 5
            request.setValue("Insomnia/0.6.2", forHTTPHeaderField: "User-Agent")
            let task = urlSession.dataTask(with: request) { data, response, error in
                defer { group.leave() }
                guard error == nil, let r = response as? HTTPURLResponse,
                      r.statusCode == expected, r.url?.absoluteString == address else { return }
                let valid = expected == 204 || (String(data: data ?? Data(), encoding: .utf8)?.contains("<BODY>Success</BODY>") == true)
                if valid { resultLock.lock(); passed = true; resultLock.unlock() }
            }
            tasks.append(task)
            task.resume()
        }
        _ = group.wait(timeout: .now() + 8)
        tasks.forEach { $0.cancel() }
        resultLock.lock(); let online = passed; resultLock.unlock()
        return operationCurrent(id) && online
    }

    private func check(minimumInterval: TimeInterval) {
        let (candidate, authorized) = snapshot()
        guard let s = candidate else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCheck >= minimumInterval else { return }
        lastCheck = now
        let online = internetAvailable(s.id)
        guard current(s.id) else { return }
        updateAvailability(online)
        let iface = wifi.interface()
        let currentSSID = authorized ? iface?.ssid() : nil
        if previousSSID == nil, let currentSSID, currentSSID != s.ssid { previousSSID = currentSSID }
        let action = recoveryAction(internet: online, wifiAuthorized: authorized,
                                    wifiOn: iface?.powerOn() ?? false,
                                    currentSSID: currentSSID, targetSSID: s.ssid,
                                    wiredRoute: pathMonitor.currentPath.usesInterfaceType(.wiredEthernet))
        record("check_result", detail: "online=\(online ? 1 : 0) wifi_authorized=\(authorized ? 1 : 0) wifi_on=\(iface?.powerOn() == true ? 1 : 0) target_connected=\(currentSSID == s.ssid ? 1 : 0) wired_route=\(pathMonitor.currentPath.usesInterfaceType(.wiredEthernet) ? 1 : 0) action=\(action)")
        let elapsed = outageSince.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        var status = ConnectionStatus(title: online ? "Интернет доступен" : "Интернет не подтверждён · \(elapsed) с",
                                      detail: "", online: online)
        switch action {
        case .keepWorkingConnection:
            schedule.reset()
            status.detail = "\(pathDescription) · рабочее подключение сохранено"
        case .needWiFiPermission:
            status.detail = "Для автоподключения Wi‑Fi нужен доступ к геолокации"
        case .wifiOff:
            status.detail = "Wi‑Fi выключен · включи его для подключения к iPhone"
        case .waitForInternet:
            schedule.reset()
            status.detail = "Раздача подключена · ожидаю доступ в интернет"
        case .joinHotspot:
            let remaining = schedule.remaining(at: ProcessInfo.processInfo.systemUptime)
            if remaining > 0 {
                status.detail = "Поиск раздачи через \(remaining) с"
            } else if let iface {
                publish(s, ConnectionStatus(title: status.title, detail: "Ищу выбранную раздачу iPhone…", online: status.online))
                do {
                    guard current(s.id, needsAuthorization: true) else { return }
                    let results = try iface.scanForNetworks(withSSID: Data(s.ssid.utf8))
                    guard current(s.id, needsAuthorization: true) else { return }
                    guard let network = results.filter({ $0.ssid == s.ssid }).max(by: { $0.rssiValue < $1.rssiValue }) else {
                        schedule.failed(at: ProcessInfo.processInfo.systemUptime)
                        status.detail = online ? "iPhone не виден · текущее подключение сохранено" : "Раздача не видна · проверь «Разрешать другим» на iPhone"
                        changedDetail("hotspot_not_visible")
                        publish(s, status)
                        return
                    }
                    // Re-evaluate the policy after the blocking scan. A recovered
                    // home Wi-Fi must not cancel iPhone preference; a healthy USB must.
                    let freshOnline = internetAvailable(s.id)
                    guard current(s.id, needsAuthorization: true), iface.powerOn() else { return }
                    updateAvailability(freshOnline)
                    let freshAction = recoveryAction(internet: freshOnline, wifiAuthorized: true, wifiOn: true,
                        currentSSID: iface.ssid(), targetSSID: s.ssid,
                        wiredRoute: pathMonitor.currentPath.usesInterfaceType(.wiredEthernet))
                    if freshAction != .joinHotspot {
                        schedule.reset()
                        publish(s, ConnectionStatus(title: freshOnline ? "Интернет доступен" : "Интернет не подтверждён",
                            detail: freshOnline ? "Рабочее подключение сохранено" : "Раздача подключена · ожидаю интернет", online: freshOnline))
                        return
                    }
                    record("association_started", detail: "reason=prefer_iphone")
                    try iface.associate(to: network, password: s.password)
                    guard current(s.id) else { return }
                    record("hotspot_associated")
                    lastOnline = nil; lastCheck = -.infinity
                    status.title = "Раздача подключена · проверяю интернет…"
                    status.online = nil
                    schedule.failed(at: ProcessInfo.processInfo.systemUptime)
                    status.detail = "Раздача подключена · проверка интернета через несколько секунд"
                } catch {
                    guard current(s.id) else { return }
                    schedule.failed(at: ProcessInfo.processInfo.systemUptime)
                    // Never log credentials or arbitrary exception text.
                    status.detail = "Не удалось подключиться · проверь пароль и доступность раздачи"
                    changedDetail("association_failed code=\((error as NSError).code)")
                }
            } else { status.detail = "Интерфейс Wi‑Fi недоступен" }
        }
        publish(s, status)
    }

    private func operationCurrent(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return session?.id == id || returnID == id
    }
    private func returning(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return session == nil && returnID == id
    }
    private func publishReturn(_ id: UUID, detail: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.returning(id) else { return }
            self.onChange?(ConnectionStatus(title: "Возвращаюсь на обычный Wi‑Fi…", detail: detail, online: nil))
        }
    }
    private func finishReturn(_ id: UUID, detail: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.session == nil, self.returnID == id else { self.lock.unlock(); return }
            self.returnID = nil
            self.lock.unlock()
            self.onChange?(ConnectionStatus(title: "Подключение к iPhone выключено", detail: detail, online: nil))
        }
    }
    private func savedPassword(_ ssid: String) throws -> String {
        for domain in [CWKeychainDomain.system, .user] {
            var value: NSString?
            let code = CWKeychainFindWiFiPassword(domain, Data(ssid.utf8), &value)
            if code == errSecSuccess, let value { return value as String }
            if code == errSecUserCanceled || code == errSecAuthFailed || code == errSecInteractionNotAllowed {
                throw NSError(domain: "InsomniaSavedWiFi", code: Int(code))
            }
        }
        throw NSError(domain: "InsomniaSavedWiFi", code: Int(errSecItemNotFound))
    }
    private func isEnterprise(_ security: CWSecurity) -> Bool {
        switch security {
        case .dynamicWEP, .wpaEnterprise, .wpaEnterpriseMixed, .wpa2Enterprise, .enterprise, .wpa3Enterprise: return true
        default: return false
        }
    }
    private func returnReady(_ id: UUID, iface: CWInterface) -> Bool {
        guard returning(id) else { return false }
        guard snapshot().1, iface.powerOn() else {
            record("wifi_return_interrupted", detail: "permission_or_wifi_off")
            finishReturn(id, detail: "Возврат остановлен · нужен включённый Wi‑Fi и доступ к имени сети")
            return false
        }
        return true
    }
    private func restoreKnownWiFi(_ id: UUID, from old: Session) {
        guard returning(id) else { return }
        record("wifi_return_started")
        guard snapshot().1, let iface = wifi.interface(), iface.powerOn() else {
            record("wifi_return_unavailable", detail: "permission_or_wifi_off")
            finishReturn(id, detail: "Для возврата нужен включённый Wi‑Fi и доступ к имени сети")
            return
        }
        // If the user or macOS already selected another network, preserve it.
        if let current = iface.ssid(), current != old.ssid {
            record("wifi_return_not_needed")
            finishReturn(id, detail: "Раздача уже не выбрана · текущее подключение сохранено")
            return
        }
        guard let configuration = iface.configuration(),
              let profiles = configuration.networkProfiles.array as? [CWNetworkProfile] else {
            record("wifi_return_unavailable", detail: "saved_profiles_unavailable")
            finishReturn(id, detail: "Список сохранённых сетей недоступен · раздача сохранена")
            return
        }
        let supported = profiles.filter { !isEnterprise($0.security) }
        let known = supported.compactMap { $0.ssid }
        do {
            var networks = try iface.scanForNetworks(withSSID: nil)
            guard returnReady(id, iface: iface) else { return }
            // Include a previously used hidden network in the directed scan.
            if let previous = previousSSID, known.contains(previous), previous != old.ssid,
               !networks.contains(where: { $0.ssid == previous }) {
                if let extra = try? iface.scanForNetworks(withSSID: Data(previous.utf8)) { networks.formUnion(extra) }
            }
            guard returnReady(id, iface: iface) else { return }
            let order = returnNetworkOrder(known: known, visible: Set(networks.compactMap { $0.ssid }),
                                           previous: previousSSID, hotspot: old.ssid)
            record("wifi_return_candidates", detail: "count=\(order.count)")
            var attemptedAssociation = false
            var lastAttemptSSID: String?
            var keychainDenied = false
            for (index, name) in order.enumerated() {
                guard returnReady(id, iface: iface) else { return }
                // Stop if the user manually switched elsewhere while the scan ran.
                if let current = iface.ssid(), current != old.ssid && current != lastAttemptSSID {
                    finishReturn(id, detail: "Текущая сеть уже изменена · подключение сохранено")
                    return
                }
                guard let profile = supported.first(where: { $0.ssid == name }),
                      let network = networks.filter({ $0.ssid == name && $0.supportsSecurity(profile.security) })
                        .max(by: { $0.rssiValue < $1.rssiValue }) else { continue }
                publishReturn(id, detail: "Подключаюсь к сохранённой сети · попытка \(index + 1) из \(order.count)")
                do {
                    let password = profile.security == .none ? nil : try savedPassword(name)
                    guard returnReady(id, iface: iface) else { return }
                    attemptedAssociation = true
                    lastAttemptSSID = name
                    try iface.associate(to: network, password: password)
                    guard returning(id) else { return }
                    // Give DHCP a short grace period; cancellation remains responsive.
                    for _ in 0..<4 {
                        guard returning(id) else { return }
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                    if iface.ssid() == name && internetAvailable(id) {
                        record("wifi_return_succeeded", detail: "candidate=\(index + 1)")
                        finishReturn(id, detail: "Вернулся на сохранённый Wi‑Fi · интернет доступен")
                        return
                    }
                    record("wifi_return_no_internet", detail: "candidate=\(index + 1)")
                } catch {
                    guard returning(id) else { return }
                    let e = error as NSError
                    record("wifi_return_failed", detail: "candidate=\(index + 1) code=\(e.code)")
                    // Respect a denied keychain prompt instead of opening more prompts.
                    if e.domain == "InsomniaSavedWiFi" && [Int(errSecUserCanceled), Int(errSecAuthFailed), Int(errSecInteractionNotAllowed)].contains(e.code) { keychainDenied = true; break }
                }
            }
            guard returning(id) else { return }
            // Never disconnect first. If an attempted join broke the original link,
            // make one attempt to recover it without re-enabling travel mode.
            if let current = iface.ssid(), current != old.ssid && current != lastAttemptSSID {
                finishReturn(id, detail: "Текущая сеть изменена · подключение сохранено")
                return
            }
            if attemptedAssociation && iface.ssid() != old.ssid {
                publishReturn(id, detail: "Сохранённые сети не подошли · восстанавливаю связь с iPhone")
                if let network = try? iface.scanForNetworks(withSSID: Data(old.ssid.utf8))
                    .filter({ $0.ssid == old.ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
                    guard returnReady(id, iface: iface) else { return }
                    try? iface.associate(to: network, password: old.password)
                }
            }
            record("wifi_return_finished_without_match")
            var detail = iface.ssid() == old.ssid ? "Подходящий Wi‑Fi недоступен · остался на iPhone" : "Не удалось вернуть обычный Wi‑Fi · проверь подключение"
            if keychainDenied { detail = "Нет доступа к сохранённому паролю · проверь разрешение Связки ключей" }
            finishReturn(id, detail: detail)
        } catch {
            guard returning(id) else { return }
            record("wifi_return_scan_failed", detail: "code=\((error as NSError).code)")
            finishReturn(id, detail: "Не удалось проверить известные сети · подключение не отключалось")
        }
    }

    private func updateAvailability(_ online: Bool) {
        guard online != lastOnline else { return }
        if online {
            let seconds = outageSince.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
            record("internet_available", detail: "outage_seconds=\(seconds)")
            outageSince = nil
        } else { outageSince = Date(); record("internet_unconfirmed") }
        lastOnline = online
    }

    private func changedDetail(_ detail: String) {
        if lastDetail != detail { record(detail); lastDetail = detail }
    }
    private func record(_ event: String, detail: String = "") {
        do {
            let url = Self.logURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
               size.intValue > 256_000 {
                let old = url.appendingPathExtension("previous")
                if FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
                try FileManager.default.moveItem(at: url, to: old)
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let row: [String: Any] = ["time": ISO8601DateFormatter().string(from: Date()), "event": event, "detail": detail]
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0a)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } catch { /* A log failure must never interrupt networking or sleep recovery. */ }
    }
}
