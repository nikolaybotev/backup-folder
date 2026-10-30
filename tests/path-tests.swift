import Foundation

@main
struct PathTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                fputs("FAIL: \(message)\n", stderr)
                failures += 1
            }
        }

        func expectRefused(_ source: String, _ dest: String, _ label: String) {
            expect(PathContainment.refuses(source: source, dest: dest), "expected refused: \(label)")
        }

        func expectAllowed(_ source: String, _ dest: String, _ label: String) {
            expect(!PathContainment.refuses(source: source, dest: dest), "expected allowed: \(label)")
        }

        // Spec section 1 — refused column
        let table: [(String, String, Bool)] = [
            ("/", "/backups", true),
            ("//", "/backups", true),
            ("///", "/backups", true),
            ("/data/photos//", "/data/photos/backup", true),
            ("/data/photos", "/data/foo/../photos/backup", true),
            ("/tmp/data", "/tmp/data2/../data/backup", true),
            ("/tmp/data", "/tmp/data/backup/../backup", true),
            ("/tmp/foo", "/tmp/foobar", false),
        ]
        for (src, dest, refused) in table {
            let got = PathContainment.refuses(source: src, dest: dest)
            if refused {
                expectRefused(src, dest, "\(src) vs \(dest)")
            } else {
                expectAllowed(src, dest, "\(src) vs \(dest)")
            }
            if got != refused {
                expect(got == refused, "table mismatch \(src) vs \(dest) got=\(got) want=\(refused)")
            }
        }

        let fm = FileManager.default
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("path-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(atPath: root)
        try! fm.createDirectory(atPath: root, withIntermediateDirectories: true)

        defer { try? fm.removeItem(atPath: root) }

        func mkdir(_ rel: String) {
            let p = root + rel
            try! fm.createDirectory(atPath: p, withIntermediateDirectories: true)
        }

        func touch(_ rel: String) {
            let p = root + rel
            try! fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: p, contents: Data(), attributes: nil)
        }

        func symlink(_ rel: String, _ target: String) {
            let p = root + rel
            try! fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try! fm.createSymbolicLink(atPath: p, withDestinationPath: target)
        }

        // Absolute symlink as source; dest inside target
        do {
            mkdir("/abs-src/target/inner")
            symlink("/abs-src-link", root + "/abs-src/target")
            let src = root + "/abs-src-link"
            let dest = root + "/abs-src/target/inner/backup"
            expectRefused(src, dest, "absolute symlink source")
        }

        // Relative symlink as source; dest inside joined target
        do {
            mkdir("/rel-src/real/deep")
            symlink("/rel-src/link", "real")
            let src = root + "/rel-src/link"
            let dest = root + "/rel-src/real/deep/backup"
            expectRefused(src, dest, "relative symlink source")
        }

        // .. after symlink: lexical dest outside source, resolved dest inside
        do {
            mkdir("/lex-out/s/sub")
            mkdir("/lex-out/outside")
            symlink("/lex-out/outside/jump", root + "/lex-out/s/sub")
            let src = root + "/lex-out/s"
            let dest = root + "/lex-out/outside/jump/../sub/backup"
            expectRefused(src, dest, ".. after symlink resolves inside")
        }

        // out symlink to outside: lexical dest inside source, resolved outside — still refused
        do {
            mkdir("/photos-shaped")
            mkdir("/var-outside")
            symlink("/photos-shaped/out", root + "/var-outside")
            let src = root + "/photos-shaped"
            let dest = root + "/photos-shaped/out/backup"
            expectRefused(src, dest, "lexical inside via out symlink")
        }

        // Symlink cycle on source
        do {
            symlink("/cycle-a", root + "/cycle-b")
            symlink("/cycle-b", root + "/cycle-a")
            let src = root + "/cycle-a"
            let dest = root + "/nowhere/backup"
            expectRefused(src, dest, "symlink cycle absolute")
        }

        // Relative symlink cycle
        do {
            mkdir("/rcycle")
            symlink("/rcycle/a", "b")
            symlink("/rcycle/b", "a")
            let src = root + "/rcycle/a"
            let dest = root + "/rcycle/other/backup"
            expectRefused(src, dest, "symlink cycle relative")
        }

        if failures == 0 {
            print("path-tests: OK")
        } else {
            fputs("\(failures) failure(s)\n", stderr)
            exit(1)
        }
    }
}
