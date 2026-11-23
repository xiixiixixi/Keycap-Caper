import AppKit
import Darwin

// Launched from the installed bundle. Receives verified staging directory, parent
// pid and version pair as data, waits for exit, then exchanges the two bundles
// on the same volume. No elevated privileges or shell are involved.
let fm = FileManager.default
let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("org.keycapcaper.desktop/Updates", isDirectory: true)
let receipt = support.appendingPathComponent("last-error.txt")
let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
let installed = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let parent = installed.deletingLastPathComponent()
let bundleID = "org.keycapcaper.desktop"

func runningAtDestination() -> [NSRunningApplication] {
    let binaries = installed.appendingPathComponent("Contents/MacOS", isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath().path
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { application in
        // Launch Services can retain the outgoing app briefly. Ask the kernel
        // whether the reported PID is still running this bundle's executable.
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let count = path.withUnsafeMutableBytes { bytes in
            proc_pidpath(application.processIdentifier, bytes.baseAddress, UInt32(bytes.count))
        }
        guard count > 0 else { return false }
        let executable = URL(fileURLWithPath: String(cString: path)).standardizedFileURL.resolvingSymlinksInPath()
        return executable.deletingLastPathComponent().path == binaries && !application.isTerminated
    }
}

func run(_ executable: String, _ arguments: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func buildNumber(_ url: URL) -> Int? {
    guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          info["CFBundleIdentifier"] as? String == bundleID else { return nil }
    if let text = info["CFBundleVersion"] as? String { return Int(text) }
    return info["CFBundleVersion"] as? Int
}

func wait(_ seconds: TimeInterval, for condition: () -> Bool) -> Bool {
    let until = ProcessInfo.processInfo.systemUptime + seconds
    repeat {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
    } while ProcessInfo.processInfo.systemUptime < until
    return condition()
}

func fail(_ message: String, relaunch: Bool = false) -> Never {
    try? message.write(to: receipt, atomically: true, encoding: .utf8)
    if relaunch && runningAtDestination().isEmpty { _ = run("/usr/bin/open", [installed.path]) }
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5, let pid = Int32(args[2]), pid > 1,
      let oldBuild = Int(args[3]), let newBuild = Int(args[4]), newBuild > oldBuild else { exit(2) }
let stage = URL(fileURLWithPath: args[1]).standardizedFileURL
let candidate = stage.appendingPathComponent("Keycap Caper.app")
guard installed.pathExtension == "app", stage.deletingLastPathComponent().resolvingSymlinksInPath().path == parent.path,
      stage.lastPathComponent.hasPrefix(".keycap-update-"),
      UUID(uuidString: String(stage.lastPathComponent.dropFirst(".keycap-update-".count))) != nil,
      candidate.resolvingSymlinksInPath().path == parent.appendingPathComponent(stage.lastPathComponent).appendingPathComponent("Keycap Caper.app").path else { exit(2) }

try fm.createDirectory(at: support, withIntermediateDirectories: true)
let lock = open(support.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
    try? fm.removeItem(at: stage)
    fail("另一次更新正在安装。")
}
defer { close(lock) }
guard wait(30, for: { kill(pid, 0) != 0 && errno == ESRCH }) else {
    try? fm.removeItem(at: stage)
    fail("应用仍在运行，本次安装已取消。")
}
func cancelInstall(_ reason: String) -> Never {
    try? fm.removeItem(at: stage)
    fail(reason, relaunch: true)
}
guard wait(5, for: { runningAtDestination().isEmpty }) else {
    cancelInstall("另一个桌宠进程还在使用这个安装位置，请退出后再试。")
}
let actualOld = buildNumber(installed)
guard actualOld == oldBuild else {
    cancelInstall("已安装的应用版本与更新开始时不同（预期 " + String(oldBuild) + "，实际 " + (actualOld.map(String.init) ?? "无法读取") + "）。请重新检查更新。")
}
let actualNew = buildNumber(candidate)
guard actualNew == newBuild else {
    cancelInstall("下载的应用版本与发布清单不同（预期 " + String(newBuild) + "，实际 " + (actualNew.map(String.init) ?? "无法读取") + "）。请重新检查更新。")
}
guard run("/usr/bin/codesign", ["--verify", "--strict", "--deep", candidate.path]) else {
    cancelInstall("下载的应用在安装前未通过系统签名验证。请重新检查更新。")
}
guard renamex_np(candidate.path, installed.path, UInt32(RENAME_SWAP)) == 0 else {
    try? fm.removeItem(at: stage)
    fail("无法替换应用，请检查「应用程序」目录的写入权限。", relaunch: true)
}
let opened = run("/usr/bin/open", ["-n", installed.path])
if opened && wait(25, for: { runningAtDestination().contains(where: { $0.isFinishedLaunching }) }) {
    try? fm.removeItem(at: receipt)
    try? fm.removeItem(at: stage)
    exit(0)
}
for process in runningAtDestination() { _ = process.terminate() }
guard wait(5, for: { runningAtDestination().isEmpty }),
      renamex_np(candidate.path, installed.path, UInt32(RENAME_SWAP)) == 0 else {
    fail("新版本启动异常。上一个版本保留在 " + candidate.path)
}
try? fm.removeItem(at: stage)
fail("新版未能启动，已恢复上一个版本。", relaunch: true)
