import AppKit

private final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetApp: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private static let title = "Keycap Caper（键帽大盗）"
    private enum Setting {
        static let origin = "petOrigin"
        static let character = "petCharacter"
        static let muted = "muted"
        static let switchStyle = "switchStyle"
        static let hidesBubbles = "hidesBubbles"
        static let hidesCombos = "hidesCombos"
        static let lastGuideBuild = "lastGuideBuild"
    }

    private let keyboard = KeyboardInput()
    private let defaults = UserDefaults.standard
    private lazy var sound = KeySound(style: defaults.string(forKey: Setting.switchStyle)
        .flatMap(SwitchStyle.init(rawValue:)) ?? .red)
    private let view = PetView(frame: NSRect(origin: .zero, size: CatArt.size))
    private let panel = PetPanel(
        contentRect: NSRect(origin: .zero, size: CatArt.size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var status: NSStatusItem!
    private let trickBook = TrickBook()
    @MainActor private lazy var updater = AppUpdater()
    @MainActor private lazy var soundLibrary = SoundLibrary(
        available: { [unowned self] in self.sound.availableStyles },
        refresh: { [unowned self] in
            self.sound.refreshInstalledStyles()
            self.rebuildSoundMenu()
        },
        audition: { [unowned self] style in self.chooseSound(style) }
    )
    private lazy var permissionGuide = PermissionGuide { [weak self] in
        guard KeyboardInput.hasPermission else { return .needsPermission }
        guard let self else { return .waitingForListener }
        if !self.panel.isVisible { return .petHidden }
        return self.keyboard.isListening ? .listening : .waitingForListener
    }
    private var comboItem: NSMenuItem!
    private var visibilityItem: NSMenuItem!
    private var moveItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private let characterMenu = NSMenu(title: "选择搭档")
    private let switchMenu = NSMenu(title: "轴体音效")
    private var bubblesItem: NSMenuItem!
    private var timer: Timer?
    private var nextPermissionCheck: TimeInterval = 0
    private var demoTimers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpPanel()
        setUpMenu()

        keyboard.onKey = { [weak self] label, index, rightPaw, keyCode in
            self?.showKey(label, index: index, rightPaw: rightPaw, keyCode: keyCode)
        }
        keyboard.onCombo = { [weak self] trick in
            guard let self, self.panel.isVisible, self.view.showsCombos else { return }
            self.view.showCombo(trick)
        }
        checkPermission()

        let timer = Timer(timeInterval: 1 / 36, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if !KeyboardInput.hasPermission && defaults.string(forKey: Setting.lastGuideBuild) != build {
            defaults.set(build, forKey: Setting.lastGuideBuild)
            DispatchQueue.main.async { [weak self] in self?.permissionGuide.present(activate: false) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        cancelDemo()
        keyboard.stop()
        sound.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.orderFrontRegardless()
        checkPermission()
        if KeyboardInput.hasPermission { trickBook.present(character: view.character) }
        else { permissionGuide.present() }
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        checkPermission()
        visibilityItem.title = panel.isVisible ? "隐藏搭档" : "显示搭档"
        moveItem.title = view.moving ? "固定搭档位置" : "移动搭档"
        soundItem.state = defaults.bool(forKey: Setting.muted) ? .off : .on
        updateSwitchCheckmark()
        bubblesItem.state = view.showsBubbles ? .on : .off
        comboItem.state = view.showsCombos ? .on : .off
    }

    func windowDidMove(_ notification: Notification) {
        if view.moving { defaults.set(NSStringFromPoint(panel.frame.origin), forKey: Setting.origin) }
    }

    private func setUpPanel() {
        panel.title = Self.title
        panel.contentView = view
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        view.showsBubbles = !defaults.bool(forKey: Setting.hidesBubbles)
        view.showsCombos = !defaults.bool(forKey: Setting.hidesCombos)
        view.character = defaults.string(forKey: Setting.character).flatMap(PetCharacter.init(rawValue:)) ?? .cat

        if let savedOrigin = defaults.string(forKey: Setting.origin) {
            panel.setFrameOrigin(NSPointFromString(savedOrigin))
            screenChanged()
        } else {
            placeInCorner()
        }
        panel.orderFrontRegardless()
    }

    private func setUpMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            // Use the same full-color artwork as Finder, including its high-resolution representations.
            let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
            icon.isTemplate = false
            icon.size = NSSize(width: 23, height: 23)
            button.image = icon
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel(Self.title)
            button.toolTip = Self.title
        }

        let menu = NSMenu(title: Self.title)
        menu.delegate = self
        let title = NSMenuItem(title: Self.title, action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        let characterItem = NSMenuItem(title: characterMenu.title, action: nil, keyEquivalent: "")
        for character in PetCharacter.allCases {
            let choice = item(character.menuTitle, #selector(selectCharacter(_:)))
            choice.representedObject = character.rawValue
            choice.state = character == view.character ? .on : .off
            characterMenu.addItem(choice)
        }
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)
        menu.addItem(item("组合技图鉴…", #selector(openTrickBook)))
        menu.addItem(item("试听并看看动作", #selector(playDemo)))
        visibilityItem = item("隐藏搭档", #selector(toggleVisibility))
        moveItem = item("移动搭档", #selector(toggleMove))
        menu.addItem(visibilityItem)
        menu.addItem(moveItem)
        menu.addItem(item("放回右下角", #selector(resetPosition)))
        menu.addItem(.separator())
        let switchItem = NSMenuItem(title: "轴体音效", action: nil, keyEquivalent: "")
        rebuildSoundMenu()
        switchItem.submenu = switchMenu
        menu.addItem(switchItem)
        soundItem = item("打字时播放音效", #selector(toggleSound))
        bubblesItem = item("显示按键气泡", #selector(toggleBubbles))
        menu.addItem(soundItem)
        menu.addItem(bubblesItem)
        comboItem = item("展示快捷键组合技", #selector(toggleCombos))
        menu.addItem(comboItem)
        menu.addItem(.separator())
        menu.addItem(item("输入监控授权向导…", #selector(openInputSettings)))
        menu.addItem(item("检查更新…", #selector(checkUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("退出键帽大盗", #selector(quit)))
        status.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: "")
        result.target = self
        return result
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextPermissionCheck {
            nextPermissionCheck = now + 2
            checkPermission()
        }
        if panel.isVisible {
            if KeyboardInput.isSecureInput { view.clearKeyFeedback() }
            view.update(at: now)
        }
    }

    private func checkPermission() {
        let granted = KeyboardInput.hasPermission
        if granted && panel.isVisible {
            if !keyboard.isListening { keyboard.start() }
        } else if keyboard.isListening {
            keyboard.stop()
            view.clearKeyFeedback()
        }
    }

    private func showKey(_ label: String, index: Int?, rightPaw: Bool, keyCode: Int? = nil) {
        guard panel.isVisible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        view.press(label, keyIndex: index, rightPaw: rightPaw, at: now)
        if !defaults.bool(forKey: Setting.muted) { sound.play(label, index: index, keyCode: keyCode) }
    }

    @objc private func openInputSettings() { permissionGuide.present() }
    @MainActor @objc private func checkUpdates() { updater.show() }
    @MainActor @objc private func getSoundPacks() { soundLibrary.show() }
    @objc private func openTrickBook() { trickBook.present(character: view.character) }
    @objc private func toggleCombos() {
        view.showsCombos.toggle()
        defaults.set(!view.showsCombos, forKey: Setting.hidesCombos)
    }

    @objc private func selectCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let character = PetCharacter(rawValue: id) else { return }
        view.character = character
        trickBook.update(character: character)
        defaults.set(id, forKey: Setting.character)
        for choice in characterMenu.items {
            choice.state = choice === sender ? .on : .off
        }
    }

    @objc private func toggleVisibility() {
        if panel.isVisible {
            cancelDemo()
            sound.stop()
            view.clearKeyFeedback()
            setMoving(false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
        checkPermission()
    }

    @objc private func toggleMove() {
        panel.orderFrontRegardless()
        checkPermission()
        setMoving(!view.moving)
    }

    private func setMoving(_ value: Bool) {
        if view.moving && !value { defaults.set(NSStringFromPoint(panel.frame.origin), forKey: Setting.origin) }
        view.moving = value
        panel.isMovable = value
        panel.ignoresMouseEvents = !value
    }

    @objc private func resetPosition() {
        setMoving(false)
        defaults.removeObject(forKey: Setting.origin)
        placeInCorner()
        panel.orderFrontRegardless()
        checkPermission()
    }

    @objc private func toggleSound() {
        let muted = !defaults.bool(forKey: Setting.muted)
        defaults.set(muted, forKey: Setting.muted)
        if muted {
            cancelDemo()
            sound.stop()
        }
    }

    private func rebuildSoundMenu() {
        switchMenu.removeAllItems()
        for style in sound.availableStyles {
            let choice = item(style.menuTitle, #selector(selectSwitch(_:)))
            choice.representedObject = style.rawValue
            switchMenu.addItem(choice)
        }
        updateSwitchCheckmark()
        let missing = SwitchStyle.allCases.filter { $0.usesPersonalRecordings && !sound.availableStyles.contains($0) }
        if !missing.isEmpty {
            switchMenu.addItem(.separator())
            switchMenu.addItem(NSMenuItem(title: "从原站获取 · 仅供个人使用", action: nil, keyEquivalent: ""))
            for style in missing {
                let choice = item(style.menuTitle + "（获取）", #selector(getAndPlay(_:)))
                choice.representedObject = style.rawValue
                switchMenu.addItem(choice)
            }
        }
        switchMenu.addItem(.separator())
        switchMenu.addItem(item("获取原版音效…", #selector(getSoundPacks)))
        switchMenu.addItem(item("试听当前轴体", #selector(previewSwitch)))
    }

    private func updateSwitchCheckmark() {
        for choice in switchMenu.items {
            guard let id = choice.representedObject as? String else { continue }
            choice.state = id == sound.style.rawValue ? .on : .off
        }
    }

    @objc private func selectSwitch(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let style = SwitchStyle(rawValue: id) else { return }
        chooseSound(style)
    }

    @MainActor @objc private func getAndPlay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let style = SwitchStyle(rawValue: id) else { return }
        soundLibrary.show()
        soundLibrary.choose(style)
    }

    @discardableResult private func chooseSound(_ style: SwitchStyle) -> Bool {
        guard sound.availableStyles.contains(style), sound.select(style) else {
            rebuildSoundMenu()
            return false
        }
        defaults.set(style.rawValue, forKey: Setting.switchStyle)
        updateSwitchCheckmark()
        previewSwitch()
        return true
    }

    @objc private func previewSwitch() {
        cancelDemo()
        sound.play()
        for (delay, label) in [(0.16, "J"), (0.39, "空格")] {
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.sound.play(label) }
            RunLoop.main.add(timer, forMode: .common)
            demoTimers.append(timer)
        }
    }

    @objc private func toggleBubbles() {
        view.showsBubbles.toggle()
        defaults.set(!view.showsBubbles, forKey: Setting.hidesBubbles)
    }

    @objc private func playDemo() {
        cancelDemo()
        panel.orderFrontRegardless()
        checkPermission()
        let notes: [(String, Int?, Bool)] = [("A", 0, false), ("J", 9, true), ("F", 5, false), ("↵", nil, true)]
        for (offset, note) in notes.enumerated() {
            let timer = Timer(timeInterval: 0.10 + 0.22 * Double(offset), repeats: false) { [weak self] _ in
                self?.showKey(note.0, index: note.1, rightPaw: note.2)
            }
            RunLoop.main.add(timer, forMode: .common)
            demoTimers.append(timer)
        }
    }

    private func cancelDemo() {
        demoTimers.forEach { $0.invalidate() }
        demoTimers.removeAll(keepingCapacity: true)
    }

    @objc private func screenChanged() {
        let area = panel.frame.insetBy(dx: 45, dy: 22)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(area) }) {
            placeInCorner()
        }
    }

    private func placeInCorner() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.maxX - CatArt.size.width - 12, y: area.minY + 12))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
struct GreenEyedCat {
    static func main() {
        let app = NSApplication.shared
        let delegate = PetApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
