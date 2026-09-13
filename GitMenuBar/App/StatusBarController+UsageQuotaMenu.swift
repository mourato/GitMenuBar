import AppKit
import SwiftUI

@MainActor
extension StatusBarController {
    func updateStatusItemAppearance(attentionCount: Int) {
        guard let button = statusItem?.button else { return }

        let groups = UsageQuotaMenuPresentation.groups(
            snapshots: usageQuotaStore.visibleSnapshots,
            preferences: usageQuotaPresentationPreferences
        )
        let style = usageQuotaPresentationPreferences.meterStyle == .bars && groups.flatMap(\.fractions).isEmpty
            ? .text
            : usageQuotaPresentationPreferences.meterStyle
        let usageImage = groups.isEmpty ? nil : makeUsageStatusImage(groups: groups, style: style)
        button.image = StatusItemBadgeRenderer.makeCompositeImage(
            baseStatusImage: baseStatusImage,
            usageImage: usageImage,
            count: attentionCount,
            iconSize: Constants.statusIconPointSize
        )
        button.toolTip = groups.isEmpty ? "GitMenuBar" : groups.map(\.spokenLabel).joined(separator: ", ")
        button.setAccessibilityLabel(button.toolTip ?? "GitMenuBar")
    }

    func showUsageMenu() {
        guard let button = statusItem?.button else {
            openMainWindow()
            return
        }

        usageQuotaStore.refresh(reason: .manual)

        let menu = NSMenu()
        menu.autoenablesItems = false

        let quotaItem = NSMenuItem()
        let hostedView = NSHostingView(
            rootView: UsageQuotaMenuView()
                .environmentObject(usageQuotaStore)
                .environmentObject(usageQuotaPresentationPreferences)
        )
        hostedView.layoutSubtreeIfNeeded()
        hostedView.frame = NSRect(
            x: 0,
            y: 0,
            width: UsageQuotaMenuView.width,
            height: max(1, hostedView.fittingSize.height)
        )
        quotaItem.view = hostedView
        quotaItem.isEnabled = false
        menu.addItem(quotaItem)
        menu.addItem(.separator())

        menu.addItem(menuItem(title: "Abrir GitMenuBar", action: #selector(openMainWindowFromUsageMenu)))
        menu.addItem(menuItem(title: "Atualizar cotas", action: #selector(refreshUsageFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Configurações", action: #selector(openSettingsFromUsageMenu)))
        menu.addItem(menuItem(title: "Sair do GitMenuBar", action: #selector(quitFromUsageMenu)))

        usageMenu = menu
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
        usageMenu = nil
    }

    private func makeUsageStatusImage(
        groups: [UsageQuotaMenuBarGroup],
        style: UsageQuotaPresentationPreferences.MeterStyle
    ) -> NSImage? {
        let renderer = ImageRenderer(content: UsageQuotaMenuBarStrip(groups: groups, style: style))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = groups.map(\.spokenLabel).joined(separator: ", ")
        return image
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindowFromUsageMenu() {
        openMainWindow()
    }

    @objc private func refreshUsageFromMenu() {
        usageQuotaStore.refresh(reason: .manual)
    }

    @objc private func openSettingsFromUsageMenu() {
        showSettingsWindow()
    }

    @objc private func quitFromUsageMenu() {
        NSApplication.shared.terminate(nil)
    }
}

private extension UsageQuotaMenuBarGroup {
    var spokenLabel: String {
        "\(providerID.displayName): \(values.joined(separator: ", "))"
    }
}
