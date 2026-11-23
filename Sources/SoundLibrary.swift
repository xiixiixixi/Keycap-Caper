import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SoundLibrary: ObservableObject {
    let styles = SwitchStyle.allCases.filter(\.usesPersonalRecordings)
    @Published private(set) var installed: Set<SwitchStyle> = []
    @Published private(set) var loading: SwitchStyle?
    @Published private(set) var failures: [SwitchStyle: String] = [:]
    private let available: () -> [SwitchStyle]
    private let refresh: () -> Void
    private let audition: (SwitchStyle) -> Bool
    private var window: NSWindow?

    init(available: @escaping () -> [SwitchStyle], refresh: @escaping () -> Void,
         audition: @escaping (SwitchStyle) -> Bool) {
        self.available = available
        self.refresh = refresh
        self.audition = audition
    }

    func show() {
        installed = Set(available())
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 514),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "原版轴体音效"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SoundLibraryPage(library: self))
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func choose(_ style: SwitchStyle) {
        if installed.contains(style) { play(style) }
        else { fetch([style], auditionAfterward: true) }
    }

    func getAll() { fetch(styles.filter { !installed.contains($0) }, auditionAfterward: false) }

    private func play(_ style: SwitchStyle) {
        if !audition(style) {
            installed = Set(available())
            failures[style] = "这套声音未能播放，请重新获取。"
        }
    }

    func importArchive(_ style: SwitchStyle) {
        guard loading == nil, let window else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.zip]
        picker.message = "选择从原声页下载的「" + style.menuTitle + "」原始压缩包。"
        picker.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = picker.url else { return }
            self?.fetch([style], auditionAfterward: true, localArchive: url)
        }
    }

    private func fetch(_ items: [SwitchStyle], auditionAfterward: Bool, localArchive: URL? = nil) {
        guard loading == nil, let first = items.first else { return }
        loading = first
        Task {
            for style in items {
                loading = style
                failures.removeValue(forKey: style)
                do {
                    if let localArchive { try await OfficialPacks.install(style, from: localArchive) }
                    else { try await OfficialPacks.install(style) }
                    refresh()
                    installed = Set(available())
                    if installed.contains(style) {
                        if auditionAfterward { play(style) }
                    } else {
                        failures[style] = "文件已下载，但录音未能载入。"
                    }
                } catch {
                    failures[style] = error.localizedDescription
                }
            }
            loading = nil
        }
    }
}

private struct SoundLibraryPage: View {
    @ObservedObject var library: SoundLibrary
    private var installedCount: Int { library.styles.filter { library.installed.contains($0) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("原版轴体音效").font(.title.bold())
                    Text("从原作者的音效库下载到你的电脑，仅供个人使用。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(installedCount == library.styles.count ? "已全部获取" : "获取全部") { library.getAll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(library.loading != nil || installedCount == library.styles.count)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(library.styles, id: \.rawValue) { style in
                        row(style)
                        if style != library.styles.last { Divider() }
                    }
                }
            }
            HStack {
                Text("已获取 \(installedCount) / \(library.styles.count) 套，可在「轴体音效」菜单切换。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu("导入原包…") {
                    ForEach(library.styles, id: \.rawValue) { style in
                        Button(style.menuTitle) { library.importArchive(style) }
                    }
                }
                .fixedSize().disabled(library.loading != nil)
            }
        }
        .padding(22).frame(width: 560, height: 514)
    }

    private func row(_ style: SwitchStyle) -> some View {
        let title = style.menuTitle.components(separatedBy: " · ")
        let ready = library.installed.contains(style)
        let loading = library.loading == style
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title[0]).font(.system(size: 15, weight: .semibold))
                Text(title.dropFirst().joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                if let error = library.failures[style] {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Link("原声页", destination: OfficialPacks.page(for: style))
                .accessibilityLabel("\(title[0])的原声页")
            if loading { ProgressView().controlSize(.small) }
            Button(loading ? "获取中" : ready ? "使用并试听" : library.failures[style] == nil ? "获取" : "重试") {
                library.choose(style)
            }
            .frame(minWidth: 75, alignment: .trailing)
            .disabled(library.loading != nil && !ready)
            .accessibilityIdentifier("pack-" + style.rawValue)
        }
        .padding(.vertical, 8)
    }
}
