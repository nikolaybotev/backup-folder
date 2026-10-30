// Generic hourly APFS-clone snapshot: backup-folder <source-dir> <backup-dir>
// (copy of an earlier backup script with the two paths taken from arguments).
// Does everything in-process (no shell), so a Full Disk Access grant applies to this binary only.
// Retention: every snapshot for 48h, then the first snapshot of each day up to 60 days.
import Foundation
import Darwin

let args = CommandLine.arguments
guard args.count == 3, args[1].hasPrefix("/"), args[2].hasPrefix("/") else {
    FileHandle.standardError.write("usage: backup-folder /abs/source /abs/backup-dir\n".data(using: .utf8)!); exit(2)
}
let src = args[1].hasSuffix("/") ? String(args[1].dropLast()) : args[1]
let dest = args[2].hasSuffix("/") ? String(args[2].dropLast()) : args[2]
if dest == src || dest.hasPrefix(src + "/") {
    FileHandle.standardError.write("backup dir must not be inside source\n".data(using: .utf8)!); exit(2)
}
let logPath = dest + "/backup.log"
let fm = FileManager.default

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
    let line = "\(f.string(from: Date())) \(s)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
}

do {
    try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write("ERROR: cannot create \(dest): \(error)\n".data(using: .utf8)!); exit(1)
}

guard (try? fm.contentsOfDirectory(atPath: src)) != nil else {
    log("ERROR: cannot read \(src) (Full Disk Access?)"); exit(1)
}

let lockPath = dest + "/.backup-folder.lock"
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
if lockFD < 0 {
    log("ERROR: cannot open lock \(lockPath) (errno \(errno))"); exit(1)
}
defer { close(lockFD) }
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    if errno == EWOULDBLOCK {
        log("skipped; dest busy")
        exit(0)
    }
    log("ERROR: flock \(lockPath) (errno \(errno))"); exit(1)
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
    log("ERROR: mkdir \(tmp): \(error)"); exit(1)
}

// Clone file by file (whole-directory clonefile is refused inside iCloud-managed folders).
// Each file is an APFS copy-on-write clone; falls back to a normal copy if cloning fails.
var failures = 0
var fallbacks = 0
func cloneTree(_ s: String, _ d: String) {
    do { try fm.createDirectory(atPath: d, withIntermediateDirectories: true) } catch { log("ERROR: mkdir \(d): \(error)"); failures += 1; return }
    guard let items = try? fm.contentsOfDirectory(atPath: s) else { log("ERROR: list \(s)"); failures += 1; return }
    for name in items {
        let sp = s + "/" + name, dp = d + "/" + name
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sp, isDirectory: &isDir) else { continue }
        if isDir.boolValue { cloneTree(sp, dp); continue }
        if clonefile(sp, dp, UInt32(CLONE_NOFOLLOW)) != 0 {
            let err = errno
            do {
                try fm.copyItem(atPath: sp, toPath: dp)
                log("WARNING: clonefile failed for \(sp) (errno \(err)); full copy")
                fallbacks += 1
            } catch { log("ERROR: copy \(sp): \(error)"); failures += 1 }
        }
    }
}
cloneTree(src, tmp)
if failures > 0 {
    log("ERROR: \(failures) item(s) failed in \(snapName); not publishing")
    do { try fm.removeItem(atPath: tmp) } catch { log("ERROR: remove \(tmp): \(error)") }
    exit(1)
}
do { try fm.moveItem(atPath: tmp, toPath: final) } catch { log("ERROR: rename failed: \(error)"); exit(1) }
var count = 0
if let e = fm.enumerator(atPath: final) { while let p = e.nextObject() as? String { var d: ObjCBool = false; if fm.fileExists(atPath: final + "/" + p, isDirectory: &d), !d.boolValue { count += 1 } } }
log("OK snapshot \(snapName) (\(count) files, \(fallbacks) full copies)")

// Prune
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
for n in toPrune {
    do { try fm.removeItem(atPath: dest + "/" + n); log("pruned \(n)") } catch { log("ERROR: prune \(n): \(error)") }
}
