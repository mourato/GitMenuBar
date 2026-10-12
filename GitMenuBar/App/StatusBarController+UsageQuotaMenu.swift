import AppKit
import SwiftUI

@MainActor
extension StatusBarController {
    func updateStatusItemAppearance() {
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
        let usageImage = showsUsageInStatusItem && !groups.isEmpty
            ? makeUsageStatusImage(
                groups: groups,
                style: style
            )
            : nil
        button.image = StatusItemBadgeRenderer.makeCompositeImage(
            baseStatusImage: baseStatusImage,
            usageImage: usageImage,
            iconSize: Constants.statusIconPointSize
        )
        button.toolTip = if showsUsageInStatusItem, !groups.isEmpty {
            "\(groups.map(\.spokenLabel).joined(separator: ", ")). Right-click for usage quotas"
        } else if usageQuotaStore.showAIUsageQuotas {
            "GitMenuBar — right-click for usage quotas"
        } else {
            "GitMenuBar"
        }
        button.setAccessibilityLabel(button.toolTip ?? "GitMenuBar")
    }

    func makeUsageQuotaMenuItem() -> NSMenuItem? {
        guard usageQuotaStore.showAIUsageQuotas else { return nil }

        let submenu = NSMenu(title: "AI Usage Quotas")
        submenu.autoenablesItems = false

        let quotaItem = NSMenuItem()
        let hostedView = NSHostingView(
            rootView: UsageQuotaMenuView()
                .environment(usageQuotaStore)
                .environment(usageQuotaPresentationPreferences)
        )
        hostedView.frame = NSRect(origin: .zero, size: hostedView.fittingSize)
        quotaItem.view = hostedView
        quotaItem.isEnabled = false
        submenu.addItem(quotaItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem(title: "Refresh Quotas", action: #selector(refreshUsageFromMenu)))
        if let updatedAt = usageQuotaStore.visibleSnapshots.map(\.fetchedAt).max() {
            let updatedItem = NSMenuItem(title: "Updated \(updatedAgoText(since: updatedAt))", action: nil, keyEquivalent: "")
            updatedItem.isEnabled = false
            submenu.addItem(updatedItem)
        }

        let menuItem = NSMenuItem(title: "AI Usage Quotas", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    private func makeUsageStatusImage(
        groups: [UsageQuotaMenuBarGroup],
        style: UsageQuotaPresentationPreferences.MeterStyle
    ) -> NSImage? {
        let renderer = ImageRenderer(
            content: UsageQuotaMenuBarStrip(
                groups: groups,
                style: style,
                tint: .black
            )
        )
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

    private func updatedAgoText(since date: Date) -> String {
        guard Date().timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @objc private func refreshUsageFromMenu() {
        usageQuotaStore.refresh(reason: .manual)
    }
}

private extension UsageQuotaMenuBarGroup {
    var spokenLabel: String {
        "\(providerID.displayName): \(values.joined(separator: ", "))"
    }
}
