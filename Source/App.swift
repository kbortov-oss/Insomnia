import AppKit
import ServiceManagement
import CoreLocation

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CLLocationManagerDelegate {
    private var status: NSStatusItem!
    private var menu = NSMenu()
    private var ticker: Timer?
    private var mode: Mode = .normal
    private var pendingMode: Mode?
    private var deadline: Date?
    private var guardian: Process?
    private var heartbeatURL: URL?
    private var startedLid = false
    private var stopping = false
    private var transitioning = false
    private var waitingForWiFi = false
    private var quitting = false
    private var nextMode: Mode?
    private var recoveryRequired = false
    private var pendingCredentials: (String, String)?
    private var lastNotice: String?
    private var remainingItem: NSMenuItem?
    private let travel = HotspotController()
    private let locationManager = CLLocationManager()
    private var connectionStatus = ConnectionStatus.disabled
    private var connectionTitleItem: NSMenuItem?
    private var connectionDetailItem: NSMenuItem?
    private let prefs = UserDefaults.standard
    private var cutoff: Int { prefs.object(forKey: "cutoff") as? Int ?? 15 }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    private func duration(for mode: Mode) -> Int {
        let stored = prefs.object(forKey: "duration.\(mode.rawValue)") as? Int
        let legacy = mode == .travel ? prefs.object(forKey: "duration") as? Int : nil
        let value = stored ?? legacy ?? (mode == .server ? 0 : 60)
        return (0...10080).contains(value) ? value : 60
    }
    private func durationLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "Без ограничения" }
        if minutes % 60 == 0 { return "\(minutes / 60) ч" }
        return "\(minutes) мин"
    }
    private var remainingText: String {
        guard startedLid, mode != .normal else { return "Таймер не активен" }
        guard let deadline else { return "Без ограничения" }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
        if seconds >= 3600 { return "Осталось \(seconds / 3600) ч \((seconds % 3600) / 60) мин" }
        if seconds >= 60 { return "Осталось \(Int(ceil(Double(seconds) / 60))) мин" }
        return "Осталось \(seconds) с"
    }
    private func newMenu() -> NSMenu { let m = NSMenu(); m.autoenablesItems = false; return m }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 { NSApp.terminate(nil); return }
        // AppKit restores this item's saved placement. Seed a right-side position
        // on first launch so crowded menu bars do not put it behind the camera housing.
        prefs.register(defaults: ["NSStatusItem Preferred Position Insomnia": 220])
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "Insomnia"
        menu.autoenablesItems = false
        menu.delegate = self
        status.menu = menu
        recoveryRequired = prefs.bool(forKey: "lidSessionUnfinished")
        if recoveryRequired && sleepDisabled() == false {
            recoveryRequired = false; prefs.removeObject(forKey: "lidSessionUnfinished")
        }
        travel.onChange = { [weak self] value in
            guard let self else { return }
            self.connectionStatus = value
            self.connectionTitleItem?.title = value.title
            self.connectionDetailItem?.title = value.detail
            self.updateIcon()
            if self.waitingForWiFi && !self.travel.isRestoring {
                self.waitingForWiFi = false
                if self.guardian != nil { self.stopGuardian() }
                else { self.completeTransitionIfReady() }
            }
        }
        locationManager.delegate = self
        refreshLocationPermission()
        updateIcon(); rebuildMenu()
        ticker = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)
        if recoveryRequired {
            DispatchQueue.main.async { self.alert("Нужно восстановить сон", "Предыдущий сеанс завершился без подтверждения восстановления. В меню доступен пункт «Восстановить обычный сон…».") }
        }
    }
    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }
    private func item(_ title: String, action: Selector? = nil, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self; i.tag = tag; i.isEnabled = action != nil
        return i
    }
    private func timerChoices(for context: Mode) -> NSMenu {
        let m = newMenu()
        for n in [15, 30, 60, 120, 240, 480, 0] {
            let i = item(durationLabel(n), action: #selector(setDuration(_:)), tag: n)
            i.representedObject = context.rawValue
            i.state = duration(for: context) == n ? .on : .off
            i.isEnabled = !transitioning && !recoveryRequired && pendingMode == nil
            m.addItem(i)
        }
        m.addItem(.separator())
        let custom = item("Другая длительность…", action: #selector(customDuration(_:)))
        custom.representedObject = context.rawValue
        custom.isEnabled = !transitioning && !recoveryRequired && pendingMode == nil
        m.addItem(custom)
        m.addItem(item(startedLid && mode == context ? "Изменение запускает отсчёт заново." : "Отсчёт начнётся после включения режима."))
        return m
    }
    private func rebuildMenu() {
        menu.removeAllItems()
        var title = mode.title
        if pendingMode != nil { title = "Ожидаю разрешение администратора…" }
        if transitioning || stopping { title = waitingForWiFi ? "Возвращаю обычный Wi‑Fi…" : "Возвращаю обычный сон…" }
        menu.addItem(item("Insomnia · \(title)"))
        let battery = batteryState()
        if let b = battery { menu.addItem(item("Батарея \(b.percent)% · \(b.onBattery ? "от батареи" : "от сети")")) }
        remainingItem = item(remainingText)
        if startedLid { menu.addItem(remainingItem!) }
        if let notice = lastNotice, mode == .normal && !transitioning { menu.addItem(item(notice)) }
        menu.addItem(.separator())
        for (index, choice) in Mode.allCases.enumerated() {
            let i = item(choice.title, action: #selector(selectMode(_:)), tag: index)
            i.state = mode == choice && pendingMode == nil ? .on : .off
            i.isEnabled = !transitioning && !recoveryRequired && pendingMode == nil
            if choice == .server && battery?.onBattery != false { i.isEnabled = false }
            if choice == .server { i.toolTip = "С закрытой крышкой от сети. Bluetooth и внешний монитор не нужны." }
            if choice == .travel { i.toolTip = "С закрытой крышкой от батареи или сети, с приоритетом iPhone." }
            menu.addItem(i)
        }
        menu.addItem(.separator())
        let timer = NSMenuItem(title: startedLid ? "Таймер · \(remainingText.lowercased())" : "Таймер", action: nil, keyEquivalent: "")
        if startedLid { timer.submenu = timerChoices(for: mode) }
        else {
            let choices = newMenu()
            for context in [Mode.server, .travel] {
                let i = NSMenuItem(title: "\(context.title): \(durationLabel(duration(for: context)).lowercased())", action: nil, keyEquivalent: "")
                i.submenu = timerChoices(for: context); choices.addItem(i)
            }
            timer.submenu = choices
        }
        menu.addItem(timer)
        let connection = NSMenuItem(title: "Связь с iPhone", action: nil, keyEquivalent: "")
        let cm = newMenu()
        connectionTitleItem = item(connectionStatus.title); cm.addItem(connectionTitleItem!)
        connectionDetailItem = item(connectionStatus.detail)
        if !connectionStatus.detail.isEmpty { cm.addItem(connectionDetailItem!) }
        if let name = prefs.string(forKey: "hotspotSSID") { cm.addItem(item("Раздача: \(name)")) }
        cm.addItem(.separator())
        let check = item("Проверить сейчас", action: #selector(checkConnection)); check.isEnabled = travel.isEnabled; cm.addItem(check)
        let setup = item("Настроить раздачу…", action: #selector(configureHotspot)); setup.isEnabled = mode == .normal && guardian == nil && !travel.isRestoring; cm.addItem(setup)
        cm.addItem(item("Доступ к Wi‑Fi…", action: #selector(requestWiFiPermission)))
        cm.addItem(item("Показать журнал", action: #selector(showConnectionLog)))
        let forget = item("Забыть раздачу…", action: #selector(forgetHotspot))
        forget.isEnabled = mode == .normal && guardian == nil && !travel.isRestoring && prefs.string(forKey: "hotspotSSID") != nil
        cm.addItem(forget); connection.submenu = cm; menu.addItem(connection)
        let settings = NSMenuItem(title: "Настройки", action: nil, keyEquivalent: "")
        let sm = newMenu()
        let cutoffItem = NSMenuItem(title: "В пути: отключать при заряде ≤ \(cutoff)%", action: nil, keyEquivalent: "")
        let cutoffs = newMenu()
        for n in [15, 20, 30] {
            let i = item("\(n)%", action: #selector(setCutoff(_:)), tag: n)
            i.state = cutoff == n ? .on : .off; i.isEnabled = guardian == nil && !transitioning
            cutoffs.addItem(i)
        }
        cutoffItem.submenu = cutoffs; sm.addItem(cutoffItem)
        let login = item("Запускать при входе", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        sm.addItem(login)
        sm.addItem(item("Сервер выключается при отключении питания."))
        settings.submenu = sm; menu.addItem(settings)
        if recoveryRequired {
            let i = item("Восстановить обычный сон…", action: #selector(recover)); i.isEnabled = guardian == nil; menu.addItem(i)
        }
        menu.addItem(.separator())
        menu.addItem(item("О приложении…", action: #selector(about)))
        let quit = item("Завершить Insomnia", action: #selector(quitApp)); quit.keyEquivalent = "q"; menu.addItem(quit)
    }
    private func updateIcon() {
        guard status != nil else { return }
        var symbol = mode == .normal ? "moon.zzz" : (mode == .server ? "server.rack" : "figure.walk")
        if recoveryRequired { symbol = "exclamationmark.moon" }
        else if mode == .travel && connectionStatus.online == false { symbol = "wifi.exclamationmark" }
        status.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Insomnia: \(mode.title)")
        status.button?.image?.isTemplate = true
        status.button?.title = transitioning || pendingMode != nil ? "…" : ""
        status.button?.toolTip = "Insomnia · \(mode.title)\n\(remainingText)\n\(connectionStatus.title)"
        remainingItem?.title = remainingText
    }
    @objc private func selectMode(_ sender: NSMenuItem) { switchTo(Mode.allCases[sender.tag]) }
    @objc private func setCutoff(_ sender: NSMenuItem) { prefs.set(sender.tag, forKey: "cutoff") }
    @objc private func setDuration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let context = Mode(rawValue: raw) else { return }
        applyDuration(sender.tag, for: context)
    }
    @objc private func customDuration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let context = Mode(rawValue: raw) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "Таймер · \(context.title)"
        a.informativeText = "Число минут от 1 до 10080 (7 дней). Если режим уже работает, отсчёт начнётся заново."
        a.addButton(withTitle: "Применить"); a.addButton(withTitle: "Отмена")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        field.stringValue = "\(max(1, duration(for: context)))"; a.accessoryView = field; a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), (1...10080).contains(n) else {
            alert("Проверь длительность", "Введи целое число минут от 1 до 10080."); return
        }
        applyDuration(n, for: context)
    }
    private func applyDuration(_ minutes: Int, for context: Mode) {
        guard !transitioning, !recoveryRequired, pendingMode == nil else { return }
        prefs.set(minutes, forKey: "duration.\(context.rawValue)")
        if startedLid && mode == context {
            let value = deadlineAfter(minutes: minutes, now: Date().timeIntervalSince1970)
            deadline = value == 0 ? nil : Date(timeIntervalSince1970: value)
            do { try writeLease() } catch { emergencyStop("Не удалось обновить таймер") }
        }
        updateIcon()
    }
    private func switchTo(_ requested: Mode) {
        guard !transitioning, !recoveryRequired, pendingMode == nil, !quitting else { return }
        if requested == mode { return }
        if requested == .server && batteryState()?.onBattery != false {
            alert("Сервер работает от сети", "Подключи питание, затем включи этот режим."); return
        }
        if guardian != nil {
            nextMode = requested; transitioning = true
            if travel.isEnabled {
                waitingForWiFi = true
                travel.stop(restoreWiFi: true)
            } else { stopGuardian() }
            updateIcon()
        } else { startMode(requested) }
    }
    private func startMode(_ requested: Mode) {
        mode = .normal; deadline = nil; pendingCredentials = nil
        if requested == .normal { updateIcon(); return }
        guard let battery = batteryState() else { alert("Режим не включён", "Не удалось прочитать состояние питания."); return }
        if requested == .server && battery.onBattery { alert("Подключи питание", "Сервер работает только от сети."); return }
        if requested == .travel && battery.onBattery && battery.percent <= cutoff {
            alert("Низкий заряд", "Для режима «В пути» заряд должен быть выше \(cutoff)% или должно быть подключено питание."); return
        }
        if requested == .travel {
            if prefs.string(forKey: "hotspotSSID") == nil { guard editHotspot(showSavedNotice: false) else { return } }
            guard let name = prefs.string(forKey: "hotspotSSID") else { return }
            do { pendingCredentials = (name, try HotspotKeychain.load(ssid: name)) }
            catch { alert("Не удалось включить режим «В пути»", error.localizedDescription); return }
            if locationManager.authorizationStatus == .notDetermined { requestWiFiPermission() }
            refreshLocationPermission()
        }
        guard sleepDisabled() == false else {
            pendingCredentials = nil
            alert("Нельзя начать сеанс", "Системный запрет сна уже включён другим способом либо его состояние недоступно."); return
        }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Insomnia-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            heartbeatURL = folder.appendingPathComponent("lease.json")
            pendingMode = requested; lastNotice = nil
            sessionLog("UI requesting mode=\(requested.rawValue)")
            try writeLease()
            prefs.set(true, forKey: "lidSessionUnfinished"); prefs.synchronize()
            try launchAuthorized(["--session", "\(getpid())", heartbeatURL!.path, "\(cutoff)", requested.rawValue])
        } catch {
            cleanupHeartbeat(); pendingMode = nil; pendingCredentials = nil
            prefs.removeObject(forKey: "lidSessionUnfinished")
            alert("Не удалось начать сеанс", error.localizedDescription)
        }
        updateIcon()
    }
    private func writeLease() throws {
        guard let url = heartbeatURL else { return }
        let lease = SessionLease(heartbeat: Date().timeIntervalSince1970, deadline: deadline?.timeIntervalSince1970 ?? 0)
        try JSONEncoder().encode(lease).write(to: url, options: .atomic)
    }
    private func tick() {
        if heartbeatURL != nil && !stopping {
            do { try writeLease() } catch { emergencyStop("Контрольный сигнал недоступен"); return }
        }
        if guardian != nil, !stopping, !startedLid, let requested = pendingMode,
           let lease = heartbeatURL,
           FileManager.default.fileExists(atPath: lease.deletingLastPathComponent().appendingPathComponent("ready").path),
           sleepDisabled() == true {
            startedLid = true; mode = requested; pendingMode = nil
            let value = deadlineAfter(minutes: duration(for: requested), now: Date().timeIntervalSince1970)
            deadline = value == 0 ? nil : Date(timeIntervalSince1970: value)
            do { try writeLease() } catch { emergencyStop("Не удалось запустить таймер"); return }
            if requested == .travel, let (name, password) = pendingCredentials { travel.start(ssid: name, password: password) }
            pendingCredentials = nil
        }
        if startedLid && !transitioning {
            if let reason = sessionEnd(now: Date().timeIntervalSince1970, heartbeat: Date().timeIntervalSince1970,
                deadline: deadline?.timeIntervalSince1970 ?? 0, battery: batteryState(), threshold: cutoff, requiresAC: mode == .server) {
                lastNotice = notice(for: reason)
                switchTo(.normal)
            }
        }
        updateIcon()
    }
    private func notice(for reason: SessionEnd) -> String {
        switch reason {
        case .timerExpired: return "Таймер завершился · обычный режим"
        case .powerDisconnected: return "Питание отключено · сервер завершён"
        case .batteryLow: return "Низкий заряд · режим завершён"
        case .batteryUnavailable: return "Состояние питания недоступно · режим завершён"
        case .heartbeatLost: return "Контрольный сигнал потерян · режим завершён"
        case .sleepStateUnavailable: return "Не удалось проверить запрет сна · режим завершён"
        case .sleepProhibitionRemoved: return "Системный запрет сна был снят · режим завершён"
        case .activationFailed: return "Не удалось включить системный запрет сна"
        }
    }
    private func emergencyStop(_ message: String) {
        lastNotice = message; nextMode = .normal; transitioning = true; stopGuardian()
    }
    private func stopGuardian() {
        guard guardian != nil else { completeTransitionIfReady(); return }
        stopping = true; cleanupHeartbeat(); updateIcon()
    }
    private func cleanupHeartbeat() {
        if let url = heartbeatURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        heartbeatURL = nil
    }
    private func guardianEnded(code: Int32, output: String) {
        let wasStarted = startedLid
        let wasStopping = stopping
        sessionLog("UI helper ended started=\(wasStarted) stopping=\(wasStopping) code=\(code) output=\(output.prefix(600))")
        guardian = nil; startedLid = false; stopping = false; pendingMode = nil; pendingCredentials = nil
        cleanupHeartbeat(); deadline = nil; mode = .normal
        let currentSleepState = sleepDisabled()
        let restored = currentSleepState == false
        let untouched = output.contains("NOT_STARTED") && !wasStarted
        recoveryRequired = !restored && !untouched
        prefs.set(recoveryRequired, forKey: "lidSessionUnfinished")
        if let raw = output.components(separatedBy: "REASON ").last?.trimmingCharacters(in: .whitespacesAndNewlines),
           let reason = SessionEnd(rawValue: raw) { lastNotice = notice(for: reason) }
        if recoveryRequired {
            nextMode = nil
            if quitting { NSApp.reply(toApplicationShouldTerminate: false); quitting = false }
            alert("Восстановление сна не подтверждено", "Используй пункт «Восстановить обычный сон…».\n\n\(output.prefix(500))")
        } else if code != 0 && !quitting && !wasStopping {
            nextMode = .normal
            if output.contains("-128") { lastNotice = "Запуск отменён" }
            else if wasStarted {
                alert("Режим завершён", "Сеанс прервался. Обычный сон восстановлен.\n\n\(lastNotice ?? "Причина записана в системный журнал.")")
            } else { alert("Режим не включён", "Не удалось начать сеанс. Проверь питание и отсутствие других утилит запрета сна.\n\n\(output.prefix(500))") }
        }
        transitioning = true
        if travel.isEnabled && !quitting {
            waitingForWiFi = true
            travel.stop(restoreWiFi: true)
        }
        updateIcon(); completeTransitionIfReady()
    }
    private func completeTransitionIfReady() {
        guard guardian == nil, !waitingForWiFi else { return }
        if quitting { NSApp.reply(toApplicationShouldTerminate: true); return }
        guard transitioning else { return }
        transitioning = false
        let requested = recoveryRequired ? Mode.normal : (nextMode ?? .normal)
        nextMode = nil
        startMode(requested)
    }
    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func appleQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    private func launchAuthorized(_ args: [String]) throws {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "InsomniaGuardian") else { throw HotspotError("Не найден процесс восстановления в пакете приложения.") }
        let command = ([helper.path] + args).map(shellQuote).joined(separator: " ")
        let script = "with timeout of 2147483647 seconds\ndo shell script \(appleQuote(command)) with administrator privileges\nend timeout"
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); process.arguments = ["-e", script]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        process.terminationHandler = { [weak self] p in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async { self?.guardianEnded(code: p.terminationStatus, output: output) }
        }
        try process.run(); guardian = process
    }
    @objc private func recover() {
        guard guardian == nil else { return }
        let a = NSAlert(); a.messageText = "Восстановить обычный сон?"
        a.informativeText = "Будет снят глобальный запрет сна после предыдущего сеанса. Если после него запрет включала другая программа, её настройка также будет снята."
        a.addButton(withTitle: "Восстановить"); a.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { transitioning = true; stopping = true; try launchAuthorized(["--restore"]); updateIcon() }
        catch { transitioning = false; stopping = false; alert("Не удалось восстановить сон", error.localizedDescription) }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { alert("Автозапуск недоступен", "Перемести приложение в «Программы» и повтори попытку.\n\n\(error.localizedDescription)") }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshLocationPermission()
    }

    private func refreshLocationPermission() {
        let a = locationManager.authorizationStatus
        travel.setWiFiAuthorized(a == .authorizedAlways)
    }

    @objc private func requestWiFiPermission() {
        NSApp.activate(ignoringOtherApps: true)
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            alert("Нужен доступ к Wi‑Fi", "macOS требует разрешение геолокации, чтобы Insomnia видела имя текущей сети и могла подключаться к раздаче. Координаты приложение не запрашивает. Разреши Insomnia доступ в «Конфиденциальность и безопасность → Службы геолокации». USB и проверка интернета работают и без этого разрешения.")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        default:
            alert("Доступ к Wi‑Fi разрешён", "Insomnia может определять имя сети и искать выбранную раздачу. Координаты приложение не получает.")
        }
    }

    @objc private func configureHotspot() { _ = editHotspot() }
    private func editHotspot(showSavedNotice: Bool = true) -> Bool {
        guard mode == .normal, guardian == nil, !travel.isRestoring else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Раздача iPhone"
        a.informativeText = "На iPhone открой «Режим модема» и включи «Разрешать другим». Укажи точное имя сети и пароль. Пароль сохраняется только в Связке ключей.\n\nВ режиме «В пути» Insomnia переходит на эту раздачу даже с рабочего домашнего Wi‑Fi. Рабочий проводной маршрут, включая USB, сохраняет. Если раздача не видна, текущая сеть остаётся подключённой."
        a.addButton(withTitle: "Сохранить")
        a.addButton(withTitle: "Отмена")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 126))
        let nameLabel = NSTextField(labelWithString: "Имя сети iPhone (SSID)")
        nameLabel.frame = NSRect(x: 0, y: 104, width: 340, height: 18)
        let name = NSTextField(frame: NSRect(x: 0, y: 74, width: 340, height: 26))
        name.stringValue = prefs.string(forKey: "hotspotSSID") ?? ""
        name.placeholderString = "Точное имя раздачи в меню Wi‑Fi"
        let passwordLabel = NSTextField(labelWithString: "Пароль раздачи")
        passwordLabel.frame = NSRect(x: 0, y: 47, width: 340, height: 18)
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 16, width: 340, height: 26))
        password.placeholderString = "Пусто — использовать сохранённый пароль"
        for field in [nameLabel, name, passwordLabel, password] { view.addSubview(field) }
        a.accessoryView = view
        a.window.initialFirstResponder = name
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        let ssid = name.stringValue
        guard (1...32).contains(ssid.utf8.count), !ssid.contains("\n"), !ssid.contains("\0") else {
            alert("Проверь имя сети", "Имя должно совпадать с раздачей iPhone и занимать от 1 до 32 байт UTF‑8.")
            return false
        }
        do {
            if !password.stringValue.isEmpty {
                let value = password.stringValue
                guard (8...63).contains(value.utf8.count), value.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) else {
                    throw HotspotError("Пароль раздачи должен содержать 8–63 символа ASCII. Скопируй его из настроек iPhone.")
                }
                try HotspotKeychain.save(value, ssid: ssid)
            } else { _ = try HotspotKeychain.load(ssid: ssid) }
            if let old = prefs.string(forKey: "hotspotSSID"), old != ssid { try? HotspotKeychain.forget(ssid: old) }
            prefs.set(ssid, forKey: "hotspotSSID")
            if showSavedNotice { alert("Раздача сохранена", "Выбери режим «В пути» в главном меню. Связь с iPhone и запрет сна включатся вместе.") }
            return true
        } catch { alert("Настройки не сохранены", error.localizedDescription); return false }
    }

    @objc private func forgetHotspot() {
        guard mode == .normal, guardian == nil, !travel.isRestoring, let ssid = prefs.string(forKey: "hotspotSSID") else { return }
        do { try HotspotKeychain.forget(ssid: ssid); prefs.removeObject(forKey: "hotspotSSID") }
        catch { alert("Не удалось забыть раздачу", error.localizedDescription) }
    }

    @objc private func checkConnection() { travel.checkNow() }

    @objc private func showConnectionLog() {
        let url = HotspotController.logURL
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { alert("Журнал пока пуст", "Записи появятся после первого включения режима «В пути».") }
    }

    @objc private func about() {
        alert("Insomnia 0.6.2", "Обычный — системные правила сна.\n\nСервер — работа с закрытой крышкой только от сети, без внешнего монитора или Bluetooth-устройств. Отключение питания завершает режим.\n\nВ пути — работа от батареи или сети с приоритетом iPhone. При выходе приложение пытается вернуть обычный Wi‑Fi.\n\nУ каждого активного режима свой таймер. Изменение длительности запускает отсчёт заново. Для запрета сна требуется системное разрешение администратора. При аварийном выключении может понадобиться восстановление сна из меню. Используй Mac с закрытой крышкой на поверхности с вентиляцией.")
    }
    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true; nextMode = nil; waitingForWiFi = false
        travel.stop()
        if guardian != nil {
            transitioning = true; stopGuardian()
            return .terminateLater
        }
        return .terminateNow
    }
}
