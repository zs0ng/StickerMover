import Foundation

enum StickerPlatform: String, CaseIterable, Identifiable {
    case qq = "QQ"
    case wechat = "WeChat"

    var id: String { rawValue }

    var emptyMessage: String {
        switch self {
        case .qq:
            return "No QQ personal emoji found on this Mac yet."
        case .wechat:
            return "No WeChat sticker previews found on this Mac yet."
        }
    }
}

struct StickerItem: Hashable, Identifiable {
    let id: UUID
    let platform: StickerPlatform
    let filename: String
    let sourcePath: String
    let collectionName: String
    let fileSize: Int64

    var displayName: String {
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return name.isEmpty ? filename : name
    }
}

struct StickerScanResult {
    let stickersByPlatform: [StickerPlatform: [StickerItem]]
    let sourceFolderCount: [StickerPlatform: Int]
}

@MainActor
final class StickerStore: ObservableObject {
    @Published private(set) var stickersByPlatform: [StickerPlatform: [StickerItem]] = [
        .qq: [],
        .wechat: [],
    ]
    @Published private(set) var sourceFolderCount: [StickerPlatform: Int] = [
        .qq: 0,
        .wechat: 0,
    ]
    @Published var searchText = ""
    @Published var lastMessage = "Scanning local QQ and WeChat sticker sources..."
    @Published var isScanning = false

    init() {
        refreshDetectedSources()
    }

    func refreshDetectedSources() {
        isScanning = true
        lastMessage = "Scanning local QQ and WeChat sticker sources..."

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StickerSourceScanner().scan()
            }.value

            stickersByPlatform = result.stickersByPlatform
            sourceFolderCount = result.sourceFolderCount
            isScanning = false

            let qqCount = result.stickersByPlatform[.qq, default: []].count
            let wechatCount = result.stickersByPlatform[.wechat, default: []].count
            lastMessage = "Detected \(qqCount) QQ stickers and \(wechatCount) WeChat stickers."
        }
    }

    func stickers(for platform: StickerPlatform) -> [StickerItem] {
        let all = stickersByPlatform[platform, default: []]
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }

        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.filename.localizedCaseInsensitiveContains(query) ||
            $0.collectionName.localizedCaseInsensitiveContains(query)
        }
    }

    func imageURL(for item: StickerItem) -> URL {
        URL(fileURLWithPath: item.sourcePath)
    }

    func sourceSummary(for platform: StickerPlatform) -> String {
        let stickerCount = stickersByPlatform[platform, default: []].count
        let folderCount = sourceFolderCount[platform, default: 0]
        return "\(stickerCount) stickers from \(folderCount) folders"
    }
}
