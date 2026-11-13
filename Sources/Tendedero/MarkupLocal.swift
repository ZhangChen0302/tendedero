import AppKit
import Darwin
import ObjectiveC
import os

@_silgen_name("TendederoCatchException")
private func TendederoCatchException(_ block: @convention(block) () -> Void, _ error: NSErrorPointer) -> Bool

/// Hosts Apple's in-process Markup editor (`MarkupViewController` in the
/// private MarkupUI framework) in a normal Tendedero window. Command-Z then
/// reaches a local undo stack, instead of being sent into the Markup sharing
/// extension's NSRemoteView, which crashes the host.
@MainActor
final class LocalMarkupSession: NSObject, NSWindowDelegate {
    private let url: URL
    private let controller: NSViewController
    private let onSave: (Data) -> Void
    private let onCancel: () -> Void

    private var window: NSWindow?
    private var previousMenu: NSMenu?
    private var keyMonitor: Any?
    private var closing = false

    static func open(url: URL, onSave: @escaping (Data) -> Void, onCancel: @escaping () -> Void) -> LocalMarkupSession? {
        guard MarkupUI.load(), let controller = MarkupUI.makeController(toolbar: true) else {
            return nil
        }
        MarkupUI.setHostBundle(controller, Bundle.main.bundleIdentifier)
        let session = LocalMarkupSession(url: url, controller: controller, onSave: onSave, onCancel: onCancel)
        // The image must be loaded only after the controller's view is in a
        // window. setFileURL: earlier throws: MarkupUI pins MUImageView
        // anchors that do not exist yet, and AppKit swallows the exception
        // so the editor never appears.
        guard session.present() else { return nil }
        return session
    }

    private init(url: URL, controller: NSViewController, onSave: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
        self.url = url
        self.controller = controller
        self.onSave = onSave
        self.onCancel = onCancel
        super.init()
    }

