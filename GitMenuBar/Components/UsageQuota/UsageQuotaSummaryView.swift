import AppKit
import SwiftUI

struct UsageQuotaSummaryView: View {
    let snapshots: [UsageQuotaSnapshot]

    var body: some View {
        HStack(spacing: WorkbenchMetrics.compactSpacing) {
            ForEach(eligibleSnapshots) { snapshot in
                UsageQuotaSummaryItem(snapshot: snapshot)
            }
        }
    }

    private var eligibleSnapshots: [UsageQuotaSnapshot] {
        snapshots.compactMap { snapshot in
            guard snapshot.primaryDisplayWindow != nil else { return nil }
            return snapshot
        }.prefix(3).map(\.self)
    }
}

private struct UsageQuotaSummaryItem: View {
    let snapshot: UsageQuotaSnapshot

    var body: some View {
        if let window = snapshot.primaryDisplayWindow {
            HStack(spacing: WorkbenchMetrics.microSpacing) {
                ProviderIconView(providerID: snapshot.providerID)

                Text("\(window.remainingPercent)%")
                    .font(WorkbenchTypography.captionStrong)
                    .foregroundStyle(UsageQuotaTrafficLightColor.swiftUI(for: window.remainingPercent))
            }
            .opacity(snapshot.isStale ? 0.72 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(window: window))
        }
    }

    private func accessibilityLabel(window: UsageWindow) -> String {
        let staleText = snapshot.isStale ? ", stale" : ""
        return "\(snapshot.displayName), \(window.remainingPercent) percent remaining\(staleText)"
    }
}

struct ProviderIconView: View {
    let providerID: UsageProviderID

    var body: some View {
        if let image = ProviderIconRenderer.image(for: providerID) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "sparkles")
                .font(WorkbenchTypography.captionStrong)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }
}

private enum ProviderIconRenderer {
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()

    static func image(for providerID: UsageProviderID) -> NSImage? {
        let resourceName = switch providerID {
        case .codex:
            "ProviderIcon-codex"
        case .cursor:
            "ProviderIcon-cursor"
        case .openrouter:
            "ProviderIcon-openrouter"
        }

        let cacheKey = resourceName as NSString
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let resourceURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg"
        ),
            let data = try? Data(contentsOf: resourceURL),
            let image = NSImage(data: data)
        else {
            return nil
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

enum UsageQuotaTrafficLightColor {
    static func swiftUI(for remainingPercent: Int) -> Color {
        switch UsageQuotaFormatting.trafficLightColor(for: remainingPercent) {
        case .green:
            .green
        case .amber:
            .orange
        case .red:
            .red
        }
    }
}

#Preview("Usage Quota Summary") {
    UsageQuotaSummaryView(snapshots: [
        UsageQuotaSnapshot(
            providerID: .codex,
            displayName: "Codex",
            sessionWindow: UsageWindow(
                remainingPercent: 62,
                resetAt: Date().addingTimeInterval(3600),
                label: "5h",
                durationSeconds: 5 * 3600
            ),
            weeklyWindow: nil,
            isAvailable: true
        ),
        UsageQuotaSnapshot(
            providerID: .cursor,
            displayName: "Cursor",
            sessionWindow: UsageWindow(
                remainingPercent: 41,
                resetAt: Date().addingTimeInterval(86400),
                label: "Plan",
                durationSeconds: 30 * 86400
            ),
            weeklyWindow: nil,
            isAvailable: true
        )
    ])
    .padding()
}
