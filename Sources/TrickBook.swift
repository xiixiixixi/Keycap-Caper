import AppKit
import SwiftUI

final class TrickBook: NSWindowController {
    private let book = TrickBookModel()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 756, height: 462),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "组合技图鉴"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TrickBookPage(book: book))
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present(character: PetCharacter) {
        book.character = character
        book.replay()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(character: PetCharacter) { book.character = character }
}

private final class TrickBookModel: ObservableObject {
    @Published var character: PetCharacter = .cat
    @Published var selected: ComboTrick = .copy
    @Published var take = 0
    func choose(_ trick: ComboTrick) {
        selected = trick
        replay()
    }
    func replay() { take &+= 1 }
}

private struct TrickBookPage: View {
    @ObservedObject var book: TrickBookModel
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private var accent: Color { dark ? Color(red: 0.72, green: 0.87, blue: 0.62) : Color(red: 0.21, green: 0.36, blue: 0.25) }
    private var inset: Color { dark ? Color(white: 0.15) : Color(red: 0.96, green: 0.95, blue: 0.92) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("组合技图鉴").font(.system(size: 24, weight: .bold, design: .rounded))
                    .padding(.bottom, 6)
                ForEach(ComboTrick.allCases, id: \.rawValue) { trick in
                    Button { book.choose(trick) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: trick.symbolName).frame(width: 20)
                            Text(trick.actionName).fontWeight(.medium)
                            Spacer()
                            Text(trick.shortcut).font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .padding(.horizontal, 11).frame(height: 32)
                        .contentShape(Rectangle())
                        .background(RoundedRectangle(cornerRadius: 8).fill(trick == book.selected ? accent : .clear))
                        .foregroundColor(trick == book.selected ? (dark ? .black : .white) : .primary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(trick.letter), modifiers: trick == .redo ? [.shift, .command] : [.command])
                    .accessibilityLabel("\(trick.actionName)  \(trick.shortcut)")
                    .accessibilityAddTraits(book.selected == trick ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(22).frame(width: 228).frame(maxHeight: .infinity, alignment: .top)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(book.selected.title).font(.system(size: 25, weight: .bold, design: .rounded))
                    Spacer()
                    Text(book.selected.shortcut)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.14)))
                        .foregroundStyle(accent)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(inset)
                    TrickStage(trick: book.selected, character: book.character, take: book.take)
                        .accessibilityLabel("\(book.character.menuTitle)，\(book.selected.title)预览")
                }
                .frame(maxHeight: .infinity)
                Text(book.selected.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { book.replay() } label: { Label("再演一次", systemImage: "arrow.clockwise") }
                        .controlSize(.large)
                    Text("也可在此按快捷键试招").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(width: 756, height: 462)
    }
}

private struct TrickStage: NSViewRepresentable {
    let trick: ComboTrick
    let character: PetCharacter
    let take: Int
    func makeNSView(context: Context) -> StageView { StageView() }
    func updateNSView(_ view: StageView, context: Context) { view.display(trick, character, take) }
    static func dismantleNSView(_ view: StageView, coordinator: ()) { view.stop() }

    final class StageView: NSView {
        private var trick: ComboTrick = .copy
        private var character: PetCharacter = .cat
        private var lastTake = -1
        private var start: TimeInterval = 0
        private var timer: Timer?

        func display(_ selected: ComboTrick, _ actor: PetCharacter, _ take: Int) {
            guard selected != trick || actor != character || take != lastTake else { return }
            trick = selected
            character = actor
            lastTake = take
            start = ProcessInfo.processInfo.systemUptime
            stop()
            needsDisplay = true
            let update = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] timer in
                guard let self, self.window?.isVisible == true else { timer.invalidate(); return }
                self.needsDisplay = true
                if ProcessInfo.processInfo.systemUptime - self.start >= ComboArt.duration { self.stop() }
            }
            timer = update
            RunLoop.main.add(update, forMode: .common)
        }

        func stop() { timer?.invalidate(); timer = nil }

        override func draw(_ dirtyRect: NSRect) {
            guard let c = NSGraphicsContext.current?.cgContext else { return }
            c.saveGState()
            defer { c.restoreGState() }
            let factor = min(bounds.width / CatArt.size.width, bounds.height / CatArt.size.height)
            c.translateBy(x: (bounds.width - CatArt.size.width * factor) * 0.5,
                          y: (bounds.height - CatArt.size.height * factor) * 0.5)
            c.scaleBy(x: factor, y: factor)
            let age = max(0, ProcessInfo.processInfo.systemUptime - start)
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let tap: CGFloat = reduced ? 0 : max(0, 1 - age / 0.20)
            CatArt.draw(in: c, gaze: CGVector(dx: -0.65, dy: 0), blink: 0, leftPress: tap,
                        rightPress: 0, keyIndex: nil, character: character)
            if age < ComboArt.duration { ComboArt.draw(trick, age: age, reducedMotion: reduced, in: c) }
        }
    }
}
