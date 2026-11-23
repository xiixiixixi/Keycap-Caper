import AppKit
import Carbon
import CoreGraphics
import IOKit.hidsystem

final class KeyboardInput {
    var onKey: ((String, Int?, Bool, Int) -> Void)?
    var onCombo: ((ComboTrick) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isListening: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    static var isSecureInput: Bool { IsSecureEventInputEnabled() }

    static func requestPermission() {
        if !hasPermission { _ = CGRequestListenEventAccess() }
    }

    @discardableResult
    func start() -> Bool {
        precondition(Thread.isMainThread)
        if isListening { return true }
        stop()
        guard Self.hasPermission else { return false }

        // A passive event tap lets the overlay observe keys without changing them.
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                if let context {
                    let input = Unmanaged<KeyboardInput>.fromOpaque(context).takeUnretainedValue()
                    input.handle(type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            return false
        }

        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return isListening
    }

    func stop() {
        precondition(Thread.isMainThread)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    deinit { stop() }

    private func handle(_ type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap, Self.hasPermission { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        case .keyDown, .flagsChanged:
            break
        default:
            return
        }

        guard !Self.isSecureInput else { return }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged {
            // Modifier flags describe this event even if a quick release is already queued.
            guard let modifier = Self.modifiers[keyCode],
                  event.flags.rawValue & UInt64(modifier.mask) != 0 else { return }
            onKey?(modifier.label, nil, Self.rightHandKeys.contains(keyCode), keyCode)
            return
        }

        // BongoCat-mac only animates a new press when a key is held and repeats.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        let physicalKey = Self.printableKeys[keyCode]
        let label = Self.specialKeys[keyCode] ?? Self.printableLabel(event) ?? physicalKey ?? "键"
        let letterIndex = physicalKey?.utf8.first.flatMap { byte in
            (65...90).contains(byte) ? Int(byte) - 65 : nil
        }
        onKey?(label, letterIndex, Self.rightHandKeys.contains(keyCode), keyCode)
        if let trick = ComboTrick.match(label: label, physicalKey: physicalKey, flags: event.flags) {
            onCombo?(trick)
        }
    }

    private static func printableLabel(_ event: CGEvent) -> String? {
        // Adapts BongoCat-mac's layout-aware display label lookup.
        // Upstream: https://github.com/Gamma-Software/BongoCat-mac/blob/a1061e4592f83cd5a4f26ed85829a48181066d69/app/BongoCat/Managers/InputMonitor.swift
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              characters.count == 1,
              !characters.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }

        let uppercase = characters.uppercased()
        return uppercase.count == 1 ? uppercase : characters
    }

    // The fallback labels and paw locations follow the physical Mac ANSI keyboard.
    private static let printableKeys: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Grave: "`", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/"
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "空格", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "↵",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Tab: "⇥", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

    private static let modifiers: [Int: (label: String, mask: Int32)] = [
        kVK_Command: ("⌘", NX_DEVICELCMDKEYMASK), kVK_RightCommand: ("⌘", NX_DEVICERCMDKEYMASK),
        kVK_Shift: ("⇧", NX_DEVICELSHIFTKEYMASK), kVK_RightShift: ("⇧", NX_DEVICERSHIFTKEYMASK),
        kVK_Option: ("⌥", NX_DEVICELALTKEYMASK), kVK_RightOption: ("⌥", NX_DEVICERALTKEYMASK),
        kVK_Control: ("⌃", NX_DEVICELCTLKEYMASK), kVK_RightControl: ("⌃", NX_DEVICERCTLKEYMASK),
        kVK_CapsLock: ("⇪", NX_ALPHASHIFT_STATELESS_MASK | NX_DEVICE_ALPHASHIFT_STATELESS_MASK),
        kVK_Function: ("Fn", NX_SECONDARYFNMASK)
    ]

    // Adapts BongoCat-mac's paw assignment to physical key codes.
    // Upstream: https://github.com/Gamma-Software/BongoCat-mac/blob/a1061e4592f83cd5a4f26ed85829a48181066d69/app/BongoCat/Views/CatView.swift
    private static let rightHandKeys: Set<Int> = [
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0,
        kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_Delete,
        kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P,
        kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket, kVK_ANSI_Backslash,
        kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_Return,
        kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
        kVK_RightShift, kVK_RightOption, kVK_RightCommand, kVK_RightControl,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
        kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7,
        kVK_ANSI_Keypad8, kVK_ANSI_Keypad9, kVK_ANSI_KeypadEnter
    ]
}
