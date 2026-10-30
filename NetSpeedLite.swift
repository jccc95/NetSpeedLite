import AppKit
import Darwin

private struct SpeedSample {
    let download: Double
    let upload: Double
}

private enum LaunchAgentManager {
    private static let label = "local.codex.netspeedlite"
    private static let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool, appURL: URL) throws {
        if enabled {
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let configuration: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", appURL.path],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: configuration,
                format: .xml,
                options: 0
            )
            try data.write(to: launchAgentURL, options: .atomic)
            try runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
        } else {
            try? runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path])
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
        }
    }

    private static func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "NetSpeedLite.LaunchAgent",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "launchctl failed"]
            )
        }
    }
}

private final class StatusBarView: NSView {
    var onClick: (() -> Void)?
    var downloadText = "↓  0B/s"
    var uploadText = "↑  0B/s"

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let lineHeight: CGFloat = 10
        (downloadText as NSString).draw(
            in: NSRect(x: 3, y: 0, width: bounds.width - 3, height: lineHeight),
            withAttributes: attributes
        )
        (uploadText as NSString).draw(
            in: NSRect(x: 3, y: 11, width: bounds.width - 3, height: lineHeight),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

private final class SpeedChartView: NSView {
    var samples: [SpeedSample] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let chart = bounds.insetBy(dx: 1, dy: 2)
        NSColor.separatorColor.setStroke()
        let grid = NSBezierPath()
        for step in 0...3 {
            let y = chart.minY + chart.height * CGFloat(step) / 3
            grid.move(to: NSPoint(x: chart.minX, y: y))
            grid.line(to: NSPoint(x: chart.maxX, y: y))
        }
        grid.lineWidth = 0.5
        grid.stroke()

        let peak = max(1, samples.map { max($0.download, $0.upload) }.max() ?? 0)
        drawLine(for: \.download, peak: peak, color: .systemBlue, in: chart)
        drawLine(for: \.upload, peak: peak, color: .systemOrange, in: chart)
    }

    private func drawLine(
        for keyPath: KeyPath<SpeedSample, Double>,
        peak: Double,
        color: NSColor,
        in chart: NSRect
    ) {
        guard !samples.isEmpty else { return }
        let path = NSBezierPath()
        for (index, sample) in samples.enumerated() {
            let secondsAgo = samples.count - 1 - index
            let x = chart.maxX - chart.width * CGFloat(secondsAgo) / 59
            let value = sample[keyPath: keyPath]
            let y = chart.minY + chart.height * CGFloat(value / peak)
            let point = NSPoint(x: x, y: min(chart.maxY, max(chart.minY, y)))
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        color.setStroke()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}

private final class PopoverViewController: NSViewController {
    var onStartupChange: ((Bool) -> Bool)?
    var onQuit: (() -> Void)?

    private let chart = SpeedChartView()
    private let downloadLabel = NSTextField(labelWithString: "↓ 下载 0B/s")
    private let uploadLabel = NSTextField(labelWithString: "↑ 上传 0B/s")
    private let startupButton = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let heading = NSTextField(labelWithString: "实时网速")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let period = NSTextField(labelWithString: "最近 60 秒")
        period.font = .systemFont(ofSize: 11)
        period.textColor = .secondaryLabelColor

        let headingRow = NSStackView(views: [heading, period])
        headingRow.orientation = .horizontal
        headingRow.distribution = .equalSpacing

        downloadLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        downloadLabel.textColor = .systemBlue
        uploadLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        uploadLabel.textColor = .systemOrange
        let ratesRow = NSStackView(views: [downloadLabel, uploadLabel])
        ratesRow.orientation = .horizontal
        ratesRow.distribution = .fillEqually
        ratesRow.spacing = 8

        chart.translatesAutoresizingMaskIntoConstraints = false
        chart.heightAnchor.constraint(equalToConstant: 128).isActive = true
        startupButton.target = self
        startupButton.action = #selector(toggleStartup(_:))
        startupButton.state = LaunchAgentManager.isEnabled ? .on : .off

        let quitButton = NSButton(title: "退出 NetSpeedLite", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        let footer = NSStackView(views: [startupButton, quitButton])
        footer.orientation = .horizontal
        footer.distribution = .equalSpacing

        let stack = NSStackView(views: [headingRow, ratesRow, chart, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -14),
            headingRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ratesRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            chart.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        view = rootView
    }

    func update(samples: [SpeedSample], download: String, upload: String) {
        loadViewIfNeeded()
        chart.samples = samples
        downloadLabel.stringValue = "↓ 下载 \(download)/s"
        uploadLabel.stringValue = "↑ 上传 \(upload)/s"
    }

    @objc private func toggleStartup(_ sender: NSButton) {
        let enabled = sender.state == .on
        guard onStartupChange?(enabled) == true else {
            sender.state = enabled ? .off : .on
            return
        }
    }

    @objc private func quitApp() {
        onQuit?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusBarView!
    private var popover: NSPopover!
    private var popoverController: PopoverViewController!
    private var timer: Timer?
    private var previous: (received: UInt64, sent: UInt64, time: TimeInterval)?
    private var samples: [SpeedSample] = []
    private var uploadRate: Double = 0
    private var downloadRate: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 58)
        statusView = StatusBarView(frame: NSRect(x: 0, y: 0, width: 58, height: 22))
        statusView.onClick = { [weak self] in self?.togglePopover() }
        statusItem.view = statusView

        popoverController = PopoverViewController()
        popoverController.onStartupChange = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled) ?? false
        }
        popoverController.onQuit = { NSApp.terminate(nil) }
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 240)
        popover.contentViewController = popoverController

        enableStartupOnFirstRun()
        sampleNetwork()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.sampleNetwork()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func togglePopover() {
        guard let statusView else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
        }
    }

