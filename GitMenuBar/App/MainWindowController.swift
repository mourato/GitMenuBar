import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    private enum Constants {
        static let windowInitialSize = NSSize(width: WorkbenchMetrics.mainWindowInitialWidth, height: 720)
        static let windowMinimumHeight: CGFloat = 420
        static let windowMinimumSize = NSSize(width: WorkbenchMetrics.mainWindowMinimumWidth, height: windowMinimumHeight)
        static let autoHideBlurEvaluationDelay: TimeInterval = 0.08
        static let windowAutosaveName = NSWindow.FrameAutosaveName("GitMenuBar.MainWindow")
        static let screenCaptureUIBundleIdentifier = "com.apple.screencaptureui"
    }

    struct WindowOpenTrace {
        let id: Int
        let startedAt: CFAbsoluteTime
        let trigger: String
    }

    enum WindowPlacementStrategy {
        case statusItemAnchor
        case mousePointerMonitor
    }

    private weak var statusBarController: StatusBarController?
    private let usageQuotaStore: UsageQuotaStore
    private var mainWindow: NSWindow? {
        window
    }

    private var mainWindowToolbarController: MainWindowToolbarController?
    private let windowDelegate = MainWindowLifecycleDelegate()
    private var nextWindowOpenTraceID = 0
    private var hasPositionedWindowInitially = false
    private var isAutoHideSuspended = false

    init(statusBarController: StatusBarController) {
        self.statusBarController = statusBarController
        usageQuotaStore = statusBarController.usageQuotaStore
        super.init(window: nil)
        setupMainWindow(statusBarController: statusBarController)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateToolbar(title: String, showsSidebarItem: Bool, showsBackItem: Bool) {
        mainWindowToolbarController?.update(
            title: title, showsSidebarItem: showsSidebarItem, showsBackItem: showsBackItem
        )
    }

    func focus() {
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func toggleVisibleWindow() {
        if NSApp.isActive, mainWindow?.isKeyWindow == true {
            hide()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            focus()
        }
    }

    private func setupMainWindow(statusBarController: StatusBarController) {
        let contentRect = NSRect(origin: .zero, size: Constants.windowInitialSize)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.collectionBehavior.insert([.fullScreenPrimary, .participatesInCycle])
        window.tabbingMode = .disallowed

        configureMainWindowAppearance(window)
        window.title = "GitMenuBar"
        let toolbarController = MainWindowToolbarController(target: statusBarController)
        toolbarController.install(in: window)
        mainWindowToolbarController = toolbarController
        window.isReleasedWhenClosed = false
        window.setContentSize(Constants.windowInitialSize)
        window.contentMinSize = Constants.windowMinimumSize
        window.setFrameAutosaveName(Constants.windowAutosaveName)
        hasPositionedWindowInitially = window.setFrameUsingName(Constants.windowAutosaveName, force: false)
        normalizeMainWindowSize(window)

        let contentController = WorkbenchWindowChrome.makeHostedContentController(rootView: makeRootView(statusBarController: statusBarController))
        window.contentViewController = contentController
        WorkbenchWindowChrome.configureTransparentWindow(window)

        windowDelegate.onShouldClose = { [weak self] in
            self?.hide()
            return false
        }
        windowDelegate.onDidResignKey = { [weak self] in
            self?.handleMainWindowDidResignKey()
        }
        windowDelegate.onDidMoveOrResize = { [weak self] in
            self?.persistMainWindowFrameIfPossible()
        }
        windowDelegate.onDidEndLiveResize = { [weak self] in
            self?.mainWindow?.invalidateShadow()
        }

        window.delegate = windowDelegate

        self.window = window
    }

    private func configureMainWindowAppearance(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.hasShadow = true
        window.isMovableByWindowBackground = false
    }

    private func makeRootView(statusBarController: StatusBarController) -> AnyView {
        let rootView = MainMenuView(
            closeWindow: { [weak self] in
                self?.hide()
            },
            openSettingsWindow: { [weak statusBarController] in
                statusBarController?.showSettingsWindow()
            },
            setAutoHideSuspended: { [weak self] suspended in
                self?.setAutoHideSuspended(suspended)
            }
        )
        .environment(statusBarController.gitManager)
        .environment(statusBarController.loginItemManager)
        .environment(statusBarController.githubAuthManager)
        .environment(statusBarController.aiProviderStore)
        .environment(statusBarController.aiCommitCoordinator)
        .environment(statusBarController.actionCoordinator)
        .environment(statusBarController.commitHistoryEditCoordinator)
        .environment(statusBarController.shortcutActionBridge)
        .environment(statusBarController.presentationModel)
        .environment(statusBarController.usageQuotaStore)
        .environment(statusBarController.usageQuotaPresentationPreferences)
        .environment(statusBarController.projectMonitor)
        .environment(statusBarController.repositorySelectionCoordinator)
        .environment(statusBarController.projectCleanupStore)

        return AnyView(rootView)
    }

    func setAutoHideSuspended(_ suspended: Bool) {
        isAutoHideSuspended = suspended
    }

    private func handleMainWindowDidResignKey() {
        guard shouldAutoHideOnBlur, !isMainWindowPresentingSheet else { return }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.autoHideBlurEvaluationDelay))
            guard let self,
                  shouldAutoHideOnBlur,
                  !self.isMainWindowPresentingSheet,
                  !self.isSystemScreenCaptureUIFrontmost
            else { return }

            hide()
        }
    }

    private var isMainWindowPresentingSheet: Bool {
        mainWindow?.attachedSheet != nil
    }

    private var shouldAutoHideOnBlur: Bool {
        MainWindowPreferences.isAutoHideOnBlurEnabled() && !isAutoHideSuspended
    }

    private var isSystemScreenCaptureUIFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Constants.screenCaptureUIBundleIdentifier
    }

    var isMainWindowVisible: Bool {
        mainWindow?.isVisible == true
    }

    func open(trace: WindowOpenTrace, placementStrategy: WindowPlacementStrategy) {
        guard let mainWindow else { return }

        if mainWindow.isMiniaturized {
            mainWindow.deminiaturize(nil)
        }

        if mainWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            usageQuotaStore.refresh(reason: .windowPresented)
            return
        }

        if restoreMainWindowFrameIfAvailable(mainWindow) {
            normalizeMainWindowSize(mainWindow)
            if let screen = mainWindow.screen ?? NSScreen.main {
                fitMainWindowWidthToVisibleFrame(mainWindow, visibleFrame: screen.visibleFrame)
                clampMainWindowOriginToVisibleFrame(mainWindow, visibleFrame: screen.visibleFrame)
            }
            hasPositionedWindowInitially = true
        } else {
            switch placementStrategy {
            case .mousePointerMonitor:
                if let screen = screenContainingMousePointer() {
                    positionMainWindow(on: screen, window: mainWindow)
                    hasPositionedWindowInitially = true
                } else if !hasPositionedWindowInitially {
                    positionMainWindowRelativeToStatusItem(mainWindow)
                    hasPositionedWindowInitially = true
                }
            case .statusItemAnchor:
                if !hasPositionedWindowInitially {
                    positionMainWindowRelativeToStatusItem(mainWindow)
                    hasPositionedWindowInitially = true
                }
            }
        }

        mainWindow.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        logWindowOpen(trace, message: "window visible")
        usageQuotaStore.refresh(reason: .windowPresented)
    }

    private func positionMainWindowRelativeToStatusItem(_ window: NSWindow) {
        guard let button = statusBarController?.statusItem?.button,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else {
            window.center()
            return
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectInScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let visibleFrame = screen.visibleFrame

        fitMainWindowWidthToVisibleFrame(window, visibleFrame: visibleFrame)

        var originX = buttonRectInScreen.maxX - window.frame.width
        var originY = buttonRectInScreen.minY - window.frame.height - 8

        let minX = visibleFrame.minX + 8
        let maxX = max(minX, visibleFrame.maxX - window.frame.width - 8)
        originX = min(max(originX, minX), maxX)

        let minY = visibleFrame.minY + 8
        let maxY = max(minY, visibleFrame.maxY - window.frame.height - 20)

        if originY < minY {
            originY = maxY
        }
        originY = min(max(originY, minY), maxY)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func screenContainingMousePointer() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
    }

    private func positionMainWindow(on screen: NSScreen, window: NSWindow) {
        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 12

        fitMainWindowWidthToVisibleFrame(window, visibleFrame: visibleFrame)

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - window.frame.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - window.frame.height - margin)

        let originX = max(minX, maxX)
        let originY = max(minY, maxY)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func fitMainWindowWidthToVisibleFrame(_ window: NSWindow, visibleFrame: NSRect) {
        let margin: CGFloat = 8
        let maxFrameWidth = visibleFrame.width - (margin * 2)
        guard maxFrameWidth > 0, window.frame.width > maxFrameWidth else { return }

        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        let frameChromeWidth = window.frame.width - currentContentSize.width
        let maxContentWidth = maxFrameWidth - frameChromeWidth
        guard maxContentWidth >= window.contentMinSize.width else { return }

        window.setContentSize(
            NSSize(width: maxContentWidth, height: currentContentSize.height)
        )
    }

    private func clampMainWindowOriginToVisibleFrame(_ window: NSWindow, visibleFrame: NSRect) {
        let margin: CGFloat = 8
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - window.frame.width - margin)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - window.frame.height - margin)
        let originX = min(max(window.frame.minX, minX), maxX)
        let originY = min(max(window.frame.minY, minY), maxY)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func normalizeMainWindowSize(_ window: NSWindow) {
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let normalizedContentSize = NSSize(
            width: max(currentContentRect.width, Constants.windowMinimumSize.width),
            height: max(currentContentRect.height, Constants.windowMinimumSize.height)
        )

        guard normalizedContentSize != currentContentRect.size else { return }
        window.setContentSize(normalizedContentSize)
    }

    func hide() {
        guard let mainWindow, mainWindow.isVisible else { return }

        persistMainWindowFrame(mainWindow)
        mainWindow.orderOut(nil)
    }

    private func persistMainWindowFrame(_ window: NSWindow) {
        window.saveFrame(usingName: Constants.windowAutosaveName)
    }

    private func persistMainWindowFrameIfPossible() {
        guard let mainWindow else { return }
        persistMainWindowFrame(mainWindow)
    }

    private func restoreMainWindowFrameIfAvailable(_ window: NSWindow) -> Bool {
        window.setFrameUsingName(Constants.windowAutosaveName, force: false)
    }

    func beginWindowOpenTrace(trigger: String) -> WindowOpenTrace {
        nextWindowOpenTraceID += 1
        let trace = WindowOpenTrace(
            id: nextWindowOpenTraceID,
            startedAt: CFAbsoluteTimeGetCurrent(),
            trigger: trigger
        )

        print("[WindowOpen #\(trace.id)] trigger=\(trigger) +0ms")
        return trace
    }

    func logWindowOpen(_ trace: WindowOpenTrace, message: String) {
        let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - trace.startedAt) * 1000)
        print("[WindowOpen #\(trace.id)] trigger=\(trace.trigger) +\(elapsedMilliseconds)ms \(message)")
    }
}

private final class MainWindowLifecycleDelegate: NSObject, NSWindowDelegate {
    var onShouldClose: (() -> Bool)?
    var onDidResignKey: (() -> Void)?
    var onDidMoveOrResize: (() -> Void)?
    var onDidEndLiveResize: (() -> Void)?

    func windowShouldClose(_: NSWindow) -> Bool {
        onShouldClose?() ?? true
    }

    func windowDidResignKey(_: Notification) {
        onDidResignKey?()
    }

    func windowDidMove(_: Notification) {
        onDidMoveOrResize?()
    }

    func windowDidEndLiveResize(_: Notification) {
        onDidEndLiveResize?()
        onDidMoveOrResize?()
    }
}
