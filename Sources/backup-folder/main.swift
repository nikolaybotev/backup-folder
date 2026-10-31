// Generic hourly APFS-clone snapshot.
// Two-argument form: backup-folder <source-dir> <backup-dir>
// Job form: backup-folder --config <config.toml>
// Does everything in-process (no shell), so a Full Disk Access grant applies to this binary only.
// Retention: every snapshot for 48h, then the first snapshot of each day up to 60 days.
import Foundation
import Darwin
import BuildStamp
#if canImport(ToolConfig)
import ToolConfig
#endif

private let stderrLock = NSLock()

private func writeStderrLine(_ line: String) {
    stderrLock.lock()
    FileHandle.standardError.write(Data(line.utf8))
    stderrLock.unlock()
}

private func usage() -> Never {
    writeStderrLine("usage: backup-folder /abs/source /abs/backup-dir\n       backup-folder --config /abs/config.toml\n")
    exit(2)
}

@main
struct BackupFolderCommand {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("--version") {
            let verbose = args.contains("--verbose")
            print(BuildStamp.versionLine(productName: "backup-folder", verbose: verbose))
            exit(0)
        }
        if args.count == 3, args[1] == "--config" {
            guard args[2].hasPrefix("/") else { usage() }
            exit(await runConfigJob(args[2]))
        }
        if args.count == 3, args[1].hasPrefix("/"), args[2].hasPrefix("/") {
            exit(runCommandLineFolder(rawSource: args[1], rawDest: args[2]))
        }
        usage()
    }
}

private func runConfigJob(_ path: String) async -> Int32 {
    guard configPermissionsAcceptable(at: path) else {
        writeStderrLine("config permissions too open\n")
        return 2
    }
    let text: String
    do {
        text = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        writeStderrLine("config io error\n")
        return 2
    }
    switch parseBackupConfig(text) {
    case .failure(let error):
        writeStderrLine("config parse error: \(error.message)\n")
        return 2
    case .success(let config):
        return await FolderJob.run(pairs: config.folders, concurrency: config.concurrency) { pair in
            runOneFolder(source: pair.source, dest: pair.dest)
        }
    }
}

private func runCommandLineFolder(rawSource: String, rawDest: String) -> Int32 {
    if PathContainment.refuses(source: rawSource, dest: rawDest) {
        writeStderrLine("backup dir must not be inside source\n")
        return 2
    }
    let source = rawSource.hasSuffix("/") ? String(rawSource.dropLast()) : rawSource
    let dest = rawDest.hasSuffix("/") ? String(rawDest.dropLast()) : rawDest
    return runOneFolder(source: source, dest: dest)
}

