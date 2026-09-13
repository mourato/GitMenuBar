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
            "\(groups.map(\.spokenLabel).joined(separator: ", ")). Right-click for usage quotas and Git commands"
        } else if usageQuotaStore.showAIUsageQuotas {
            "GitMenuBar — right-click for usage quotas and Git commands"
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
                .environmentObject(usageQuotaStore)
                .environmentObject(usageQuotaPresentationPreferences)
        )
        hostedView.frame = NSRect(origin: .zero, size: hostedView.fittingSize)
        quotaItem.view = hostedView
        quotaItem.isEnabled = false
        submenu.addItem(quotaItem)
        submenu.addItem(.separator())
        submenu.addItem(menuItem(title: "Atualizar cotas", action: #selector(refreshUsageFromMenu)))

        let menuItem = NSMenuItem(title: "AI Usage Quotas", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    private func makeUsageStatusImage(
        groups: [UsageQuotaMenuBarGroup],
        style: UsageQuotaPresentationPreferences.MeterStyle,
        isTemplate: Bool,
        appearance: NSAppearance?
    ) -> NSImage? {
        // ponytail: ImageRenderer ignora NSAppearance.current, então resolve labelColor
        // para cor fixa antes de renderizar; template usa preto (só alpha importa).
        let tint: Color = if isTemplate {
            .black
        } else if let appearance {
            resolvedMenuBarTint(for: appearance)
        } else {
            Color(nsColor: .labelColor)
        }

        let renderer = ImageRenderer(
            content: UsageQuotaMenuBarStrip(
                groups: groups,
                style: style,
                tint: tint
            )
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = isTemplate
        image.accessibilityDescription = groups.map(\.spokenLabel).joined(separator: ", ")
        return image
    }

    private func resolvedMenuBarTint(for appearance: NSAppearance) -> Color {
        var resolved = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.sRGB) ?? NSColor.labelColor
        }
        return Color(nsColor: resolved)
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
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
