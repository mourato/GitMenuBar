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
        addCodexResetItems(to: submenu)

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

    private func addCodexResetItems(to submenu: NSMenu) {
        guard let codex = usageQuotaStore.visibleSnapshots.first(where: { $0.providerID == .codex }),
              !codex.resetCredits.isEmpty
        else {
            return
        }

        submenu.addItem(.separator())
        let count = codex.resetCreditsAvailable ?? codex.resetCredits.count
        let header = NSMenuItem(
            title: count == 1 ? "1 Codex reset available" : "\(count) Codex resets available",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        submenu.addItem(header)

        for credit in codex.resetCredits {
            let isRedeeming = usageQuotaStore.redeemingResetCreditIDs.contains(credit.id)
            let expiry = credit.expiresAt.formatted(date: .abbreviated, time: .omitted)
            let item = menuItem(
                title: isRedeeming ? "Using reset" : "Use reset, expires \(expiry)",
                action: #selector(redeemResetFromMenu(_:))
            )
            item.representedObject = credit
            item.isEnabled = !isRedeeming
            submenu.addItem(item)
        }
    }

    @objc private func redeemResetFromMenu(_ sender: NSMenuItem) {
        guard let credit = sender.representedObject as? UsageQuotaResetCredit else { return }
        Task {
            guard confirmResetRedemption() else { return }
            guard let outcome = await usageQuotaStore.redeemCodexResetCredit(credit) else { return }
            presentResetOutcome(outcome)
        }
    }

    /// Redeeming spends a reset that cannot be recovered, so the user confirms first.
    private func confirmResetRedemption() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Use a Codex reset?"
        alert.informativeText = "This spends one reset from your ChatGPT account. It can't be undone."
        alert.addButton(withTitle: "Use Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentResetOutcome(_ outcome: CodexResetRedeemOutcome) {
        let alert = NSAlert()
        switch outcome {
        case let .applied(windowsReset):
            alert.alertStyle = .informational
            alert.messageText = "Codex reset used"
            alert.informativeText = windowsReset > 0
                ? "\(windowsReset) Codex limit \(windowsReset == 1 ? "window was" : "windows were") reset."
                : "Your Codex limits were reset."
        case .nothingToReset:
            alert.alertStyle = .informational
            alert.messageText = "No Codex limit needed a reset"
            alert.informativeText = "No limit was eligible for a reset. Refresh quotas to check your remaining resets."
        case .noCredit:
            alert.alertStyle = .warning
            alert.messageText = "No reset available"
            alert.informativeText = "This reset was already used or has expired. Usage has been refreshed."
        case .unauthorized:
            alert.alertStyle = .warning
            alert.messageText = "Sign in to Codex again"
            alert.informativeText = "Your ChatGPT session expired. Open Codex, sign in, then try again."
        case .forbidden:
            alert.alertStyle = .warning
            alert.messageText = "Resets aren't available"
            alert.informativeText = "ChatGPT doesn't allow resets for this account."
        case .failed:
            alert.alertStyle = .critical
            alert.messageText = "Couldn't confirm the reset"
            alert.informativeText = "The request didn't finish. Refresh quotas to see whether the reset was used before you try again."
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private extension UsageQuotaMenuBarGroup {
    var spokenLabel: String {
        "\(providerID.displayName): \(values.joined(separator: ", "))"
    }
}
