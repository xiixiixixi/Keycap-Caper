import CryptoKit
import Darwin
import Foundation

/// The release ships only this catalog. The recordings and their license arrive from
/// the original publisher when someone explicitly chooses to get a personal copy.
enum OfficialPacks {
    fileprivate struct Recording {
        let path: String
        let digest: String
        let bytes: Int
        let audio: String

        init(_ path: String, _ digest: String, _ bytes: Int, _ audio: String = "sound.ogg") {
            self.path = path
            self.digest = digest
            self.bytes = bytes
            self.audio = audio
        }

        var url: URL {
            URL(string: "https://downloads.mechvibes.com/sound-packs/")!.appendingPathComponent(path)
        }
    }

    private static let catalog: [SwitchStyle: Recording] = [
        .mahjong: Recording("mv-c4703e204564494aacd06f1aa6824f20/r2-0c26dc9b.zip",
            "77e43f821627398af8b077d33f57624e9ade4a987258a83f4836bb04febe7d1d", 291793, "concatenated_audio.wav"),
        .cherryRed: Recording("default-keyboard-cherrymx-red-abs/r1-515a0341.zip",
            "1f5090637fe875b99932cf84e035688e88c02914de8bfbee835d7cf3d3088dbc", 2335121),
        .cherryBlack: Recording("default-keyboard-cherrymx-black-pbt/r1-deab4368.zip",
            "5cba11379fb128d35b3f3c82fab1be6156f8a9ece180f6019caa6b0e3a3023a9", 2156333),
        .cherryBrown: Recording("default-keyboard-cherrymx-brown-pbt/r1-bc539d9d.zip",
            "95955dcc6ca00dd4b459d6779bdfab84e20d1938fc09b85cc70571350073ac91", 1938760),
        .cherryBlue: Recording("default-keyboard-cherrymx-blue-pbt/r1-10c20b53.zip",
            "49609933f7a0486107fdda72b145f4e88043bf998c7903508adc8fc21bcc87fc", 2477762),
        .crystalPurple: Recording("default-keyboard-eg-crystal-purple/r1-3ce884cb.zip",
            "fecfbf764c9a636a7761f8b67e5074e59a1f98945e52c792dc55ac7137158dd7", 321496, "purple.ogg"),
        .toprePurple: Recording("default-keyboard-topre-purple-hybrid-pbt/r1-4a4a456d.zip",
            "cac288959f5e88928d9c3593a85fac894a321abb43d1cb787006edde4dbae910", 1609885)
    ]

    static func page(for style: SwitchStyle) -> URL {
        let slug = style == .mahjong ? "novix-56-gateron-magnetic-jade-pro-he" : style.rawValue
        return URL(string: "https://mechvibes.com/sound-packs/")!.appendingPathComponent(slug)
    }

    static func directory(for style: SwitchStyle) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.keycapcaper.desktop/OriginalPacks", isDirectory: true)
            .appendingPathComponent(style.rawValue, isDirectory: true)
    }

    /// The optional file lets the owner import exactly the same original ZIP from the pack's page.
    static func install(_ style: SwitchStyle, from localArchive: URL? = nil) async throws {
        guard let recording = catalog[style] else { throw PackError("这套音效已随应用提供。") }
        let fm = FileManager.default
        let target = directory(for: style)
        let parent = target.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".pack-" + UUID().uuidString, isDirectory: true)
        let result = stage.appendingPathComponent("recording", isDirectory: true)
        let archive = stage.appendingPathComponent("original.zip")
        try fm.createDirectory(at: result, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }

        if let localArchive {
            try recording.checkSize(at: localArchive)
            try fm.copyItem(at: localArchive, to: archive)
        } else {
            try await recording.download(to: archive)
        }
        try recording.checkSize(at: archive)
        let content = try Data(contentsOf: archive)
        let hash = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        guard hash == recording.digest else { throw PackError("这个压缩包与原站已核对的版本不一致。请检查音效名称及版本。") }
        try Task.checkCancellation()
        // Each field is a fixed filename in an exact, hash-pinned original archive.
        // Stream bytes into files we create instead of interpreting ZIP entry paths or permissions.
        for name in ["config.json", "LICENSE.txt", recording.audio] {
            let destination = result.appendingPathComponent(name)
            guard fm.createFile(atPath: destination.path, contents: nil) else { throw PackError("无法写入本机的音效目录。") }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-p", archive.path, name]
            unzip.standardOutput = output
            unzip.standardError = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0, try output.offset() > 0 else { throw PackError("原声文件读取失败，请重新获取。") }
        }
        try Task.checkCancellation()
        if renamex_np(result.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST, renamex_np(result.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
                throw PackError("无法保存原版音效，请检查磁盘空间后重试。")
            }
        }
    }

    fileprivate struct PackError: LocalizedError {
        var errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }
}

extension OfficialPacks.Recording {
    fileprivate func checkSize(at file: URL) throws {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, info.fileSize == bytes else {
            throw OfficialPacks.PackError("压缩包大小与原版不符，请重新获取。")
        }
    }

    fileprivate func download(to output: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 90
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for attempt in 0...1 {
            try Task.checkCancellation()
            do {
                let guardrail = OriginalDownload(byteLimit: Int64(bytes))
                let (file, response) = try await session.download(from: url, delegate: guardrail)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw OfficialPacks.PackError("原站暂时无法提供这套音效，请稍后重试或从原站导入。")
                }
                try checkSize(at: file)
                try FileManager.default.moveItem(at: file, to: output)
                return
            } catch let error as URLError where attempt == 0 &&
                        [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }
}

private final class OriginalDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let byteLimit: Int64
    init(byteLimit: Int64) { self.byteLimit = byteLimit }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The pinned URL is already the publisher's versioned download destination.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > byteLimit || totalBytesExpectedToWrite > byteLimit { downloadTask.cancel() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
