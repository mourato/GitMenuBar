import SwiftUI

struct RepositoryVisibilityToggle: View {
    @Binding var isPrivate: Bool

    var body: some View {
        SettingsSection(title: "Visibility", systemImage: isPrivate ? "lock" : "globe") {
            HStack(spacing: 0) {
                visibilityButton(title: "Public", systemImage: "globe", isSelected: !isPrivate) {
                    isPrivate = false
                }
                visibilityButton(title: "Private", systemImage: "lock", isSelected: isPrivate) {
                    isPrivate = true
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func visibilityButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .foregroundColor(isSelected ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct RepoVisibilityPreview: View {
    @State private var isPrivate = true

    var body: some View {
        RepositoryVisibilityToggle(isPrivate: $isPrivate)
            .padding()
            .frame(width: 320)
    }
}

#Preview("Repository Visibility") {
    RepoVisibilityPreview()
}
