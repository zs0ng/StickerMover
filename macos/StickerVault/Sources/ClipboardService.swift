import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardService {
    @discardableResult
    static func copySticker(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let ext = url.pathExtension.lowercased()
        let type: NSPasteboard.PasteboardType
        switch ext {
        case "gif":
            type = .init(UTType.gif.identifier)
        case "png":
            type = .init(UTType.png.identifier)
        case "jpg", "jpeg":
            type = .init(UTType.jpeg.identifier)
        case "webp":
            if #available(macOS 14.0, *) {
                type = .init(UTType.webP.identifier)
            } else {
                type = .init("org.webmproject.webp")
            }
        default:
            type = .init(UTType.data.identifier)
        }

        let item = NSPasteboardItem()
        item.setData(data, forType: type)
        item.setString(url.absoluteString, forType: .fileURL)

        var objects: [NSPasteboardWriting] = [item, url as NSURL]
        if ext != "gif", ext != "webp", let image = NSImage(contentsOf: url) {
            objects.insert(image, at: 0)
        }
        return pasteboard.writeObjects(objects)
    }
}
