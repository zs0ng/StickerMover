import CryptoKit
import Foundation

struct StickerSourceScanner {
    private let fileManager = FileManager.default
    private let allowedExtensions = Set(["png", "jpg", "jpeg", "gif", "webp"])
    private let normalizedRoot: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        normalizedRoot = appSupport.appendingPathComponent("StickerVault/Normalized", isDirectory: true)
        try? fileManager.createDirectory(at: normalizedRoot, withIntermediateDirectories: true)
    }

    func scan() -> StickerScanResult {
        var stickersByPlatform: [StickerPlatform: [StickerItem]] = [
            .all: [],
            .qq: [],
            .wechat: [],
            .telegram: [],
            .whatsapp: [],
        ]
        var sourceFolderCount: [StickerPlatform: Int] = [
            .all: 0,
            .qq: 0,
            .wechat: 0,
            .telegram: 0,
            .whatsapp: 0,
        ]

        let qqRoots = qqCandidateRoots()
        sourceFolderCount[.qq] = qqRoots.count
        for root in qqRoots {
            stickersByPlatform[.qq, default: []].append(
                contentsOf: scanFiles(in: root, platform: .qq, collectionName: root.lastPathComponent)
            )
        }

        let wechatRecovery = WeChatRecoveryService()
        let wechatResult = wechatRecovery.preparedRecoveredRoots()
        sourceFolderCount[.wechat] = wechatResult.sourceRootCount
        stickersByPlatform[.wechat] = normalizedWeChatStickers(from: wechatResult.roots)

        let telegramRoots = telegramCandidateRoots()
        sourceFolderCount[.telegram] = telegramRoots.count
        stickersByPlatform[.telegram] = normalizedTelegramStickers(from: telegramRoots)

        let whatsappRoots = whatsappCandidateRoots()
        sourceFolderCount[.whatsapp] = whatsappRoots.count
        for root in whatsappRoots {
            stickersByPlatform[.whatsapp, default: []].append(
                contentsOf: scanFiles(in: root, platform: .whatsapp, collectionName: root.lastPathComponent)
            )
        }

        stickersByPlatform[.all] =
            stickersByPlatform[.qq, default: []] +
            stickersByPlatform[.wechat, default: []] +
            stickersByPlatform[.telegram, default: []] +
            stickersByPlatform[.whatsapp, default: []]
        sourceFolderCount[.all] =
            sourceFolderCount[.qq, default: 0] +
            sourceFolderCount[.wechat, default: 0] +
            sourceFolderCount[.telegram, default: 0] +
            sourceFolderCount[.whatsapp, default: 0]

        for platform in StickerPlatform.allCases {
            stickersByPlatform[platform] = stickersByPlatform[platform, default: []]
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }

        return StickerScanResult(
            stickersByPlatform: stickersByPlatform,
            sourceFolderCount: sourceFolderCount
        )
    }

    private func normalizedWeChatStickers(from roots: [URL]) -> [StickerItem] {
        var items: [StickerItem] = []
        var seenHashes = Set<String>()
        let cacheRoot = normalizedRoot.appendingPathComponent("WeChat", isDirectory: true)
        try? fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true else { continue }
                guard let kind = imageKind(for: fileURL) else { continue }
                guard let digest = sha256(for: fileURL) else { continue }
                guard seenHashes.insert(digest).inserted else { continue }

                let cachedURL = normalizedURL(in: cacheRoot, digest: digest, kind: kind)
                if !fileManager.fileExists(atPath: cachedURL.path) {
                    try? fileManager.copyItem(at: fileURL, to: cachedURL)
                }

                items.append(
                    StickerItem(
                        id: UUID(),
                        platform: .wechat,
                        filename: cachedURL.lastPathComponent,
                        sourcePath: cachedURL.path,
                        previewPath: cachedURL.path,
                        collectionName: root.lastPathComponent,
                        fileSize: Int64(values?.fileSize ?? 0)
                    )
                )
            }
        }

        return items
    }

    private func qqCandidateRoots() -> [URL] {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QQ", isDirectory: true)

        guard let children = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { $0.lastPathComponent.hasPrefix("nt_qq_") }
            .map { $0.appendingPathComponent("nt_data/Emoji/personal_emoji/Ori", isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func whatsappCandidateRoots() -> [URL] {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/stickers", isDirectory: true)

        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }
        return [root]
    }

    private func telegramCandidateRoots() -> [URL] {
        let base = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore", isDirectory: true)

        guard let children = try? fileManager.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { $0.lastPathComponent.hasPrefix("account-") }
            .map { $0.appendingPathComponent("postbox/media", isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }

    private func scanFiles(in root: URL, platform: StickerPlatform, collectionName: String) -> [StickerItem] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [StickerItem] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            guard imageKind(for: fileURL) != nil else { continue }

            items.append(
                StickerItem(
                    id: UUID(),
                    platform: platform,
                    filename: fileURL.lastPathComponent,
                    sourcePath: fileURL.path,
                    previewPath: fileURL.path,
                    collectionName: collectionName,
                    fileSize: Int64(values?.fileSize ?? 0)
                )
            )
        }

        return items
    }

    private func normalizedTelegramStickers(from roots: [URL]) -> [StickerItem] {
        let recovery = TelegramRecoveryService()
        let manifests = recovery.preparedManifestURLs(from: roots)
        var items: [StickerItem] = []

        for manifestURL in manifests {
            guard
                let data = try? Data(contentsOf: manifestURL),
                let manifest = try? JSONDecoder().decode(TelegramRecoveryManifest.self, from: data)
            else {
                continue
            }

            let collectionName = manifestURL.deletingLastPathComponent().lastPathComponent
            for entry in manifest.items {
                guard let previewOutput = entry.previewOutput else { continue }
                items.append(
                    StickerItem(
                        id: UUID(),
                        platform: .telegram,
                        filename: URL(fileURLWithPath: entry.stickerOutput).lastPathComponent,
                        sourcePath: entry.stickerOutput,
                        previewPath: previewOutput,
                        collectionName: collectionName,
                        fileSize: Int64(entry.size)
                    )
                )
            }
        }

        return items
    }

    private func imageKind(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 32)

        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) {
            return "png"
        }
        if data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8)) {
            return "gif"
        }
        if data.starts(with: Data([0xFF, 0xD8, 0xFF])) {
            return "jpg"
        }
        if data.starts(with: Data("RIFF".utf8)) && data.dropFirst(8).starts(with: Data("WEBP".utf8)) {
            return "webp"
        }
        let ext = url.pathExtension.lowercased()
        return allowedExtensions.contains(ext) ? ext : nil
    }

    private func normalizedURL(in root: URL, digest: String, kind: String) -> URL {
        root.appendingPathComponent("\(digest).\(kind)", isDirectory: false)
    }

    private func sha256(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct WeChatRecoveryResult {
    let roots: [URL]
    let sourceRootCount: Int
}

private struct TelegramRecoveryManifest: Decodable {
    struct Item: Decodable {
        let stickerOutput: String
        let previewOutput: String?
        let size: Int

        private enum CodingKeys: String, CodingKey {
            case stickerOutput = "sticker_output"
            case previewOutput = "preview_output"
            case size
        }
    }

    let items: [Item]
}

private struct WeChatRecoveryService {
    private let fileManager = FileManager.default
    private let appSupportRoot: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportRoot = appSupport.appendingPathComponent("StickerVault/Recovered/WeChat", isDirectory: true)
        try? fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
    }

    func preparedRecoveredRoots() -> WeChatRecoveryResult {
        let sourceRoots = wechatSourceRoots()
        let recoveredRoot = appSupportRoot.appendingPathComponent("images", isDirectory: true)

        if containsFiles(in: recoveredRoot) {
            return WeChatRecoveryResult(roots: [recoveredRoot], sourceRootCount: sourceRoots.count)
        }

        guard !sourceRoots.isEmpty else {
            return WeChatRecoveryResult(roots: [], sourceRootCount: 0)
        }

        let exportRoot = appSupportRoot.appendingPathComponent("export", isDirectory: true)
        try? fileManager.removeItem(at: exportRoot)
        try? fileManager.removeItem(at: recoveredRoot)
        try? fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: recoveredRoot, withIntermediateDirectories: true)

        guard
            let exportScript = locateScript(named: "mememover_export.py"),
            let recoverScript = locateScript(named: "download_wechat_favorites.py")
        else {
            return WeChatRecoveryResult(roots: [], sourceRootCount: sourceRoots.count)
        }

        for sourceRoot in sourceRoots {
            let exportOut = exportRoot.appendingPathComponent(sourceRoot.lastPathComponent, isDirectory: true)
            let exportOK = runProcess(
                executable: "/usr/bin/env",
                arguments: ["python3", exportScript.path, sourceRoot.path, "--output-dir", exportOut.path]
            )
            guard exportOK else { continue }

            let favoritesJSON = exportOut.appendingPathComponent("favorites.json", isDirectory: false)
            guard fileManager.fileExists(atPath: favoritesJSON.path) else { continue }

            let manifest = exportOut.appendingPathComponent("recovered_manifest.json", isDirectory: false)
            _ = runProcess(
                executable: "/usr/bin/env",
                arguments: [
                    "python3",
                    recoverScript.path,
                    favoritesJSON.path,
                    "--output-dir",
                    recoveredRoot.path,
                    "--manifest",
                    manifest.path,
                ]
            )
        }

        if containsFiles(in: recoveredRoot) {
            return WeChatRecoveryResult(roots: [recoveredRoot], sourceRootCount: sourceRoots.count)
        }
        return WeChatRecoveryResult(roots: [], sourceRootCount: sourceRoots.count)
    }

    private func wechatSourceRoots() -> [URL] {
        let supportBase = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat",
                isDirectory: true
            )

        guard let versionDirs = try? fileManager.contentsOfDirectory(
            at: supportBase,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for versionDir in versionDirs {
            guard let accountDirs = try? fileManager.contentsOfDirectory(
                at: versionDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for accountDir in accountDirs {
                let stickersRoot = accountDir.appendingPathComponent("Stickers", isDirectory: true)
                let persistence = stickersRoot.appendingPathComponent("Persistence", isDirectory: true)
                let thumbs = stickersRoot.appendingPathComponent("Thumbs", isDirectory: true)
                let archive = stickersRoot.appendingPathComponent("fav.archive", isDirectory: false)
                if fileManager.fileExists(atPath: persistence.path),
                   fileManager.fileExists(atPath: thumbs.path),
                   fileManager.fileExists(atPath: archive.path)
                {
                    results.append(stickersRoot)
                }
            }
        }

        return results.sorted { $0.path < $1.path }
    }

    private func locateScript(named filename: String) -> URL? {
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var searchBases: [URL] = [cwd]
        var cursor = cwd
        for _ in 0..<6 {
            cursor.deleteLastPathComponent()
            searchBases.append(cursor)
        }

        for base in searchBases {
            let candidate = base.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func containsFiles(in root: URL) -> Bool {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return true
            }
        }
        return false
    }

    private func runProcess(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private struct TelegramRecoveryService {
    private let fileManager = FileManager.default
    private let appSupportRoot: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportRoot = appSupport.appendingPathComponent("StickerVault/Recovered/Telegram", isDirectory: true)
        try? fileManager.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)
    }

    func preparedManifestURLs(from roots: [URL]) -> [URL] {
        guard let recoverScript = locateScript(named: "recover_telegram_stickers.py") else {
            return []
        }

        var manifests: [URL] = []
        for root in roots {
            let accountName = root.deletingLastPathComponent().lastPathComponent
            let accountRoot = appSupportRoot.appendingPathComponent(accountName, isDirectory: true)
            let manifestURL = accountRoot.appendingPathComponent("manifest.json", isDirectory: false)

            try? fileManager.removeItem(at: accountRoot)
            try? fileManager.createDirectory(at: accountRoot, withIntermediateDirectories: true)
            _ = runProcess(
                executable: "/usr/bin/env",
                arguments: ["python3", recoverScript.path, root.path, "--output-dir", accountRoot.path]
            )

            if fileManager.fileExists(atPath: manifestURL.path) {
                manifests.append(manifestURL)
            }
        }

        return manifests.sorted { $0.path < $1.path }
    }

    private func locateScript(named filename: String) -> URL? {
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var searchBases: [URL] = [cwd]
        var cursor = cwd
        for _ in 0..<6 {
            cursor.deleteLastPathComponent()
            searchBases.append(cursor)
        }

        for base in searchBases {
            let candidate = base.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func runProcess(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
