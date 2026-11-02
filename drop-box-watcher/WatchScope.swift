import Foundation

/// Foundation-only watch scope and candidate selection (FR1–FR2). No CoreServices, no sleep, no iCloud download.
enum WatchScope {
    private static func stripPrivatePrefix(_ path: String) -> String {
        if path.hasPrefix("/private") { return String(path.dropFirst("/private".count)) }
        return path
    }

    static func filesystemEqual(_ a: URL, _ b: URL) -> Bool {
        let pa = a.resolvingSymlinksInPath().standardizedFileURL.path
        let pb = b.resolvingSymlinksInPath().standardizedFileURL.path
        if pa == pb { return true }
        return stripPrivatePrefix(pa) == stripPrivatePrefix(pb)
    }

    /// FR1: resolved watch folder or descendant with boundary slash; `/private` stripped on both sides.
    static func isWithinWatchFolder(watchFolder: URL, resolvedStandardizedPath path: String) -> Bool {
        let watch = stripPrivatePrefix(
            watchFolder.resolvingSymlinksInPath().standardizedFileURL.path
        )
        let candidate = stripPrivatePrefix(path)
        if candidate == watch { return true }
        if watch == "/" { return true }
        return candidate.hasPrefix(watch + "/")
    }

    /// Returns regular-file URLs to recheck this pass (FR2). Does not claim or coordinate.
    static func candidateRegularFiles(
        watchFolder: URL,
        eventURL: URL,
        ignorePatterns: [String],
        enumerationOptions: FileManager.DirectoryEnumerationOptions
    ) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: eventURL.path) else { return [] }

        let scopePath = eventURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard isWithinWatchFolder(watchFolder: watchFolder, resolvedStandardizedPath: scopePath) else {
            return []
        }

        let watchResolved = watchFolder.resolvingSymlinksInPath().standardizedFileURL

        if filesystemEqual(eventURL.standardizedFileURL, watchResolved)
            || filesystemEqual(eventURL, watchFolder) {
            return walkRegularFiles(
                at: watchResolved,
                watchFolder: watchFolder,
                ignorePatterns: ignorePatterns,
                enumerationOptions: enumerationOptions
            )
        }

        guard let directChild = directChildOfWatchFolder(eventURL: eventURL, watchFolder: watchFolder) else {
            return []
        }

        let childKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let childValues = try? directChild.resourceValues(forKeys: childKeys) else { return [] }

        if childValues.isSymbolicLink == true { return [] }

        if childValues.isRegularFile == true, filesystemEqual(directChild, eventURL) {
            let name = directChild.lastPathComponent
            if nameMatchesAnyIgnorePattern(name, patterns: ignorePatterns) { return [] }
            return [directChild.standardizedFileURL]
        }

        guard childValues.isDirectory == true else { return [] }

        return walkRegularFiles(
            at: directChild.standardizedFileURL,
            watchFolder: watchFolder,
            ignorePatterns: ignorePatterns,
            enumerationOptions: enumerationOptions
        )
    }

    private static func directChildOfWatchFolder(eventURL: URL, watchFolder: URL) -> URL? {
        var current = eventURL.standardizedFileURL
        while true {
            let parent = current.deletingLastPathComponent()
            if filesystemEqual(parent, watchFolder) {
                return current
            }
            if parent.path == current.path || parent.path == "/" {
                return nil
            }
            current = parent
        }
    }

    private static func walkRegularFiles(
        at root: URL,
        watchFolder: URL,
        ignorePatterns: [String],
        enumerationOptions: FileManager.DirectoryEnumerationOptions
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: enumerationOptions
        ) else {
            return []
        }

        var seenDirectoryIds: Set<String> = []
        var files: [URL] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            if values.isDirectory == true {
                let scopePath = url.resolvingSymlinksInPath().standardizedFileURL.path
                if !isWithinWatchFolder(watchFolder: watchFolder, resolvedStandardizedPath: scopePath) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let dev = (attrs[.systemNumber] as? NSNumber) ?? (attrs[.deviceIdentifier] as? NSNumber),
                      let ino = attrs[.systemFileNumber] as? NSNumber
                else {
                    enumerator.skipDescendants()
                    continue
                }
                let dirId = "\(dev.uint64Value)-\(ino.uint64Value)"
                if seenDirectoryIds.contains(dirId) {
                    enumerator.skipDescendants()
                    continue
                }
                seenDirectoryIds.insert(dirId)
                continue
            }

            if values.isRegularFile != true { continue }

            let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
            if !isWithinWatchFolder(watchFolder: watchFolder, resolvedStandardizedPath: filePath) {
                continue
            }

            let name = url.lastPathComponent
            if nameMatchesAnyIgnorePattern(name, patterns: ignorePatterns) { continue }
            files.append(url.standardizedFileURL)
        }

        return files
    }
}
