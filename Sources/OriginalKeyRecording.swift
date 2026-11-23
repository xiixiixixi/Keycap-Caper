import AVFoundation
import Carbon

// Author-supplied single-file soundboards use web physical key names and milliseconds.
final class OriginalKeyRecording {
    private struct Configuration: Decodable {
        let audio_file: String
        let definitions: [String: Definition]
        struct Definition: Decodable { let timing: [[Double]] }
    }

    private let source: URL
    private let ranges: [String: [ClosedRange<Double>]]
    private(set) var clips: [String: Data] = [:]

    init?(directory: URL) {
        let config = directory.appendingPathComponent("config.json")
        guard let size = try? config.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= 512 * 1024,
              let data = try? Data(contentsOf: config),
              let info = try? JSONDecoder().decode(Configuration.self, from: data),
              ["concatenated_audio.wav", "sound.ogg", "purple.ogg"].contains(info.audio_file),
              info.definitions.count <= 256 else { return nil }
        source = directory.appendingPathComponent(info.audio_file)
        guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let bytes = values.fileSize, bytes > 0, bytes <= 16 * 1024 * 1024 else { return nil }

        var checked: [String: [ClosedRange<Double>]] = [:]
        for (key, definition) in info.definitions {
            let spans = definition.timing
            guard (1...2).contains(spans.count), spans.allSatisfy({ bounds in
                bounds.count == 2 && bounds[0] >= 0 && bounds[1] > bounds[0]
                    && bounds[1] <= 180_000 && bounds[1] - bounds[0] <= 2000
            }) else { return nil }
            // Keep the author's downstroke/return order, including separate locations in the soundboard.
            checked[key] = spans.map { $0[0]...$0[1] }
        }
        for key in ["KeyA", "KeyJ", "Enter", "Space"] where checked[key] == nil { return nil }
        ranges = checked
    }

    func prepare() -> Bool {
        if !clips.isEmpty { return true }
        guard let pcm = SoundboardPCM(source) else { return false }
        var distinct: [[Range<Int>]: Data] = [:]
        var loaded: [String: Data] = [:]
        for (name, spans) in ranges {
            let frames = spans.compactMap { pcm.frames(in: $0) }
            guard frames.count == spans.count else { return false }
            if let cached = distinct[frames] { loaded[name] = cached; continue }
            guard let clip = pcm.wave(frames) else { continue }
            distinct[frames] = clip
            loaded[name] = clip
        }
        guard ["KeyA", "KeyJ", "Enter", "Space"].allSatisfy({ loaded[$0] != nil }) else { return false }
        clips = loaded
        return true
    }

    func unload() { clips.removeAll() }

    func key(for label: String, index: Int?, code: Int?) -> String {
        if let code, let physical = Self.positions[code], clips[physical] != nil { return physical }
        if let index, (0..<26).contains(index) { return "Key" + String(UnicodeScalar(65 + index)!) }
        if let special = Self.previewKeys[label] { return special }
        if label.utf8.count == 1, let c = label.uppercased().utf8.first {
            if (65...90).contains(c) { return "Key" + label.uppercased() }
            if (48...57).contains(c) { return "Digit" + label }
        }
        return "KeyA"
    }

    private static let previewKeys = ["空格":"Space", "↩":"Enter", "↵":"NumpadEnter", "⌫":"Backspace",
                                      "⇥":"Tab", "⇧":"ShiftLeft", "⌃":"ControlLeft", "⌥":"AltLeft"]
    private static let positions: [Int: String] = [
        kVK_ANSI_A:"KeyA", kVK_ANSI_B:"KeyB", kVK_ANSI_C:"KeyC", kVK_ANSI_D:"KeyD",
        kVK_ANSI_E:"KeyE", kVK_ANSI_F:"KeyF", kVK_ANSI_G:"KeyG", kVK_ANSI_H:"KeyH",
        kVK_ANSI_I:"KeyI", kVK_ANSI_J:"KeyJ", kVK_ANSI_K:"KeyK", kVK_ANSI_L:"KeyL",
        kVK_ANSI_M:"KeyM", kVK_ANSI_N:"KeyN", kVK_ANSI_O:"KeyO", kVK_ANSI_P:"KeyP",
        kVK_ANSI_Q:"KeyQ", kVK_ANSI_R:"KeyR", kVK_ANSI_S:"KeyS", kVK_ANSI_T:"KeyT",
        kVK_ANSI_U:"KeyU", kVK_ANSI_V:"KeyV", kVK_ANSI_W:"KeyW", kVK_ANSI_X:"KeyX",
        kVK_ANSI_Y:"KeyY", kVK_ANSI_Z:"KeyZ",
        kVK_ANSI_0:"Digit0", kVK_ANSI_1:"Digit1", kVK_ANSI_2:"Digit2", kVK_ANSI_3:"Digit3",
        kVK_ANSI_4:"Digit4", kVK_ANSI_5:"Digit5", kVK_ANSI_6:"Digit6", kVK_ANSI_7:"Digit7",
        kVK_ANSI_8:"Digit8", kVK_ANSI_9:"Digit9",
        kVK_ANSI_Grave:"Backquote", kVK_ANSI_Minus:"Minus", kVK_ANSI_Equal:"Equal",
        kVK_ANSI_LeftBracket:"BracketLeft", kVK_ANSI_RightBracket:"BracketRight", kVK_ANSI_Backslash:"Backslash",
        kVK_ANSI_Semicolon:"Semicolon", kVK_ANSI_Quote:"Quote", kVK_ANSI_Comma:"Comma",
        kVK_ANSI_Period:"Period", kVK_ANSI_Slash:"Slash", kVK_Return:"Enter", kVK_Tab:"Tab",
        kVK_Space:"Space", kVK_Delete:"Backspace", kVK_ForwardDelete:"Delete", kVK_Escape:"Escape",
        kVK_Shift:"ShiftLeft", kVK_RightShift:"ShiftRight", kVK_Control:"ControlLeft", kVK_RightControl:"ControlLeft",
        kVK_Option:"AltLeft", kVK_RightOption:"AltLeft", kVK_CapsLock:"CapsLock",
        kVK_LeftArrow:"ArrowLeft", kVK_RightArrow:"ArrowRight", kVK_UpArrow:"ArrowUp", kVK_DownArrow:"ArrowDown",
        kVK_Home:"Home", kVK_End:"End", kVK_PageUp:"PageUp", kVK_PageDown:"PageDown", kVK_Help:"Insert",
        kVK_F1:"F1", kVK_F2:"F2", kVK_F3:"F3", kVK_F4:"F4", kVK_F5:"F5", kVK_F6:"F6",
        kVK_F7:"F7", kVK_F8:"F8", kVK_F9:"F9", kVK_F10:"F10", kVK_F11:"F11", kVK_F12:"F12",
        kVK_ANSI_Keypad0:"Numpad0", kVK_ANSI_Keypad1:"Numpad1", kVK_ANSI_Keypad2:"Numpad2",
        kVK_ANSI_Keypad3:"Numpad3", kVK_ANSI_Keypad4:"Numpad4", kVK_ANSI_Keypad5:"Numpad5",
        kVK_ANSI_Keypad6:"Numpad6", kVK_ANSI_Keypad7:"Numpad7", kVK_ANSI_Keypad8:"Numpad8",
        kVK_ANSI_Keypad9:"Numpad9", kVK_ANSI_KeypadEnter:"NumpadEnter", kVK_ANSI_KeypadClear:"NumLock",
        kVK_ANSI_KeypadPlus:"NumpadAdd", kVK_ANSI_KeypadMinus:"NumpadSubtract", kVK_ANSI_KeypadMultiply:"NumpadMultiply",
        kVK_ANSI_KeypadDivide:"NumpadDivide", kVK_ANSI_KeypadDecimal:"NumpadDecimal"
    ]
}

