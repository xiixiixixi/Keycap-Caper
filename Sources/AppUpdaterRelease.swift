import CryptoKit
import Darwin
import Foundation

struct CaperUpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct CaperRelease: Decodable {
    let schema: Int
    let bundleID: String
    let build: Int
    let version: String
    let arch: String
    let minimumSystemVersion: String
    let archive: String
    let sha256: String
    let notes: String

    private struct Envelope: Decodable {
        let payload: Data
        let signature: Data
    }

    static var localChannel: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.keycapcaper.desktop/Updates/channel/latest.json")
    }

    static func remoteURL(_ address: String) -> URL? {
        guard let parts = URLComponents(string: address), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.fragment == nil, !parts.path.isEmpty, !parts.path.hasSuffix("/") else { return nil }
        return parts.url
    }

    static func verified(_ bytes: Data, key: Data, bundleID: String) throws -> CaperRelease {
        guard bytes.count <= 256 * 1024,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
              publicKey.isValidSignature(envelope.signature, for: envelope.payload) else {
            throw CaperUpdateError("更新清单的发布签名无效。请检查更新来源，或稍后重试。")
        }
        let r = try JSONDecoder().decode(Self.self, from: envelope.payload)
        guard r.schema == 1, r.bundleID == bundleID, r.build > 0, !r.version.isEmpty,
              !r.version.contains(where: { $0.isNewline }), r.version.count <= 40,
              r.archive.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,180}\.zip\z"#, options: .regularExpression) != nil,
              r.sha256.range(of: #"^[0-9a-f]{64}\z"#, options: .regularExpression) != nil else {
            throw CaperUpdateError("更新清单与应用不匹配。请检查发布的版本和文件。")
        }
        #if arch(arm64)
        let cpu = "arm64"
        #elseif arch(x86_64)
        let cpu = "x86_64"
        #else
        let cpu = "unsupported"
        #endif
        guard [cpu, "universal"].contains(r.arch) else { throw CaperUpdateError("此更新与当前处理器不兼容。") }
        let elements = r.minimumSystemVersion.split(separator: ".", omittingEmptySubsequences: false)
        let components = elements.compactMap { Int($0) }
        guard (1...3).contains(elements.count), components.count == elements.count,
              components.allSatisfy({ (0...999).contains($0) }) else { throw CaperUpdateError("更新清单的系统版本无效。") }
        let v = components + [0, 0]
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: v[0], minorVersion: v[1], patchVersion: v[2])) else {
            throw CaperUpdateError("此更新需要系统版本 " + r.minimumSystemVersion + " 或更高版本。")
        }
        return r
    }

    func verifyArchive(at url: URL) throws {
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        var digest = SHA256()
        while let chunk = try reader.read(upToCount: 262144), !chunk.isEmpty { digest.update(data: chunk) }
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == sha256 else { throw CaperUpdateError("更新包未通过完整性校验，请重新下载。") }
    }
}

private final class CaperDownloadPolicy: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    let progress: @Sendable (Double) -> Void

    init(limit: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.limit = limit
        self.progress = progress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { CaperRelease.remoteURL($0.absoluteString) } == nil ? nil : request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel(); return }
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
}

enum CaperUpdateFiles {
    static func fetch(_ url: URL, to dest: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let fileManager = FileManager.default
        func ensureSize(_ file: URL) throws {
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, let size = info.fileSize, size > 0, size <= limit else {
                throw CaperUpdateError("更新文件大小无效。")
            }
        }
        if url.isFileURL {
            guard fileManager.fileExists(atPath: url.path) else { throw CaperUpdateError("本机发布目录里暂时找不到更新文件。") }
            try ensureSize(url)
            try fileManager.copyItem(at: url, to: dest)
        } else {
            guard CaperRelease.remoteURL(url.absoluteString) != nil else { throw CaperUpdateError("网络更新源必须使用安全连接。") }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 180
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel() }
            let policy = CaperDownloadPolicy(limit: limit, progress: progress)
            let (file, response) = try await session.download(from: url, delegate: policy)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CaperUpdateError("更新服务器没有返回文件，请检查地址或稍后重试。")
            }
            try ensureSize(file)
            try fileManager.moveItem(at: file, to: dest)
        }
        try ensureSize(dest)
    }

    static func check(channel: URL, bundle: Bundle = .main) async throws -> CaperRelease {
        guard let keyURL = bundle.url(forResource: "UpdatePublicKey", withExtension: "txt"),
              let text = try? String(contentsOf: keyURL, encoding: .utf8),
              let key = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)), let id = bundle.bundleIdentifier else {
            throw CaperUpdateError("此安装缺少发布验证密钥，请使用完整安装包。")
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try await fetch(channel, to: temp, limit: 256 * 1024)
        return try CaperRelease.verified(Data(contentsOf: temp), key: key, bundleID: id)
    }

    /// The installer takes ownership of this private sibling directory only after it launches.
    static func stage(_ release: CaperRelease, channel: URL, bundle: Bundle = .main,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let fm = FileManager.default
        let destination = bundle.bundleURL
        let parent = destination.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".keycap-update-" + UUID().uuidString, isDirectory: true)
        let currentBuild = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        guard release.build > currentBuild, fm.isWritableFile(atPath: parent.path) else {
            throw CaperUpdateError("请从可写的「应用程序」目录运行，再安装较新的版本。")
        }
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let zip = stage.appendingPathComponent("update.zip")
            let package = channel.deletingLastPathComponent().appendingPathComponent(release.archive)
            try await fetch(package, to: zip, limit: 256 * 1024 * 1024, progress: progress)
            try release.verifyArchive(at: zip)
            // bsdtar's default safe extraction rejects traversal through .. and symlinks.
            try command("/usr/bin/tar", ["-xf", zip.path, "-C", stage.path, "--no-same-owner"])
            try fm.removeItem(at: zip)
            let contents = try fm.contentsOfDirectory(atPath: stage.path)
            guard contents == ["Keycap Caper.app"] else { throw CaperUpdateError("更新包的目录结构无效。") }
            let app = stage.appendingPathComponent("Keycap Caper.app")
            let infoFile = app.appendingPathComponent("Contents/Info.plist")
            let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoFile), format: nil) as? [String: Any]
            guard info?["CFBundleIdentifier"] as? String == release.bundleID,
                  info?["CFBundleVersion"] as? String == String(release.build),
                  info?["CFBundleShortVersionString"] as? String == release.version else {
                throw CaperUpdateError("应用的实际版本与签名清单不符。")
            }
            #if arch(arm64)
            let cpu = CPU_TYPE_ARM64
            #elseif arch(x86_64)
            let cpu = CPU_TYPE_X86_64
            #endif
            guard let name = info?["CFBundleExecutable"] as? String, !name.isEmpty, !name.contains("/"),
                  Bundle(url: app)?.executableArchitectures?.contains(NSNumber(value: cpu)) == true else {
                throw CaperUpdateError("更新包缺少适合这台电脑的应用程序。")
            }
            try command("/usr/bin/codesign", ["--verify", "--strict", "--deep", app.path])
            return stage
        } catch {
            try? fm.removeItem(at: stage)
            throw error
        }
    }

    private static func command(_ executable: String, _ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw CaperUpdateError("更新包无法解开，或未通过应用验证。") }
    }
}
