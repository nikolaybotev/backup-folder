import Darwin
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: clonefile-probe /abs/src /abs/dst\n".data(using: .utf8)!)
    exit(2)
}
let src = CommandLine.arguments[1]
let dst = CommandLine.arguments[2]
if clonefile(src, dst, UInt32(CLONE_NOFOLLOW)) != 0 {
    perror("clonefile")
    exit(1)
}
