import AppKit
import SwiftUI

enum WorkbenchWindowChrome {
    @MainActor
    static func configureTransparentWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    @MainActor
    static func installShell(in contentView: NSView) {
        if let existingShell = contentView.subviews.compactMap({ $0 as? WorkbenchWindowShellView }).first {
            existingShell.updateAppearance()
            return
        }

        let shell = WorkbenchWindowShellView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(shell, positioned: .below, relativeTo: nil)

        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shell.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shell.topAnchor.constraint(equalTo: contentView.topAnchor),
            shell.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        contentView.wantsLayer = true
        shell.updateAppearance()
        WorkbenchScrollViewStyle.configureScrollViews(in: contentView)
    }

    @MainActor
    static func makeHostedContentController(rootView: some View) -> NSViewController {
        WorkbenchHostedContentViewController(rootView: AnyView(rootView))
    }
}

final class WorkbenchWindowShellView: NSView {
    private let visualEffectView = NSVisualEffectView()
    private let solidBackgroundView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViews()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func updateAppearance() {
        let shouldReduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        visualEffectView.isHidden = shouldReduceTransparency
        solidBackgroundView.isHidden = !shouldReduceTransparency
        solidBackgroundView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    private func setUpViews() {
        wantsLayer = true

        visualEffectView.material = .windowBackground
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        solidBackgroundView.wantsLayer = true
        solidBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(solidBackgroundView)
        addSubview(visualEffectView)

        NSLayoutConstraint.activate([
            solidBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            solidBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAccessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: NSWorkspace.shared
        )

        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    @objc
    private func handleAccessibilityDisplayOptionsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateAppearance()
        }
    }
}

private final class WorkbenchHostedContentViewController: NSViewController {
    private let hostingController: NSHostingController<AnyView>

    init(rootView: AnyView) {
        hostingController = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = WorkbenchMetrics.largeCornerRadius
        container.layer?.masksToBounds = true
        view = container

        let shell = WorkbenchWindowShellView()
        shell.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        container.addSubview(shell)
        container.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            shell.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shell.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shell.topAnchor.constraint(equalTo: container.topAnchor),
            shell.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        if !(hostingController.view is NSHostingView<AnyView>) {
            assertionFailure("Expected NSHostingView<AnyView> for hosted window content")
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        WorkbenchScrollViewStyle.configureScrollViews(in: view)
    }
}
