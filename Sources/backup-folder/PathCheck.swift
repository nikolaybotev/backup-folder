import Foundation

enum PathContainment {
    /// True when the backup destination must be refused (inside source lexically or after symlink resolution).
    static func refuses(source: String, dest: String) -> Bool {
        let lexSrc = lexicalNormalize(source)
        let lexDest = lexicalNormalize(dest)
        if isInside(normalizedSource: lexSrc, normalizedDest: lexDest) {
            return true
        }
        switch resolvePath(source) {
        case .cycle:
            return true
        case .path(let resSrc):
            switch resolvePath(dest) {
            case .cycle:
                return true
            case .path(let resDest):
                return isInside(normalizedSource: resSrc, normalizedDest: resDest)
            }
        }
    }

    // MARK: - Lexical normalize (compare only; not fed into the symlink walk)

    static func lexicalNormalize(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        if p == "/" || p.isEmpty {
            return "/"
        }
        var stack: [String] = []
        for comp in p.split(separator: "/", omittingEmptySubsequences: false) {
            if comp.isEmpty || comp == "." {
                continue
            }
            if comp == ".." {
                if !stack.isEmpty {
                    stack.removeLast()
                }
                continue
            }
            stack.append(String(comp))
        }
        if stack.isEmpty {
            return "/"
        }
        return "/" + stack.joined(separator: "/")
    }

    // MARK: - Inside (P3)

    static func isInside(normalizedSource source: String, normalizedDest dest: String) -> Bool {
        if dest == source {
            return true
        }
        if source == "/" {
            return true
        }
        return dest.hasPrefix(source + "/")
    }

    // MARK: - Symlink resolution walk

    enum ResolveResult {
        case path(String)
        case cycle
    }

    static func resolvePath(_ path: String) -> ResolveResult {
        let components = walkComponents(fromAbsolute: path)
        return resolveWalk(remaining: components, stack: [], expanding: [])
    }

    /// Components for the walk: trailing slashes stripped; empty and `.` skipped; `..` kept.
    private static func walkComponents(fromAbsolute path: String) -> [String] {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p = String(p.dropLast())
        }
        if p == "/" || p.isEmpty {
            return []
        }
        var out: [String] = []
        for comp in p.split(separator: "/", omittingEmptySubsequences: false) {
            if comp.isEmpty || comp == "." {
                continue
            }
            out.append(String(comp))
        }
        return out
    }

    private static func walkComponentsFromRelative(_ target: String) -> [String] {
        var out: [String] = []
        for comp in target.split(separator: "/", omittingEmptySubsequences: false) {
            if comp.isEmpty || comp == "." {
                continue
            }
            out.append(String(comp))
        }
        return out
    }

    private static func resolveWalk(
        remaining: [String],
        stack: [String],
        expanding: [String]
    ) -> ResolveResult {
        var comps = remaining
        var st = stack
        let fm = FileManager.default

        while !comps.isEmpty {
            let comp = comps.removeFirst()
            if comp == ".." {
                if !st.isEmpty {
                    st.removeLast()
                }
                continue
            }

            let candidate = absolutePath(stack: st, component: comp)

            let linkTarget: String?
            do {
                linkTarget = try fm.destinationOfSymbolicLink(atPath: candidate)
            } catch {
                linkTarget = nil
            }

            if linkTarget == nil {
                st.append(comp)
                continue
            }

            if expanding.contains(candidate) {
                return .cycle
            }

            let target = linkTarget!
            let injected: [String]
            let newStack: [String]
            if target.hasPrefix("/") {
                newStack = []
                injected = walkComponents(fromAbsolute: target)
            } else {
                newStack = st
                injected = walkComponentsFromRelative(target)
            }
            let newExpanding = expanding + [candidate]
            return resolveWalk(
                remaining: injected + comps,
                stack: newStack,
                expanding: newExpanding
            )
        }

        if st.isEmpty {
            return .path("/")
        }
        return .path("/" + st.joined(separator: "/"))
    }

    private static func absolutePath(stack: [String], component: String) -> String {
        if stack.isEmpty {
            return "/" + component
        }
        return "/" + stack.joined(separator: "/") + "/" + component
    }
}
