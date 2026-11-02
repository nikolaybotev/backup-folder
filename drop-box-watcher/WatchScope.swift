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
        watchFolderPresented: URL? = nil,
        eventURL: URL,
        ignorePatterns: [String],
        enumerationOptions: FileManager.DirectoryEnumerationOptions
    ) -> [URL] {
        let fm = FileManager.default
        let eventStandardized = eventURL.standardizedFileURL
        guard fm.fileExists(atPath: eventStandardized.path) else { return [] }

        let scopePath = eventStandardized.resolvingSymlinksInPath().standardizedFileURL.path
        guard isWithinWatchFolder(watchFolder: watchFolder, resolvedStandardizedPath: scopePath) else {
            return []
        }

        let watchResolved = watchFolder.resolvingSymlinksInPath().standardizedFileURL

        if filesystemEqual(eventStandardized, watchResolved)
            || filesystemEqual(eventURL, watchFolder)
            || (watchFolderPresented.map { filesystemEqual(eventStandardized, $0) } ?? false) {
            return walkRegularFiles(
                at: watchResolved,
                watchFolder: watchFolder,
                ignorePatterns: ignorePatterns,
                enumerationOptions: enumerationOptions
            )
        }

        guard let directChild = directChildOfWatchFolder(
            eventURL: eventStandardized,
            watchFolder: watchFolder,
            watchFolderPresented: watchFolderPresented
        ) else {
            return []
        }

        let childKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let childValues = try? directChild.resourceValues(forKeys: childKeys) else { return [] }

        if childValues.isSymbolicLink == true { return [] }

        if childValues.isRegularFile == true, filesystemEqual(directChild, eventStandardized) {
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

    private static func directChildOfWatchFolder(
        eventURL: URL,
        watchFolder: URL,
        watchFolderPresented: URL?
    ) -> URL? {
        var current = eventURL.standardizedFileURL
        while true {
            let parent = current.deletingLastPathComponent()
            if filesystemEqual(parent, watchFolder) {
                return current
            }
            if let presented = watchFolderPresented, filesystemEqual(parent, presented) {
                return current
            }
            if parent.path == current.path || parent.path == "/" {
                return nil
            }
            current = parent
        }
    }

    private static func directoryIdentity(for url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        if let dev = (attrs[.systemNumber] as? NSNumber) ?? (attrs[.deviceIdentifier] as? NSNumber),
           let ino = attrs[.systemFileNumber] as? NSNumber {
            return "\(dev.uint64Value)-\(ino.uint64Value)"
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func walkRegularFiles(
        at root: URL,
        watchFolder: URL,
        ignorePatterns: [String],
        enumerationOptions: FileManager.DirectoryEnumerationOptions
    ) -> [URL] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var seenDirectoryIds: Set<String> = []
        var files: [URL] = []
        var stack = [root.standardizedFileURL]

        while let dir = stack.popLast() {
            let dirScope = dir.resolvingSymlinksInPath().standardizedFileURL.path
            guard isWithinWatchFolder(watchFolder: watchFolder, resolvedStandardizedPath: dirScope) else {
                continue
            }
            guard let dirId = directoryIdentity(for: dir) else { continue }
            if seenDirectoryIds.contains(dirId) { continue }
            seenDirectoryIds.insert(dirId)

            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: Array(keys),
                options: enumerationOptions
            ) else {
                continue
            }

            for url in entries {
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }

                if values.isSymbolicLink == true { continue }

                if values.isDirectory == true {
                    stack.append(url.standardizedFileURL)
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
        }

        return files
    }
}
