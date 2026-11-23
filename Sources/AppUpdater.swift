import AppKit

@MainActor
final class AppUpdater: NSObject, NSWindowDelegate {
    private let sourceKey = "KeycapCaperUpdateChannel"
    private let officialChannel = URL(string: "https://github.com/xiixiixixi/Keycap-Caper/releases/latest/download/latest.json")!
    private let status = NSTextField(labelWithString: "")
    private let notes = NSTextView()
    private let progress = NSProgressIndicator()
    private let source = NSButton(title: "", target: nil, action: nil)
    private let primary = NSButton(title: "", target: nil, action: nil)
    private var window: NSWindow?
    private var release: CaperRelease?
    private var busy = false
    private var installing = false
    private var checkedChannel: URL?

    private var build: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }

    private var channel: URL {
        let selection = UserDefaults.standard.string(forKey: sourceKey)
        if selection == "local" { return CaperRelease.localChannel }
        if let selection, let url = CaperRelease.remoteURL(selection) { return url }
        return officialChannel
    }

    func show() {
        if window == nil { makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        guard !busy, release == nil else { return }
        let receipt = CaperRelease.localChannel.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("last-error.txt")
        if let message = try? String(contentsOf: receipt, encoding: .utf8) {
            try? FileManager.default.removeItem(at: receipt)
            display(title: "上次安装未完成", detail: message, action: "重新检查")
        } else { check() }
    }

    private func makeWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 315),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window = w
        w.isReleasedWhenClosed = false
        w.title = "应用更新"
        w.delegate = self
        w.center()
        guard let content = w.contentView else { return }

        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 62).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 62).isActive = true
        let heading = NSTextField(labelWithString: "键帽大盗")
        heading.font = .systemFont(ofSize: 24, weight: .bold)
        let installed = NSTextField(labelWithString: "已安装 " + version + "（构建 " + String(build) + "）")
        installed.font = .systemFont(ofSize: 13)
        installed.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [heading, installed])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 3
        let header = NSStackView(views: [icon, titles])
        header.spacing = 12

        status.font = .systemFont(ofSize: 17, weight: .semibold)
        status.setAccessibilityIdentifier("update-status")
        status.lineBreakMode = .byTruncatingTail
        notes.isEditable = false
        notes.isSelectable = true
        notes.isRichText = false
        notes.drawsBackground = false
        notes.textContainerInset = .zero
        notes.textContainer?.lineFragmentPadding = 0
        notes.textContainer?.widthTracksTextView = true
        notes.isHorizontallyResizable = false
        notes.isVerticallyResizable = true
        notes.autoresizingMask = [.width]
        notes.font = .systemFont(ofSize: 13)
        notes.textColor = .secondaryLabelColor
        notes.setAccessibilityLabel("版本说明")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = notes
        scroll.borderType = .noBorder

        progress.style = .bar
        progress.controlSize = .small
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
        source.target = self
        source.action = #selector(editChannel)
        source.bezelStyle = .inline
        source.setAccessibilityIdentifier("update-source")
        primary.target = self
        primary.action = #selector(performAction)
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        primary.setAccessibilityIdentifier("update-primary")
        for view in [header, status, scroll, progress, source, primary] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            status.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 9),
            scroll.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -10),
            progress.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: primary.topAnchor, constant: -14),
            source.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            source.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
            source.trailingAnchor.constraint(lessThanOrEqualTo: primary.leadingAnchor, constant: -12),
            primary.trailingAnchor.constraint(equalTo: status.trailingAnchor),
            primary.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -19)
        ])
        refreshSourceLabel()
    }

    private func refreshSourceLabel() {
        if channel == officialChannel { source.title = "更新源 · 官方发布页…" }
        else { source.title = channel.isFileURL ? "更新源 · 本机发布目录…" : "更新源 · 自定义网址…" }
        source.toolTip = channel.isFileURL ? channel.deletingLastPathComponent().path : channel.absoluteString
    }

    private func display(title: String, detail: String, action: String) {
        status.stringValue = title
        notes.string = detail
        notes.scrollToBeginningOfDocument(nil)
        primary.title = action
        primary.isEnabled = !busy
        source.isEnabled = !busy
        window?.standardWindowButton(.closeButton)?.isEnabled = !installing
        progress.isHidden = !busy
        if busy && progress.isIndeterminate { progress.startAnimation(nil) }
        if !busy { progress.stopAnimation(nil) }
    }

    @objc private func performAction() {
        guard !busy else { return }
        if let release, let checkedChannel { install(release, from: checkedChannel) }
        else { check() }
    }

    private func check() {
        guard !busy else { return }
        busy = true
        release = nil
        checkedChannel = nil
        progress.isIndeterminate = true
        let address = channel
        refreshSourceLabel()
        display(title: "正在检查更新…", detail: "正在读取发布说明并验证签名。", action: "检查中")
        Task { [self] in
            do {
                let latest = try await CaperUpdateFiles.check(channel: address)
                busy = false
                if latest.build > build {
                    release = latest
                    checkedChannel = address
                    display(title: "发现新版本 " + latest.version, detail: latest.notes, action: "安装并重新打开")
                } else {
                    display(title: latest.build == build ? "已是最新版本" : "已安装更新的版本",
                            detail: latest.build == build ? latest.notes : "更新源中的版本是 " + latest.version + "。", action: "重新检查")
                }
            } catch {
                busy = false
                display(title: "暂时无法检查更新", detail: error.localizedDescription, action: "重新检查")
            }
        }
    }

    private func install(_ version: CaperRelease, from address: URL) {
        busy = true
        installing = true
        progress.isIndeterminate = true
        display(title: "准备更新至 " + version.version, detail: "正在取得并校验更新包。完成后应用会重新打开。", action: "正在安装")
        Task { [self] in
            do {
                let stage = try await CaperUpdateFiles.stage(version, channel: address) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.installing else { return }
                        self.progress.isIndeterminate = false
                        self.progress.doubleValue = fraction
                    }
                }
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CaperUpdateInstaller")
                let process = Process()
                process.executableURL = helper
                process.arguments = [stage.path, String(ProcessInfo.processInfo.processIdentifier), String(build), String(version.build)]
                do { try process.run() }
                catch { try? FileManager.default.removeItem(at: stage); throw error }
                NSApplication.shared.terminate(nil)
            } catch {
                busy = false
                installing = false
                release = nil
                checkedChannel = nil
                display(title: "更新未安装", detail: error.localizedDescription, action: "重新检查")
            }
        }
    }

    @objc private func editChannel() {
        guard !busy, let window else { return }
        let alert = NSAlert()
        alert.messageText = "选择更新来源"
        alert.informativeText = "留空使用键帽大盗的官方发布页，也可以指定其他更新清单或使用本机目录。"
        let address = NSTextField(string: channel == officialChannel || channel.isFileURL ? "" : channel.absoluteString)
        address.placeholderString = "https://…/latest.json"
        address.frame = NSRect(x: 0, y: 0, width: 330, height: 25)
        address.setAccessibilityLabel("网络更新清单网址")
        alert.accessoryView = address
        alert.addButton(withTitle: "保存并检查")
        alert.addButton(withTitle: "使用本机目录")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = address
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            let text = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertSecondButtonReturn {
                UserDefaults.standard.set("local", forKey: self.sourceKey)
            } else if text.isEmpty {
                UserDefaults.standard.removeObject(forKey: self.sourceKey)
            } else if let url = CaperRelease.remoteURL(text) {
                UserDefaults.standard.set(url.absoluteString, forKey: self.sourceKey)
            } else {
                self.release = nil
                self.checkedChannel = nil
                self.display(title: "更新地址无效", detail: "请使用以 https:// 开头、指向更新清单的完整网址。", action: "重新检查")
                return
            }
            self.check()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !installing }
    func windowWillClose(_ notification: Notification) { release = nil; checkedChannel = nil }
}