    @discardableResult
    private func present() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.deletingPathExtension().lastPathComponent
        window.contentViewController = controller
        window.delegate = self
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 480, height: 320)
        window.layoutIfNeeded()
        self.window = window

        var loadError: NSError?
        let loaded = TendederoCatchException({ MarkupUI.setFileURL(self.controller, self.url) }, &loadError)
        if !loaded {
            log.error("Markup setFileURL failed: \(loadError?.localizedDescription ?? "unknown", privacy: .public)")
            window.delegate = nil
            window.orderOut(nil)
            self.window = nil
            return false
        }

        addButtons(to: window)
        sizeAndCenter(window)
        installEditMenu()
        installKeyMonitor()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.view)
        return true
    }

    private func addButtons(to window: NSWindow) {
        let cancel = titlebarButton(title: L("Cancel"), keyEquivalent: "\u{1b}", action: #selector(cancelClicked), trailing: false)
        let done = titlebarButton(title: L("Done"), keyEquivalent: "", action: #selector(doneClicked), trailing: true)
        window.addTitlebarAccessoryViewController(cancel)
        window.addTitlebarAccessoryViewController(done)
    }

    private func titlebarButton(title: String, keyEquivalent: String, action: Selector, trailing: Bool) -> NSTitlebarAccessoryViewController {
        let height: CGFloat = 28
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .accessoryBarAction
        button.keyEquivalent = keyEquivalent
        button.setButtonType(.momentaryPushIn)
        button.sizeToFit()
        var buttonFrame = button.frame
        buttonFrame.size.height = 22
        buttonFrame.size.width = max(buttonFrame.width + 10, 64)
        let width = buttonFrame.width + 16
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        button.frame = NSRect(
            x: trailing ? 2 : 8,
            y: ((height - buttonFrame.height) / 2).rounded(),
            width: buttonFrame.width,
            height: buttonFrame.height
        )
        holder.addSubview(button)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = holder
        accessory.layoutAttribute = trailing ? .right : .left
        return accessory
    }

    private func sizeAndCenter(_ window: NSWindow) {
        let imageSize = NSImage(contentsOf: url)?.size ?? NSSize(width: 640, height: 400)
        var content = NSSize(width: imageSize.width + 48, height: imageSize.height + 120)
        let area = LinePanel.screenUnderPointer()?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let area {
            content.width = min(max(content.width, 520), area.width * 0.86)
            content.height = min(max(content.height, 360), area.height * 0.86)
            window.setContentSize(content)
            let frame = window.frame
            window.setFrameOrigin(NSPoint(
                x: (area.midX - frame.width / 2).rounded(),
                y: (area.midY - frame.height / 2).rounded()
            ))
        } else {
            window.setContentSize(content)
            window.center()
        }
    }

    private func installEditMenu() {
        previousMenu = NSApp.mainMenu
        let edit = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(undo)
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Delete", action: NSSelectorFromString("delete:"), keyEquivalent: ""))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let bar = NSMenu()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    /// Sends undo/redo to the in-process controller. This is a local method
    /// call, not a key event into a remote view, so it does not trip ViewBridge.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
        guard commandOnly, event.charactersIgnoringModifiers?.lowercased() == "z" else { return event }
        let name = flags.contains(.shift) ? "redo:" : "undo:"
        let sel = NSSelectorFromString(name)
        if controller.responds(to: sel) {
            _ = controller.perform(sel, with: nil)
            return nil
        }
        return event
    }

    @objc private func cancelClicked() {
        finish(save: false)
    }

    @objc private func doneClicked() {
        finish(save: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWithoutSaving()
        return false
    }

    /// Closes the editor without writing back, if it is still open.
    func closeWithoutSaving() {
        finish(save: false)
    }

    private func finish(save: Bool) {
        guard !closing else { return }
        if save {
            guard let data = MarkupUI.dataRepresentation(of: controller) else {
                NSSound.beep()
                log.error("Local Markup had nothing to write back")
                return
            }
            closing = true
            teardown()
            onSave(data)
        } else {
            closing = true
            teardown()
            onCancel()
        }
    }

    private func teardown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NSApp.mainMenu = previousMenu
        previousMenu = nil
        MarkupUI.teardown(controller)
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
    }
}

/// Runtime access to private MarkupUI types. The framework is loaded with
/// `dlopen`; nothing is linked at compile time, so a missing class on a
/// future macOS just makes the host fall back to the sharing-service editor.
private enum MarkupUI {
    private static let markupPath = "/System/Library/PrivateFrameworks/MarkupUI.framework/MarkupUI"
    private static let annotationPath = "/System/Library/PrivateFrameworks/AnnotationKit.framework/AnnotationKit"

    static func load() -> Bool {
        guard dlopen(annotationPath, RTLD_NOW | RTLD_GLOBAL) != nil else {
            log.error("Could not load AnnotationKit")
            return false
        }
        guard dlopen(markupPath, RTLD_NOW | RTLD_GLOBAL) != nil else {
            log.error("Could not load MarkupUI")
            return false
        }
        return NSClassFromString("MarkupViewController") != nil
    }

    static func makeController(toolbar: Bool) -> NSViewController? {
        guard let cls = NSClassFromString("MarkupViewController") else { return nil }
        let allocSel = NSSelectorFromString("alloc")
        guard let allocated = (cls as AnyObject).perform(allocSel)?.takeRetainedValue() else { return nil }
        let initSel = NSSelectorFromString("initWithToolbar:")
        guard let method = class_getInstanceMethod(cls, initSel) else { return nil }
        typealias InitFn = @convention(c) (AnyObject, Selector, Bool) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: InitFn.self)
        guard let object = fn(allocated, initSel, toolbar)?.takeUnretainedValue() else { return nil }
        return object as? NSViewController
    }

    static func setHostBundle(_ controller: NSViewController, _ identifier: String?) {
        guard let identifier else { return }
        let sel = NSSelectorFromString("setHostProcessBundleIdentifier:")
        if controller.responds(to: sel) {
            _ = controller.perform(sel, with: identifier)
        }
        let padding = NSSelectorFromString("setWantsToolbarAndPadding:")
        if controller.responds(to: padding), let method = class_getInstanceMethod(object_getClass(controller), padding) {
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Fn.self)(controller, padding, true)
        }
    }

    static func setFileURL(_ controller: NSViewController, _ url: URL) {
        let sel = NSSelectorFromString("setFileURL:withArchivedModelData:")
        let cls: AnyClass = object_getClass(controller) ?? NSClassFromString("MarkupViewController")!
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSURL, AnyObject?) -> Void
        unsafeBitCast(method_getImplementation(method), to: Fn.self)(controller, sel, url as NSURL, nil)
    }

    static func dataRepresentation(of controller: NSViewController) -> Data? {
        let sel = NSSelectorFromString("dataRepresentationWithError:")
        let cls: AnyClass = object_getClass(controller) ?? NSClassFromString("MarkupViewController")!
        guard let method = class_getInstanceMethod(cls, sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Unmanaged<AnyObject>?
        var error: NSError?
        let result = unsafeBitCast(method_getImplementation(method), to: Fn.self)(controller, sel, &error)?.takeUnretainedValue() as? Data
        if result == nil, let error {
            log.error("Markup dataRepresentation failed: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    static func teardown(_ controller: NSViewController) {
        for name in ["documentDidCloseTeardown", "fullTeardown"] {
            let sel = NSSelectorFromString(name)
            if controller.responds(to: sel) {
                _ = controller.perform(sel)
            }
        }
    }
}
