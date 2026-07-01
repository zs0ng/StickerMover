import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct StickerVaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = StickerStore()

    var body: some Scene {
        MenuBarExtra("StickerVault", systemImage: "face.smiling.inverse") {
            StickerVaultView(store: store)
                .frame(minWidth: 420, minHeight: 520)
        }
        .menuBarExtraStyle(.window)
    }
}

struct StickerVaultView: View {
    @ObservedObject var store: StickerStore
    @State private var selectedPlatform: StickerPlatform = .all
    private let columns = [GridItem(.adaptive(minimum: 84, maximum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            header
            searchBar
            statusBar
            platformTabs
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("StickerVault")
                    .font(.title3.weight(.semibold))
                Text("Auto-detected sticker sources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            Button("Refresh") {
                store.refreshDetectedSources()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var searchBar: some View {
        TextField("Search stickers", text: $store.searchText)
            .textFieldStyle(.roundedBorder)
    }

    private var statusBar: some View {
        HStack {
            Text(store.lastMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(store.sourceSummary(for: selectedPlatform))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var platformTabs: some View {
        TabView(selection: $selectedPlatform) {
            platformGrid(.all)
                .tabItem { Text("All") }
                .tag(StickerPlatform.all)
            platformGrid(.qq)
                .tabItem { Text("QQ") }
                .tag(StickerPlatform.qq)
            platformGrid(.wechat)
                .tabItem { Text("WeChat") }
                .tag(StickerPlatform.wechat)
            platformGrid(.telegram)
                .tabItem { Text("Telegram") }
                .tag(StickerPlatform.telegram)
            platformGrid(.whatsapp)
                .tabItem { Text("WhatsApp") }
                .tag(StickerPlatform.whatsapp)
        }
    }

    private func platformGrid(_ platform: StickerPlatform) -> some View {
        let items = store.stickers(for: platform)

        return Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: platformSymbol(for: platform))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(platform.emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(platform == .all ? "Click Refresh to rescan local sticker sources." : "Click Refresh after opening \(platform.rawValue) at least once on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            StickerCell(
                                item: item,
                                sourceURL: store.sourceURL(for: item),
                                previewURL: store.previewURL(for: item)
                            ) {
                                if ClipboardService.copySticker(at: store.sourceURL(for: item)) {
                                    store.lastMessage = "Copied \(item.displayName) from \(platform.rawValue)."
                                } else {
                                    store.lastMessage = "Failed to copy \(item.displayName)."
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func platformSymbol(for platform: StickerPlatform) -> String {
        switch platform {
        case .all:
            return "square.grid.2x2"
        case .qq:
            return "bubble.left.and.bubble.right"
        case .wechat:
            return "message"
        case .telegram:
            return "paperplane"
        case .whatsapp:
            return "phone.bubble"
        }
    }
}

struct StickerCell: View {
    let item: StickerItem
    let sourceURL: URL
    let previewURL: URL
    let onCopy: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
                if let image = NSImage(contentsOf: previewURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 86)
            .help("Click to copy to clipboard, or drag the file into a chat app")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.collectionName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.fileTypeLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture(perform: onCopy)
        .onDrag {
            NSItemProvider(contentsOf: sourceURL) ?? NSItemProvider()
        }
        .help("Click to copy to clipboard, or drag the file into a chat app")
    }
}
