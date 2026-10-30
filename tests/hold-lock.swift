// Hold dest/.backup-folder.lock for macOS smoke (non-blocking skip test).
import Foundation
import Darwin

let args = CommandLine.arguments
guard args.count == 2, args[1].hasPrefix("/") else {
    fputs("usage: hold-lock /abs/backup-dir\n", stderr)
    exit(2)
}
let dest = args[1].hasSuffix("/") ? String(args[1].dropLast()) : args[1]
let lockPath = dest + "/.backup-folder.lock"
let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
if fd < 0 {
    fputs("hold-lock: open failed errno \(errno)\n", stderr)
    exit(1)
}
defer { close(fd) }
if flock(fd, LOCK_EX) != 0 {
    fputs("hold-lock: flock failed errno \(errno)\n", stderr)
    exit(1)
}
// Hold until smoke test sends SIGTERM.
while true {
    sleep(3600)
}
