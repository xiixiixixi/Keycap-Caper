import AppKit

enum InputGuideState {
    case needsPermission, waitingForListener, listening, petHidden

    var showsSetupSteps: Bool {
        self == .needsPermission || self == .waitingForListener
    }
}

/// A native file drag. NSURL publishes public.file-url (including the .app suffix).
final class DraggableApplicationCard: NSView, NSDraggingSource {
    let applicationURL: URL
    private let icon: NSImage
    private let outline = CAShapeLayer()

    init(applicationURL: URL) {
        self.applicationURL = applicationURL
        icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(outline)
        let image = NSImageView(image: icon)
        image.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: "Keycap Caper（键帽大盗）")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let hint = NSTextField(labelWithString: "按住这里，拖到系统的应用列表")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, hint])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let grip = NSImageView(image: NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil) ?? NSImage())
        grip.contentTintColor = .secondaryLabelColor
        for view in [image, labels, grip] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 70),
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 49), image.heightAnchor.constraint(equalTo: image.widthAnchor),
            labels.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 9),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: grip.leadingAnchor, constant: -4),
            grip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            grip.centerYAnchor.constraint(equalTo: centerYAnchor), grip.widthAnchor.constraint(equalToConstant: 16)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("拖动键帽大盗应用到系统输入监控列表，也可使用下方的在访达中显示按钮")
        toolTip = applicationURL.path
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 10, cornerHeight: 10, transform: nil)
        outline.path = path
        outline.lineWidth = 1.4
        outline.lineDashPattern = [5, 4]
        effectiveAppearance.performAsCurrentDrawingAppearance {
            outline.strokeColor = NSColor.systemTeal.withAlphaComponent(0.7).cgColor
            outline.fillColor = NSColor.systemTeal.withAlphaComponent(0.075).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
    func makeDraggingItem(at point: NSPoint) -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
        item.setDraggingFrame(NSRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44), contents: icon)
        return item
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let session = beginDraggingSession(with: [makeDraggingItem(at: point)], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}

final class PermissionGuide: NSWindowController, NSWindowDelegate {
    private let readState: () -> InputGuideState
    private let applicationURL = Bundle.main.bundleURL
    private let status = NSTextField(labelWithString: "")
    private let headline = NSTextField(labelWithString: "")
    private let explanation = NSTextField(wrappingLabelWithString: "")
    private let steps = NSStackView()
    private let closeButton = NSButton(title: "稍后", target: nil, action: nil)
    private let restartButton = NSButton(title: "重新打开应用", target: nil, action: nil)
    private let troubleButton = NSButton(title: "开关已开？修复旧授权", target: nil, action: nil)
    private let settingsButton = NSButton(title: "打开输入监控设置", target: nil, action: nil)
    private var timer: Timer?
    private var currentState: InputGuideState?

