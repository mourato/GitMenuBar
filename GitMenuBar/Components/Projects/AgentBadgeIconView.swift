import AppKit
import SwiftUI

/// Compact visual badge representing an active or recent AI coding agent on a project.
struct AgentBadgeIconView: View {
    let activity: AgentProjectActivity
    var size: CGFloat = 13

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            agentImage
                .frame(width: size, height: size)
                .opacity(activity.status.isRunning ? 1.0 : 0.45)

            if activity.status.isRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: 4, height: 4)
                    .offset(x: 1, y: 1)
            }
        }
        .help(tooltipText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var agentImage: some View {
        if let nsImage = AgentIconCache.image(for: activity.harness) {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(activity.status.isRunning ? Color.primary : Color.secondary)
                .accessibilityHidden(true)
        } else {
            Image(systemName: activity.harness.fallbackSymbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(activity.status.isRunning ? Color.primary : Color.secondary)
                .accessibilityHidden(true)
        }
    }

    private var tooltipText: String {
        switch activity.status {
        case .running:
            "\(activity.harness.displayName): active now"
        case let .recent(date):
            "\(activity.harness.displayName): active \(Self.formatRelativeDate(date))"
        }
    }

    private var accessibilityLabel: String {
        switch activity.status {
        case .running:
            "\(activity.harness.displayName) agent: active now"
        case let .recent(date):
            "\(activity.harness.displayName) agent: active \(Self.formatRelativeDate(date))"
        }
    }

    private static func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Thread-safe image caching for SVG agent icons.
private enum AgentIconCache {
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()

    static func image(for harness: AgentHarnessID) -> NSImage? {
        let resourceName = harness.iconResourceName
        let cacheKey = resourceName as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let resourceURL = Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg"
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: "Resources/ProviderIcons"
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: "svg",
            subdirectory: "ProviderIcons"
        )

        guard let resourceURL,
              let data = try? Data(contentsOf: resourceURL),
              let image = NSImage(data: data)
        else {
            return nil
        }

        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

#Preview("Agent Badges - All Harnesses") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Active Agents (Running)")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack(spacing: 8) {
            ForEach(AgentHarnessID.allCases) { harness in
                AgentBadgeIconView(
                    activity: AgentProjectActivity(harness: harness, status: .running)
                )
            }
        }

        Divider()

        Text("Recent Agents (Inactive)")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack(spacing: 8) {
            ForEach(AgentHarnessID.allCases) { harness in
                AgentBadgeIconView(
                    activity: AgentProjectActivity(
                        harness: harness,
                        status: .recent(Date().addingTimeInterval(-1800))
                    )
                )
            }
        }
    }
    .padding()
    .frame(width: 250)
}
