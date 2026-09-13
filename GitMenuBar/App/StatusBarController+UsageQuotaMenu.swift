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
        let showsUsageInStatusItem = usageQuotaStore.showAIUsageQuotas
            && usageQuotaPresentationPreferences.menuBarVisibility == .always
        let menuBarAppearance = button.window?.effectiveAppearance ?? button.effectiveAppearance
        let usageImage = showsUsageInStatusItem && !groups.isEmpty
            ? makeUsageStatusImage(
                groups: groups,
                style: style,
                isTemplate: attentionCount == 0,
                appearance: menuBarAppearance
            )
            : nil
        button.image = StatusItemBadgeRenderer.makeCompositeImage(
            baseStatusImage: baseStatusImage,
            usageImage: usageImage,
            count: attentionCount,
            iconSize: Constants.statusIconPointSize,
            appearance: menuBarAppearance
        )
        button.toolTip = if showsUsageInStatusItem, !groups.isEmpty {
            groups.map(\.spokenLabel).joined(separator: ", ")
        } else if usageQuotaStore.showAIUsageQuotas {
            "GitMenuBar — open usage quotas menu"
        } else {
            "GitMenuBar"
        }
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
        hostedView.frame = NSRect(origin: .zero, size: hostedView.fittingSize)
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
        style: UsageQuotaPresentationPreferences.MeterStyle,
        isTemplate: Bool,
        appearance: NSAppearance?
    ) -> NSImage? {
        var renderedImage: NSImage?
        let render = {
            let renderer = ImageRenderer(
                content: UsageQuotaMenuBarStrip(
                    groups: groups,
                    style: style,
                    tint: Color(nsColor: .labelColor)
                )
            )
            renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
            renderedImage = renderer.nsImage
        }

        if let appearance {
            appearance.performAsCurrentDrawingAppearance(render)
        } else {
            render()
        }

        guard let image = renderedImage else { return nil }
        image.isTemplate = isTemplate
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
