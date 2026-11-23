import AVFoundation

enum SwitchStyle: String, CaseIterable {
    case mahjong
    case cherryRed = "cherrymx-red-abs-keycaps"
    case cherryBlack = "cherrymx-black-pbt-keycaps"
    case cherryBrown = "cherrymx-brown-pbt-keycaps"
    case cherryBlue = "cherrymx-blue-pbt-keycaps"
    case crystalPurple = "eg-crystal-purple"
    case toprePurple = "topre-purple-hybrid-pbt-keycaps"
    case outemuGreen = "outemu-green"
    case red, brown, blue
    case silentRed = "silent-red"

    var menuTitle: String {
        switch self {
        case .mahjong: return "麻将音 · 佳达隆磁玉专业版实录"
        case .cherryRed: return "樱桃红轴 · 线性实录"
        case .cherryBlack: return "樱桃黑轴 · 线性实录"
        case .cherryBrown: return "樱桃茶轴 · 段落实录"
        case .cherryBlue: return "樱桃青轴 · 有声点击实录"
        case .crystalPurple: return "水晶紫轴 · 段落实录"
        case .toprePurple: return "东普紫轴 · 静电容实录"
        case .outemuGreen: return "高特绿轴 · 有声点击实录"
        case .red: return "红轴 · 轻快顺滑（模拟）"
        case .brown: return "茶轴 · 柔和段落（模拟）"
        case .blue: return "青轴 · 清脆双响（模拟）"
        case .silentRed: return "静音红轴 · 低声闷敲（模拟）"
        }
    }

    var usesPersonalRecordings: Bool {
        switch self {
        case .mahjong, .cherryRed, .cherryBlack, .cherryBrown, .cherryBlue, .crystalPurple, .toprePurple:
            return true
        case .red, .brown, .blue, .silentRed, .outemuGreen:
            return false
        }
    }
}

private final class RecordedKeys {
    private let original: OriginalKeyRecording?
    private let mapping: [String: String]
    private let directory: URL
    private var pools: [String: [AVAudioPlayer]] = [:]

    init?(style: SwitchStyle, support: URL) {
        directory = support.appendingPathComponent("org.keycapcaper.desktop/Sounds", isDirectory: true)
            .appendingPathComponent(style.rawValue, isDirectory: true)
        original = OriginalKeyRecording(directory: OfficialPacks.directory(for: style))
        if original != nil {
            mapping = [:]
            return
        }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("mapping.plist")),
              let mapping = try? PropertyListDecoder().decode([String: String].self, from: data),
              ["A", "J", "空格"].allSatisfy({ mapping[$0] != nil }) else { return nil }
        self.mapping = mapping
        // Check file headers without allocating an audio player for every key in every pack.
        for name in Set(mapping.values) {
            guard name.range(of: #"^sample-[0-9]+$"#, options: .regularExpression) != nil,
                  let file = try? AVAudioFile(forReading: sampleURL(name)), file.length > 0 else { return nil }
        }
    }

    private func sampleURL(_ name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension("wav")
    }

    private func readyVoice(_ name: String) -> AVAudioPlayer? {
        let voice: AVAudioPlayer?
        if let original {
            guard let data = original.clips[name] else { return nil }
            voice = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
        } else {
            voice = try? AVAudioPlayer(contentsOf: sampleURL(name))
        }
        guard let player = voice, player.prepareToPlay() else { return nil }
        return player
    }

    func warmUp() -> Bool {
        if let original, !original.prepare() { return false }
        for label in ["A", "J", "空格"] {
            guard let name = sampleName(label, index: nil, keyCode: nil) else { return false }
            if pools[name] == nil {
                guard let player = readyVoice(name) else { return false }
                pools[name] = [player]
            }
        }
        return true
    }

    private func sampleName(_ label: String, index: Int?, keyCode: Int?) -> String? {
        if let original {
            let key = original.key(for: label, index: index, code: keyCode)
            return original.clips[key] != nil ? key : "KeyA"
        }
        let letter = index.flatMap { (0..<26).contains($0) ? String(UnicodeScalar(65 + $0)!) : nil }
        return letter.flatMap { mapping[$0] } ?? mapping[label] ?? mapping[label.uppercased()] ?? mapping["A"]
    }

    func play(_ label: String, index: Int?, keyCode: Int?) {
        guard let name = sampleName(label, index: index, keyCode: keyCode) else { return }
        var voices = pools[name] ?? []
        let voice: AVAudioPlayer
        if let index = voices.firstIndex(where: { !$0.isPlaying }) {
            voice = voices.remove(at: index)
        } else if voices.count < 8, let extra = readyVoice(name) {
            voice = extra
        } else if !voices.isEmpty {
            voice = voices.removeFirst()
        } else {
            return
        }
        voices.append(voice)
        pools[name] = voices
        voice.currentTime = 0
        voice.play()
    }

    func stop() {
        for voices in pools.values {
            for player in voices where player.isPlaying { player.stop() }
        }
        pools.removeAll()
    }

    func unloadSamples() { original?.unload() }
}

final class KeySound {
    private(set) var style: SwitchStyle
    private var recordings: [SwitchStyle: RecordedKeys] = [:]
    private var voices: [AVAudioPlayer] = []
    private var nextVoice = 0
    var availableStyles: [SwitchStyle] {
        SwitchStyle.allCases.filter { !$0.usesPersonalRecordings || recordings[$0] != nil }
    }

    init(style: SwitchStyle) {
        self.style = .red
        refreshInstalledStyles()
        if availableStyles.contains(style) { self.style = style }
        if !loadVoices() {
            self.style = .red
            _ = loadVoices()
        }
    }

    func refreshInstalledStyles() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for style in SwitchStyle.allCases where style.usesPersonalRecordings && recordings[style] == nil {
            recordings[style] = RecordedKeys(style: style, support: support)
        }
    }

    @discardableResult
    func select(_ newStyle: SwitchStyle) -> Bool {
        guard availableStyles.contains(newStyle) else { return false }
        if style == newStyle { return true }
        // Validate and preload the newly acquired recording before switching away.
        if let pack = recordings[newStyle], !pack.warmUp() {
            pack.stop()
            recordings.removeValue(forKey: newStyle)
            return false
        }
        stop()
        recordings[style]?.unloadSamples()
        style = newStyle
        return loadVoices()
    }

    private func loadVoices() -> Bool {
        if let pack = recordings[style] {
            voices.removeAll()
            return pack.warmUp()
        }
        // Two sets of four taps allow overlapping key presses with the bundled sounds.
        voices = (0..<8).compactMap { slot in
            let name = "\(style.rawValue)-\(slot % 4 + 1)"
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"),
                  let player = try? AVAudioPlayer(contentsOf: url), player.prepareToPlay() else { return nil }
            return player
        }
        nextVoice = 0
        return !voices.isEmpty
    }

    func play(_ label: String = "A", index: Int? = nil, keyCode: Int? = nil) {
        if let pack = recordings[style] {
            pack.play(label, index: index, keyCode: keyCode)
            return
        }
        guard !voices.isEmpty else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.currentTime = 0
        voice.play()
    }

    func stop() {
        recordings[style]?.stop()
        for voice in voices where voice.isPlaying { voice.stop() }
    }
}
