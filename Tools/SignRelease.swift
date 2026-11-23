// Publisher-side utility. Only the public verification key is bundled in the app.
import Foundation
import CryptoKit
import Darwin

struct Release: Encodable {
    let schema = 1
    let bundleID: String
    let build: Int
    let version: String
    let arch: String
    let minimumSystemVersion: String
    let archive: String
    let sha256: String
    let notes: String
}
struct Envelope: Encodable { let payload: String; let signature: String }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
func file(_ path: String) -> URL { URL(fileURLWithPath: path) }
func installPrivateKey(_ raw: Data, at url: URL) throws {
    // Never replace the publisher's identity, including during simultaneous initial setup.
    let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    if fd < 0 {
        if errno == EEXIST { return }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    try handle.write(contentsOf: raw)
    try handle.synchronize()
    try handle.close()
}
func signingKey(at url: URL) throws -> Curve25519.Signing.PrivateKey {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attrs[.type] as? FileAttributeType == .typeRegular,
          let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0
    else { fail("The signing key must be a regular file readable only by its owner.") }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: url))
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 3 else { fail("Usage: SignRelease keygen KEY PUBLIC or sign KEY PUBLIC APP ZIP ARCH NOTES OUTPUT") }
    let privateURL = file(args[1]), publicURL = file(args[2])
    if args[0] == "keygen" && args.count == 3 {
        if FileManager.default.fileExists(atPath: publicURL.path) && !FileManager.default.fileExists(atPath: privateURL.path) {
            fail("A public identity already exists. Restore its private signing key before publishing.")
        }
        try FileManager.default.createDirectory(at: privateURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try installPrivateKey(Curve25519.Signing.PrivateKey().rawRepresentation, at: privateURL)
        let key = try signingKey(at: privateURL)
        let publicText = key.publicKey.rawRepresentation.base64EncodedString()
        if FileManager.default.fileExists(atPath: publicURL.path) {
            guard try String(contentsOf: publicURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == publicText
            else { fail("Publisher key does not match the pinned public key.") }
        } else {
            try Data((publicText + "\n").utf8).write(to: publicURL, options: .withoutOverwriting)
        }
    } else if args[0] == "sign" && args.count == 8 {
        let key = try signingKey(at: privateURL)
        let publicData = try String(contentsOf: publicURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.publicKey.rawRepresentation.base64EncodedString() == publicData else { fail("Publisher key mismatch.") }
        let app = file(args[3]), archive = file(args[4])
        guard let info = Bundle(url: app)?.infoDictionary, let bundleID = info["CFBundleIdentifier"] as? String,
              bundleID == "org.keycapcaper.desktop", let buildText = info["CFBundleVersion"] as? String,
              let build = Int(buildText), build > 0, let version = info["CFBundleShortVersionString"] as? String,
              let minimum = info["LSMinimumSystemVersion"] as? String else { fail("Invalid app metadata.") }
        let digest = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        let release = Release(bundleID: bundleID, build: build, version: version, arch: args[5], minimumSystemVersion: minimum,
                              archive: archive.lastPathComponent, sha256: digest,
                              notes: try String(contentsOf: file(args[6]), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let payload = try JSONEncoder().encode(release)
        let envelope = Envelope(payload: payload.base64EncodedString(), signature: try key.signature(for: payload).base64EncodedString())
        try JSONEncoder().encode(envelope).write(to: file(args[7]), options: .atomic)
    } else { fail("Unexpected command or argument count.") }
} catch { fail(error.localizedDescription) }