private struct SoundboardPCM {
    let bytes: Data
    let rate: Int
    let channels: Int

    init?(_ file: URL) {
        if file.pathExtension.lowercased() == "ogg" {
            guard let encoded = try? Data(contentsOf: file, options: .mappedIfSafe),
                  encoded.count <= 16 * 1024 * 1024 else { return nil }
            var frames: Int32 = 0, channels: Int32 = 0, rate: Int32 = 0
            guard let samples = encoded.withUnsafeBytes({ buffer in
                caper_decode_vorbis(buffer.bindMemory(to: UInt8.self).baseAddress, Int32(buffer.count), &frames, &channels, &rate)
            }) else { return nil }
            self.channels = Int(channels)
            self.rate = Int(rate)
            bytes = Data(bytesNoCopy: samples, count: Int(frames) * Int(channels) * 2, deallocator: .free)
        } else {
            var handle: AudioFileID?
            guard AudioFileOpenURL(file as CFURL, .readPermission, kAudioFileWAVEType, &handle) == noErr,
                  let handle else { return nil }
            defer { AudioFileClose(handle) }
            var format = AudioStreamBasicDescription()
            var infoSize = UInt32(MemoryLayout.size(ofValue: format))
            guard AudioFileGetProperty(handle, kAudioFilePropertyDataFormat, &infoSize, &format) == noErr,
                  format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 16,
                  format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  (8000...96000).contains(format.mSampleRate), (1...2).contains(format.mChannelsPerFrame),
                  format.mBytesPerFrame == 2 * format.mChannelsPerFrame else { return nil }
            var size: UInt64 = 0
            infoSize = UInt32(MemoryLayout.size(ofValue: size))
            guard AudioFileGetProperty(handle, kAudioFilePropertyAudioDataByteCount, &infoSize, &size) == noErr,
                  size > 0, size <= 32 * 1024 * 1024, size % UInt64(format.mBytesPerFrame) == 0 else { return nil }
            var count = UInt32(size)
            var samples = Data(count: Int(count))
            let status = samples.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                AudioFileReadBytes(handle, false, 0, &count, raw.baseAddress!)
            }
            guard status == noErr, count == UInt32(size) else { return nil }
            channels = Int(format.mChannelsPerFrame)
            rate = Int(format.mSampleRate)
            bytes = samples
        }
    }

    func frames(in span: ClosedRange<Double>) -> Range<Int>? {
        let total = bytes.count / (channels * 2)
        let start = Int((span.lowerBound * Double(rate) / 1000).rounded())
        let end = Int((span.upperBound * Double(rate) / 1000).rounded())
        // Some boards round their final timestamp to the nearest millisecond.
        guard start < min(end, total), end <= total + rate / 1000 else { return nil }
        return start..<min(end, total)
    }

    func wave(_ parts: [Range<Int>]) -> Data? {
        let stride = channels * 2
        var samples = Data(capacity: parts.reduce(0) { $0 + $1.count * stride })
        for frames in parts {
            samples.append(bytes[(frames.lowerBound * stride)..<(frames.upperBound * stride)])
        }
        let audible = samples.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).contains { abs(Int($0)) > 40 } }
        guard audible else { return nil }
        var result = Data(capacity: 44 + samples.count)
        func tag(_ value: String) { result.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { result.append(contentsOf: $0) }
        }
        tag("RIFF"); number(UInt32(36 + samples.count)); tag("WAVE"); tag("fmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(channels)); number(UInt32(rate))
        number(UInt32(rate * stride)); number(UInt16(stride)); number(UInt16(16))
        tag("data"); number(UInt32(samples.count)); result.append(samples)
        return result
    }
}
