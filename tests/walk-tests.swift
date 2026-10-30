import Foundation

@main
struct WalkTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if !condition {
                fputs("FAIL: \(message)\n", stderr)
                failures += 1
            }
        }

        var visited = Set<DirectoryId>()
        let sys = NSNumber(value: 42)
        let ino = NSNumber(value: 1001)

        expect(
            WalkPolicy.mayEnter(systemNumber: sys, systemFileNumber: ino, visited: &visited),
            "first visit should enter"
        )
        expect(visited.count == 1, "visited set should hold one id")

        expect(
            !WalkPolicy.mayEnter(systemNumber: sys, systemFileNumber: ino, visited: &visited),
            "repeat visit should not enter"
        )
        expect(visited.count == 1, "visited set unchanged after repeat")

        expect(
            !WalkPolicy.mayEnter(systemNumber: nil, systemFileNumber: ino, visited: &visited),
            "missing system number should not enter"
        )
        expect(
            !WalkPolicy.mayEnter(systemNumber: sys, systemFileNumber: nil, visited: &visited),
            "missing file number should not enter"
        )

        if failures == 0 {
            print("walk-tests: OK")
        } else {
            fputs("\(failures) failure(s)\n", stderr)
            exit(1)
        }
    }
}
