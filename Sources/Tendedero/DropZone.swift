import AppKit

/// Accepts image files (and raw image pasteboard data) dropped onto the line
/// so they hang the same way as "Hang on Tendedero" from Finder's Services.
final class DropZone: NSView {
    /// True while an external drag is over this view; AppDelegate uses it so
    /// the panel stops ignoring mouse events for the whole strip.
    static private(set) var isReceiving = false

    var onDrop: (([URL]) -> Bool)?
    var onDragSession: ((Bool) -> Void)?

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp", "bmp"
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        subviews.forEach { $0.frame = bounds }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.canAccept(sender) else { return [] }
        Self.isReceiving = true
        onDragSession?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        Self.isReceiving = false
        onDragSession?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        Self.canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            Self.isReceiving = false
            onDragSession?(false)
        }
        let urls = Self.materializeImageURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        return onDrop?(urls) ?? false
    }

    /// True when the drag pasteboard carries at least one image file or image bits.
    static func dragLooksLikeImages() -> Bool {
        canAccept(NSPasteboard(name: .drag))
    }

    private static func canAccept(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender.draggingPasteboard)
    }

    private static func canAccept(_ pb: NSPasteboard) -> Bool {
        !fileImageURLs(from: pb).isEmpty || pb.availableType(from: [.png, .tiff]) != nil
    }

    private static func fileImageURLs(from pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  !isDir.boolValue else { return false }
            return imageExtensions.contains(url.pathExtension.lowercased())
        }
    }

    /// File URLs when present; otherwise write pasteboard image bits to a temp file.
    private static func materializeImageURLs(from pb: NSPasteboard) -> [URL] {
        let files = fileImageURLs(from: pb)
        if !files.isEmpty { return files }
        // WeChat / browser / Preview often drag raw image bits with no file URL.
        let isPNG = pb.data(forType: .png) != nil
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return [] }
        let ext = isPNG ? "png" : "tiff"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TendederoDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "drop-\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return [url]
        } catch {
            return []
        }
    }
}
