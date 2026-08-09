import AppKit
import CodexStatusCore
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusHeaderItem: NSMenuItem!
    private var taskPreviewItem: NSMenuItem!
    private var detailItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var notificationsItem: NSMenuItem!
    private var notificationStatusItem: NSMenuItem!
    private var timer: Timer?
    private var currentSnapshot = TaskStatusSnapshot.idle
    private var currentLabel = "空闲"
    private var currentTint: NSColor = .secondaryLabelColor
    private var currentDotAlpha: CGFloat = 1.0
    private var pulseTimer: Timer?
    private var pulseStart: Date?

    private let monitor = SessionLogWatcher(
        sessionsDirectory: URL(fileURLWithPath: NSHomeDirectory() + "/.codex/sessions"),
        staleAfter: Settings.staleAfter,
        idleWindow: Settings.idleWindow
    )
    private let notifier = Notifier()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        monitor.onUpdate = { [weak self] snapshot in
            Task { @MainActor in
                self?.currentSnapshot = snapshot
                self?.refreshMenu()
            }
        }
        monitor.onTaskEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTaskEvent(event)
            }
        }

        monitor.startWatching()
        monitor.poll()
        notifier.activate()
        refreshMenu()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    // MARK: - Timer

    private func tick() {
        monitor.poll(pollInterval: Settings.pollInterval)
        refreshMenu()
    }

    // MARK: - Status UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.font = NSFont.menuBarFont(ofSize: 13)
            button.image = makeDotImage(diameter: 13, color: .secondaryLabelColor, alpha: 1.0)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.attributedTitle = labelAttributedTitle("空闲")
        }

        let menu = NSMenu()
        statusHeaderItem = NSMenuItem(title: "Codex 状态：空闲", action: nil, keyEquivalent: "")
        statusHeaderItem.isEnabled = false
        taskPreviewItem = NSMenuItem(title: "任务：暂无", action: nil, keyEquivalent: "")
        taskPreviewItem.isEnabled = false
        detailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        detailItem.isHidden = true
        menu.addItem(statusHeaderItem)
        menu.addItem(taskPreviewItem)
        menu.addItem(detailItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o"))

        launchAtLoginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        menu.addItem(launchAtLoginItem)

        notificationsItem = NSMenuItem(title: "完成/中断时通知", action: #selector(toggleNotifications), keyEquivalent: "")
        menu.addItem(notificationsItem)
        notificationStatusItem = NSMenuItem(title: "通知权限：查询中…", action: nil, keyEquivalent: "")
        notificationStatusItem.isEnabled = false
        menu.addItem(notificationStatusItem)
        menu.addItem(NSMenuItem(title: "测试通知", action: #selector(testNotification), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开通知设置…", action: #selector(openNotificationSettings), keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        menu.delegate = self
    }

    private func refreshMenu() {
        let snapshot = currentSnapshot
        let label: String
        let tint: NSColor
        switch snapshot.kind {
        case .idle:
            label = "空闲"
            tint = .secondaryLabelColor
        case .working:
            label = "思考中"
            tint = .systemBlue
        case .stalled:
            label = "无活动"
            tint = .systemOrange
        case .completed:
            label = "完成"
            tint = .systemGreen
        case .interrupted:
            label = "中断"
            tint = .systemRed
        }
        statusHeaderItem.title = "Codex 状态：\(label)"
        currentLabel = label
        currentTint = tint
        if snapshot.kind == .working {
            startPulse()
        } else {
            stopPulse()
        }
        applyAppearance()

        let preview = snapshot.preview?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "暂无任务"
        taskPreviewItem.title = "任务：\(truncate(preview, 60))"

        switch snapshot.kind {
        case .working, .stalled:
            if let started = snapshot.startedAt {
                detailItem.title = "已进行 \(formatDuration(Date().timeIntervalSince(started)))"
            } else {
                detailItem.title = ""
            }
            detailItem.isHidden = detailItem.title.isEmpty
        case .completed:
            var parts: [String] = []
            if let ms = snapshot.durationMs {
                parts.append("耗时 \(formatDuration(TimeInterval(ms) / 1000))")
            }
            if let message = snapshot.detail, !message.isEmpty {
                parts.append(truncate(message, 80))
            }
            detailItem.title = parts.joined(separator: " · ")
            detailItem.isHidden = parts.isEmpty
        case .interrupted:
            var parts: [String] = []
            if let ms = snapshot.durationMs {
                parts.append("耗时 \(formatDuration(TimeInterval(ms) / 1000))")
            }
            if let reason = snapshot.detail, !reason.isEmpty {
                parts.append(reason == "interrupted" ? "手动中断" : "原因：\(reason)")
            }
            detailItem.title = parts.joined(separator: " · ")
            detailItem.isHidden = parts.isEmpty
        case .idle:
            detailItem.title = ""
            detailItem.isHidden = true
        }

        launchAtLoginItem.state = launchAtLogin ? .on : .off
        notificationsItem.state = Settings.notificationsEnabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        StatusLog.write("menu opened")
        refreshNotificationStatus()
    }

    // MARK: - Events

    private func handleTaskEvent(_ event: TaskEvent) {
        guard Settings.notificationsEnabled else { return }
        switch event.kind {
        case .completed:
            notifier.send(
                title: "Codex 任务已完成",
                body: notificationBody(for: event, fallback: "任务已完成")
            )
        case .interrupted:
            notifier.send(
                title: "Codex 任务已中断",
                body: notificationBody(for: event, fallback: "任务被中断")
            )
        case .started:
            break
        }
    }

    private func notificationBody(for event: TaskEvent, fallback: String) -> String {
        if let detail = event.detail, !detail.isEmpty {
            return truncate(detail, 100)
        }
        if let preview = event.preview, !preview.isEmpty {
            return truncate(preview, 100)
        }
        return fallback
    }

    // MARK: - Menu actions

    @objc private func openCodex() {
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSSound.beep()
            statusHeaderItem.title = "未找到 Codex 应用（ChatGPT.app）"
        }
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAtLogin {
            try? SMAppService.mainApp.unregister()
            launchAtLogin = false
        } else {
            do {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            } catch {
                NSSound.beep()
                statusHeaderItem.title = "无法设置登录时启动，请将 App 放入 /Applications 或 ~/Applications"
            }
        }
        refreshMenu()
    }

    @objc private func toggleNotifications() {
        Settings.notificationsEnabled.toggle()
        refreshMenu()
    }

    @objc private func testNotification() {
        StatusLog.write("test notification clicked")
        notifier.send(title: "CodexStatus 测试", body: "通知功能正常 ✅")
    }

    @objc private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private var launchAtLogin: Bool {
        get { UserDefaults.standard.object(forKey: Settings.launchAtLoginKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Settings.launchAtLoginKey) }
    }

    // MARK: - Helpers

    private func truncate(_ string: String, _ maxCount: Int) -> String {
        if string.count <= maxCount { return string }
        return String(string.prefix(maxCount - 1)) + "…"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// The status label rendered with the neutral label color, so
    /// `contentTintColor` only affects the dot image.
    private func labelAttributedTitle(_ label: String) -> NSAttributedString {
        NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    /// A filled circle used as the menu bar status "light", painted directly
    /// with the status color (template + contentTintColor does not reliably
    /// tint plain bitmap images on the status bar).
    private func makeDotImage(diameter: CGFloat, color: NSColor, alpha: CGFloat) -> NSImage? {
        let side = Int(ceil(diameter))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        let inset = diameter * 0.08
        let rect = CGRect(x: inset, y: inset, width: diameter - inset * 2, height: diameter - inset * 2)
        context.cgContext.setFillColor(color.withAlphaComponent(alpha).cgColor)
        context.cgContext.fillEllipse(in: rect)
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.addRepresentation(rep)
        return image
    }

    private func applyAppearance() {
        guard let button = statusItem?.button else { return }
        button.attributedTitle = labelAttributedTitle(currentLabel)
        button.image = makeDotImage(diameter: 13, color: currentTint, alpha: currentDotAlpha)
    }

    // MARK: - Breathing dot

    private func startPulse() {
        guard pulseTimer == nil else { return }
        pulseStart = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePulse()
            }
        }
        pulseTimer = timer
    }

    private func stopPulse() {
        guard pulseTimer != nil else { return }
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseStart = nil
        currentDotAlpha = 1.0
    }

    private func updatePulse() {
        guard let start = pulseStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        // Gentle breathing over a ~1.4 s cycle, alpha 1.0 -> 0.35 -> 1.0.
        let phase = (elapsed / 1.4) * 2 * .pi
        currentDotAlpha = 0.35 + 0.65 * (0.5 + 0.5 * cos(phase))
        applyAppearance()
    }

    private func refreshNotificationStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await notifier.authorizationStatus()
            let label: String
            switch status {
            case .authorized: label = "已允许"
            case .provisional: label = "已允许（临时）"
            case .denied: label = "系统未授权（已启用兼容通知）"
            case .notDetermined: label = "未确定（将使用兼容通知）"
            default: label = "未知"
            }
            notificationStatusItem.title = "通知权限：\(label)"
        }
    }
}