    private func enableStartupOnFirstRun() {
        let preferences = UserDefaults(suiteName: "local.codex.netspeedlite")!
        let configurationKey = "launchAtLoginConfigured"
        guard preferences.object(forKey: configurationKey) == nil else { return }
        if setLaunchAtLogin(true) {
            preferences.set(true, forKey: configurationKey)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            try LaunchAgentManager.setEnabled(enabled, appURL: appBundleURL())
            UserDefaults(suiteName: "local.codex.netspeedlite")?
                .set(true, forKey: "launchAtLoginConfigured")
            return true
        } catch {
            NSLog("NetSpeedLite: couldn't update login startup: %@", error.localizedDescription)
            return false
        }
    }

    private func appBundleURL() -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sampleNetwork() {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let address = cursor {
            defer { cursor = address.pointee.ifa_next }
            guard let data = address.pointee.ifa_data,
                  let name = address.pointee.ifa_name,
                  String(cString: name) != "lo0",
                  let family = address.pointee.ifa_addr?.pointee.sa_family,
                  family == UInt8(AF_LINK) else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received &+= UInt64(stats.ifi_ibytes)
            sent &+= UInt64(stats.ifi_obytes)
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let previous, now > previous.time,
           received >= previous.received, sent >= previous.sent {
            let elapsed = now - previous.time
            downloadRate = Double(received - previous.received) / elapsed
            uploadRate = Double(sent - previous.sent) / elapsed
        } else {
            downloadRate = 0
            uploadRate = 0
        }
        previous = (received, sent, now)
        samples.append(SpeedSample(download: downloadRate, upload: uploadRate))
        if samples.count > 60 { samples.removeFirst(samples.count - 60) }

        let download = format(downloadRate)
        let upload = format(uploadRate)
        updateStatusDisplay(download: download, upload: upload)
        popoverController.update(samples: samples, download: download, upload: upload)
    }

    private func updateStatusDisplay(download: String, upload: String) {
        let valueWidth = max(download.count, upload.count)
        let alignedDownload = String(repeating: " ", count: valueWidth - download.count) + download
        let alignedUpload = String(repeating: " ", count: valueWidth - upload.count) + upload
        statusView.downloadText = "↓  \(alignedDownload)/s"
        statusView.uploadText = "↑  \(alignedUpload)/s"
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = max(
            (statusView.downloadText as NSString).size(withAttributes: attributes).width,
            (statusView.uploadText as NSString).size(withAttributes: attributes).width
        )
        let width = max(58, ceil(textWidth) + 8)
        statusItem.length = width
        statusView.setFrameSize(NSSize(width: width, height: 22))
        statusView.needsDisplay = true
    }

    private func format(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1fMB", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.0fKB", bytesPerSecond / 1_000)
        }
        return String(format: "%.0fB", bytesPerSecond)
    }
}

private func acquireSingletonLock() -> Int32 {
    let path = "/tmp/local.codex.netspeedlite.\(getuid()).lock"
    let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { return -1 }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
        Darwin.close(descriptor)
        return -1
    }
    return descriptor
}

private let singletonLockDescriptor = acquireSingletonLock()
if singletonLockDescriptor >= 0 {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
