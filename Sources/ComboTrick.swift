import AppKit

enum ComboTrick: String, CaseIterable {
    case copy, paste, cut, undo, redo, save, find, selectAll

    private var info: (key: String, title: String, action: String, detail: String, symbol: String) {
        switch self {
        case .copy: return ("C", "纸片分身", "复制", "爪边的纸片一抖，变出一张副本。", "doc.on.doc")
        case .paste: return ("V", "飞帖归位", "粘贴", "小纸片打个旋，贴回夹板。", "clipboard")
        case .cut: return ("X", "一剪两段", "剪切", "剪刀一合，两截纸带各溜一边。", "scissors")
        case .undo: return ("Z", "倒带一格", "撤销", "怀表倒转，刚才那一步悄悄退回去。", "arrow.uturn.backward")
        case .redo: return ("Z", "重演一招", "重做", "怀表顺转，把上一步再演一遍。", "arrow.uturn.forward")
        case .save: return ("S", "宝箱封存", "保存", "小宝箱合上盖，锁孔闪一下。", "archivebox")
        case .find: return ("F", "侦探出动", "查找", "放大镜扫过地面，逮住一枚爪印。", "magnifyingglass")
        case .selectAll: return ("A", "一网打尽", "全选", "选框张开，把三颗小键帽一网收齐。", "selection.pin.in.out")
        }
    }

    var title: String { info.title }
    var actionName: String { info.action }
    var detail: String { info.detail }
    var symbolName: String { info.symbol }
    var letter: Character { Character(info.key.lowercased()) }
    var shortcut: String { (self == .redo ? "⇧⌘" : "⌘") + info.key }

    static func match(label: String, physicalKey: String?, flags: CGEventFlags) -> Self? {
        let modifiers = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn])
        guard modifiers == .maskCommand || modifiers == [.maskCommand, .maskShift] else { return nil }
        // A Latin keyboard layout may put C at a different physical position. Non-Latin
        // input methods often leave system shortcuts on the underlying physical letters.
        let latinOrASCII = label.unicodeScalars.count == 1 && label.unicodeScalars.allSatisfy(\.isASCII)
        let key = latinOrASCII ? label.uppercased() : physicalKey
        if modifiers.contains(.maskShift) { return key == "Z" ? .redo : nil }
        return allCases.first { $0 != .redo && $0.info.key == key }
    }
}