private func runOneFolder(source src: String, dest: String) -> Int32 {
    if PathContainment.refuses(source: src, dest: dest) {
        writeStderrLine("backup dir must not be inside source\n")
        return 2
    }
    let logPath = dest + "/backup.log"
    let fm = FileManager.default

    func log(_ s: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let line = "\(formatter.string(from: Date())) \(s)\n"
        writeStderrLine(line)
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }

    do {
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
    } catch {
        writeStderrLine("ERROR: cannot create \(dest): \(error)\n")
        return 1
    }

    guard (try? fm.contentsOfDirectory(atPath: src)) != nil else {
        log("ERROR: cannot read \(src) (Full Disk Access?)")
        return 1
    }

    let lockPath = dest + "/.backup-folder.lock"
    let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
    if lockFD < 0 {
        log("ERROR: cannot open lock \(lockPath) (errno \(errno))")
        return 1
    }
    defer { close(lockFD) }
    if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
        if errno == EWOULDBLOCK {
            log("skipped; dest busy")
            return 0
        }
        log("ERROR: flock \(lockPath) (errno \(errno))")
        return 1
    }

    if let children = try? fm.contentsOfDirectory(atPath: dest) {
        for name in children where name.hasPrefix(".inprogress-") {
            try? fm.removeItem(atPath: dest + "/" + name)
        }
    }

    let nameFormatter = DateFormatter()
    nameFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
    nameFormatter.locale = Locale(identifier: "en_US_POSIX")
    nameFormatter.timeZone = TimeZone.current
    let stamp = nameFormatter.string(from: Date())
    let pid = getpid()

    func snapshotPathTaken(_ name: String) -> Bool {
        fm.fileExists(atPath: dest + "/" + name) || fm.fileExists(atPath: dest + "/.inprogress-" + name)
    }

    var snapName = "\(stamp)-\(pid)"
    if snapshotPathTaken(snapName) {
        var n = 2
        repeat {
            snapName = "\(stamp)-\(pid)-\(n)"
            n += 1
        } while snapshotPathTaken(snapName)
    }

    let tmp = dest + "/.inprogress-" + snapName
    let final = dest + "/" + snapName
    do {
        try fm.createDirectory(atPath: tmp, withIntermediateDirectories: false)
    } catch {
        log("ERROR: mkdir \(tmp): \(error)")
        return 1
    }

    // Clone file by file (whole-directory clonefile is refused inside iCloud-managed folders).
    // Each file is an APFS copy-on-write clone; falls back to a normal copy if cloning fails.
    var failures = 0
    var fallbacks = 0
    func cloneTree(_ s: String, _ d: String, _ visited: inout Set<DirectoryId>) {
        do {
            try fm.createDirectory(atPath: d, withIntermediateDirectories: true)
        } catch {
            log("ERROR: mkdir \(d): \(error)")
            failures += 1
            return
        }
        guard let items = try? fm.contentsOfDirectory(atPath: s) else {
            log("ERROR: list \(s)")
            failures += 1
            return
        }
        for name in items {
            let sp = s + "/" + name
            let dp = d + "/" + name
            let attrs: [FileAttributeKey: Any]
            do {
                attrs = try fm.attributesOfItem(atPath: sp)
            } catch {
                log("ERROR: attributes \(sp): \(error)")
                failures += 1
                continue
            }
            let fileType = attrs[.type] as? FileAttributeType
            let isSymlink = fileType == .typeSymbolicLink
                || (try? fm.destinationOfSymbolicLink(atPath: sp)) != nil
            if isSymlink {
                if clonefile(sp, dp, UInt32(CLONE_NOFOLLOW)) != 0 {
                    log("ERROR: clonefile \(sp) (errno \(errno))")
                    failures += 1
                }
                continue
            }
            switch fileType {
            case .typeDirectory:
                let sysNum = attrs[.systemNumber] as? NSNumber
                let sysFileNum = attrs[.systemFileNumber] as? NSNumber
                if !WalkPolicy.mayEnter(systemNumber: sysNum, systemFileNumber: sysFileNum, visited: &visited) {
                    if sysNum == nil || sysFileNum == nil {
                        log("ERROR: directory id missing for \(sp)")
                    } else {
                        log("ERROR: cycle \(sp)")
                    }
                    failures += 1
                    continue
                }
                cloneTree(sp, dp, &visited)
            case .typeRegular:
                if clonefile(sp, dp, UInt32(CLONE_NOFOLLOW)) != 0 {
                    let err = errno
                    do {
                        try fm.copyItem(atPath: sp, toPath: dp)
                        log("WARNING: clonefile failed for \(sp) (errno \(err)); full copy")
                        fallbacks += 1
                    } catch {
                        log("ERROR: copy \(sp): \(error)")
                        failures += 1
                    }
                }
            default:
                let typeLabel = fileType.map { String(describing: $0.rawValue) } ?? "unknown"
                log("ERROR: skip special file \(sp) (\(typeLabel))")
                failures += 1
            }
        }
    }
    var visited = Set<DirectoryId>()
    cloneTree(src, tmp, &visited)
    if failures > 0 {
        log("ERROR: \(failures) item(s) failed in \(snapName); not publishing")
        do {
            try fm.removeItem(atPath: tmp)
        } catch {
            log("ERROR: remove \(tmp): \(error)")
        }
        return 1
    }
    do {
        try fm.moveItem(atPath: tmp, toPath: final)
    } catch {
        log("ERROR: rename failed: \(error)")
        return 1
    }
    var count = 0
    if let enumerator = fm.enumerator(atPath: final) {
        while let path = enumerator.nextObject() as? String {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: final + "/" + path, isDirectory: &isDirectory), !isDirectory.boolValue {
                count += 1
            }
        }
    }
    log("OK snapshot \(snapName) (\(count) files, \(fallbacks) full copies)")

    let now = Date()
    let oldParseFormatter = DateFormatter()
    oldParseFormatter.dateFormat = "yyyy-MM-dd_HHmm"
    oldParseFormatter.timeZone = TimeZone.current
    oldParseFormatter.locale = Locale(identifier: "en_US_POSIX")
    oldParseFormatter.isLenient = false
    let newParseFormatter = DateFormatter()
    newParseFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
    newParseFormatter.timeZone = TimeZone.current
    newParseFormatter.locale = Locale(identifier: "en_US_POSIX")
    newParseFormatter.isLenient = false

    func parseSnapshotInstant(_ name: String) -> Date? {
        if SnapshotRetention.isOldFormatCandidate(name) {
            return oldParseFormatter.date(from: name)
        }
        if SnapshotRetention.isNewFormatCandidate(name) {
            let prefix = String(name.prefix(SnapshotRetention.newFormatInstantPrefixLength))
            return newParseFormatter.date(from: prefix)
        }
        return nil
    }

    let dirNames = (try? fm.contentsOfDirectory(atPath: dest)) ?? []
    let names = SnapshotRetention.sortedCandidateNames(dirNames, parseInstant: parseSnapshotInstant)
    let toPrune = SnapshotRetention.namesToPrune(sortedCandidateNames: names, now: now, parseInstant: parseSnapshotInstant)
    for name in toPrune {
        do {
            try fm.removeItem(atPath: dest + "/" + name)
            log("pruned \(name)")
        } catch {
            log("ERROR: prune \(name): \(error)")
        }
    }
    return 0
}