    init(state: @escaping () -> InputGuideState) {
        readState = state
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 436, height: 450),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "键帽大盗 · 输入监控"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        buildContent(in: window)
    }
    required init?(coder: NSCoder) { nil }

    func present(activate: Bool = true) {
        guard let window else { return }
        refresh()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        if timer == nil {
            let poll = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.main.add(poll, forMode: .common)
            timer = poll
        }
    }
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        window?.level = .normal
    }

    private func buildContent(in window: NSWindow) {
        guard let content = window.contentView else { return }
        let mark = NSImageView(image: NSWorkspace.shared.icon(forFile: applicationURL.path))
        mark.imageScaling = .scaleProportionallyUpOrDown
        let top = NSStackView(views: [mark, status])
        top.alignment = .centerY
        top.spacing = 7
        status.font = .systemFont(ofSize: 12, weight: .semibold)
        mark.widthAnchor.constraint(equalToConstant: 32).isActive = true
        mark.heightAnchor.constraint(equalTo: mark.widthAnchor).isActive = true

        headline.font = .systemFont(ofSize: 26, weight: .bold)
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor

        let layout = NSStackView()
        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 8
        layout.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(layout)

        let first = Self.step("1", "进入系统设置的「输入监控」")
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.bezelStyle = .rounded
        let second = Self.step("2", "拖入应用，打开它右侧的开关")
        let drag = DraggableApplicationCard(applicationURL: applicationURL)
        let reveal = NSButton(title: "在访达中显示应用", target: self, action: #selector(revealApplication))
        reveal.bezelStyle = .inline
        reveal.font = .systemFont(ofSize: 12)
        let help = NSTextField(wrappingLabelWithString: "如果列表里已有键帽大盗，可直接打开开关。系统提示「退出并重新打开」时，点它让授权生效。")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        troubleButton.target = self
        troubleButton.action = #selector(showTroubleshooting)
        troubleButton.bezelStyle = .inline
        troubleButton.font = .systemFont(ofSize: 12)
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 8
        for view in [first, settingsButton, second, drag, reveal, help] { steps.addArrangedSubview(view) }
        steps.setCustomSpacing(17, after: settingsButton)

        restartButton.target = self
        restartButton.action = #selector(relaunch)
        restartButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(dismiss)
        closeButton.bezelStyle = .rounded
        let showSettings = NSButton(title: "查看系统设置", target: self, action: #selector(openSettings))
        showSettings.bezelStyle = .rounded
        let actions = NSStackView(views: [showSettings, restartButton, troubleButton, NSView(), closeButton])
        actions.spacing = 8
        actions.detachesHiddenViews = true
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        for view in [top, headline, explanation, steps, actions] { layout.addArrangedSubview(view) }
        layout.setCustomSpacing(13, after: top)
        layout.setCustomSpacing(19, after: explanation)
        layout.setCustomSpacing(14, after: steps)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            layout.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            layout.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            explanation.widthAnchor.constraint(equalTo: layout.widthAnchor),
            steps.widthAnchor.constraint(equalTo: layout.widthAnchor),
            drag.widthAnchor.constraint(equalTo: steps.widthAnchor),
            help.widthAnchor.constraint(equalTo: steps.widthAnchor),
            actions.widthAnchor.constraint(equalTo: layout.widthAnchor)
        ])
        self.layout = layout
        self.showSettings = showSettings
    }

    private weak var layout: NSStackView?
    private weak var showSettings: NSButton?
    private static func step(_ number: String, _ title: String) -> NSView {
        let n = NSTextField(labelWithString: number)
        n.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        n.textColor = .systemTeal
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        let row = NSStackView(views: [n, label])
        row.spacing = 8
        return row
    }

    private func refresh() {
        let state = readState()
        guard state != currentState, let window, let layout else { return }
        currentState = state
        steps.isHidden = !state.showsSetupSteps
        showSettings?.isHidden = state.showsSetupSteps
        restartButton.isHidden = state != .waitingForListener
        troubleButton.isHidden = !state.showsSetupSteps
        closeButton.title = state.showsSetupSteps ? "稍后" : "完成"
        switch state {
        case .needsPermission:
            status.stringValue = "输入监控 · 等待授权"
            status.textColor = .secondaryLabelColor
            headline.stringValue = "让搭档跟上你的敲键"
            explanation.stringValue = "输入监控允许桌宠在你使用其他应用时识别按键和组合技。输入的文字不会保存。"
        case .waitingForListener:
            status.stringValue = "输入监控 · 已允许"
            status.textColor = .systemOrange
            headline.stringValue = "正在连接键盘"
            explanation.stringValue = "系统已允许输入监控。若几秒后仍未连接，请先重新打开应用。重开后仍没反应，点下方「修复旧授权」。"
        case .listening:
            status.stringValue = "输入监控 · 已就绪"
            status.textColor = .systemGreen
            headline.stringValue = "搭档已经听见键盘了"
            explanation.stringValue = "回到平常使用的应用，试着敲一个字母或按 ⌘C，看搭档跟着你行动。"
        case .petHidden:
            status.stringValue = "输入监控 · 已允许"
            status.textColor = .systemGreen
            headline.stringValue = "授权已完成"
            explanation.stringValue = "搭档目前已隐藏。打开菜单栏图标，选择「显示搭档」即可恢复按键动作。"
        }
        // Anchor the top edge while collapsing setup steps into the confirmation.
        window.contentView?.layoutSubtreeIfNeeded()
        var frame = window.frame
        let height = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 436,
                                                            height: ceil(layout.fittingSize.height) + 38)).height
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: window.isVisible)
    }
    @objc private func openSettings() {
        guard let window, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        if currentState?.showsSetupSteps == true, let screen = window.screen ?? NSScreen.main {
            // Keep the drag source beside System Settings and leave its list exposed.
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.minX + 12,
                y: max(visible.minY, min(window.frame.minY, visible.maxY - window.frame.height))))
            window.level = .floating
        }
        if !NSWorkspace.shared.open(url) {
            let alert = NSAlert()
            alert.messageText = "请从苹果菜单打开「系统设置」"
            alert.informativeText = "选择「隐私与安全性」，然后打开「输入监控」。"
            alert.beginSheetModal(for: window)
        }
    }
    @objc private func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([applicationURL])
    }
    @objc private func showTroubleshooting() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "输入监控已开启，搭档仍没反应？"
        alert.informativeText = "先重新打开键帽大盗。若仍未连接，在系统「输入监控」列表选中旧的键帽大盗条目，点减号移除。再将当前应用拖入列表、打开开关，并按系统提示选择「退出并重新打开」。"
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "重新打开应用")
        alert.beginSheetModal(for: window) { [weak self] result in
            if result == .alertSecondButtonReturn { self?.relaunch() }
        }
    }
    @objc private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: config) { app, error in
            DispatchQueue.main.async {
                if let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    NSApp.terminate(nil)
                } else if let error {
                    NSApp.presentError(error)
                }
            }
        }
    }
    @objc private func dismiss() { close() }
}
