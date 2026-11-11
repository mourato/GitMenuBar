import AppKit
import SwiftUI

/// Inline status line for label reads and writes. It names a restriction
/// without asking for credentials and offers retry only when another attempt
/// can succeed.
struct IssueLabelStatusView: View {
    let text: String
    let systemImage: String
    let retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WorkbenchMetrics.compactSpacing) {
            Image(systemName: systemImage)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("Try Again", action: retry)
                    .workbenchGhost()
            }
        }
    }
}

/// Per-issue label menu. The row itself still opens GitHub; this control lists
/// every repository label with a checkmark for the applied ones, so keyboard
/// and VoiceOver can change one label at a time. It also starts label creation,
/// which belongs to the repository rather than to this issue.
struct IssueLabelMenu: View {
    let issue: GitHubIssue
    let labels: [GitHubIssueLabel]
    let canEdit: Bool
    let canCreate: Bool
    let isPending: Bool
    let isEnabled: Bool
    let onSet: (GitHubIssueLabel, Bool) -> Void
    let onCreate: () -> Void

    var body: some View {
        if canCreate || (canEdit && !labels.isEmpty) {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                    .accessibilityLabel("Updating labels for issue \(issue.number)")
            } else {
                Menu {
                    if canEdit {
                        ForEach(labels, id: \.name) { label in
                            Toggle(
                                label.name,
                                isOn: Binding(
                                    get: { issue.labels.contains { $0.name == label.name } },
                                    set: { isOn in onSet(label, isOn) }
                                )
                            )
                        }
                    }
                    if canCreate {
                        if canEdit, !labels.isEmpty {
                            Divider()
                        }
                        Button("New Label in Repository", action: onCreate)
                    }
                } label: {
                    Image(systemName: "tag")
                        .font(WorkbenchTypography.body)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: WorkbenchMetrics.iconHitTarget, height: WorkbenchMetrics.iconHitTarget)
                .contentShape(Rectangle())
                .disabled(!isEnabled)
                .help("Edit labels for issue \(issue.number)")
                .accessibilityLabel("Edit labels for issue \(issue.number), \(issue.title)")
                .accessibilityHint("Choose labels to apply or remove, or create a label for this repository")
            }
        }
    }
}

/// Creates a repository label from the tag menu. The sheet names the
/// repository, because the label becomes available to every issue there; the
/// issue keeps its labels until the user applies the new one.
struct IssueLabelCreationSheet: View {
    let repositoryName: String
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onCreate: (_ name: String, _ colorHex: String, _ description: String) -> Void

    @State private var name = ""
    @State private var color = Color.accentColor
    @State private var description = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
            Text("New Label")
                .font(.headline.weight(.semibold))

            Text("Adds a label to \(repositoryName). Every issue in the repository can use it. Creating it does not apply it to this issue.")
                .font(WorkbenchTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: WorkbenchMetrics.compactSpacing) {
                Text("Name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("needs triage", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(WorkbenchTypography.detail)
                    .focused($isNameFocused)
                    .onSubmit(submit)
                    .accessibilityLabel("Label name")

                Text("Color")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: WorkbenchMetrics.compactSpacing) {
                    ColorPicker("Label color", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel("Label color")
                    Text("#\(IssueLabelHex.color(from: color))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("Description (optional)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("What this label means", text: $description)
                    .textFieldStyle(.roundedBorder)
                    .font(WorkbenchTypography.detail)
                    .onSubmit(submit)
                    .accessibilityLabel("Label description, optional")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(WorkbenchTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: WorkbenchMetrics.compactSpacing) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer(minLength: 0)

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Creating label")
                }
                Button("Create Label", action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(WorkbenchMetrics.panelPadding)
        .frame(width: WorkbenchMetrics.sidePanelWidth)
        .onAppear {
            isNameFocused = true
        }
    }

    private func submit() {
        guard !isSaving else { return }
        onCreate(name, IssueLabelHex.color(from: color), description)
    }
}

/// Converts the native color picker's selection to the six-digit hex GitHub
/// stores, so the request always carries a valid color.
enum IssueLabelHex {
    static func color(from color: Color) -> String {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let red = Int((resolved.redComponent * 255).rounded())
        let green = Int((resolved.greenComponent * 255).rounded())
        let blue = Int((resolved.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", red, green, blue)
    }
}

/// Copy for label failures and restrictions. A permission problem stays
/// distinct from a connection error, because only the latter can be retried.
enum IssueLabelMessages {
    static func mutation(_ error: GitHubIssueLabelError) -> String {
        switch error {
        case .notAuthenticated:
            "Sign in to GitHub in Settings to change labels."
        case .repositoryNotFound:
            "GitHub did not find this repository, or your account cannot access it."
        case .forbidden:
            "Your GitHub account cannot change labels in this repository. Ask a repository admin for write access."
        case .labelNameTaken:
            "That label name already exists in this repository."
        case .invalidLabel:
            "GitHub rejected the label. Check its name and color."
        case .requestFailed:
            "Could not update labels. Check your connection and try again."
        }
    }

    static func list(_ error: GitHubIssueLabelError) -> String {
        switch error {
        case .notAuthenticated:
            "Sign in to GitHub in Settings to change labels."
        case .repositoryNotFound:
            "Could not load this repository's labels."
        case .forbidden:
            "Your GitHub account cannot change labels in this repository. Ask a repository admin for write access."
        case .labelNameTaken:
            "Could not load this repository's labels."
        case .invalidLabel:
            "Could not load this repository's labels."
        case .requestFailed:
            "Could not load labels. Check your connection and try again."
        }
    }

    static func creation(_ error: IssueLabelCreationError) -> String {
        switch error {
        case let .validation(validation):
            validationMessage(validation)
        case let .repository(repository):
            repositoryMessage(repository)
        }
    }

    private static func validationMessage(_ error: IssueLabelDraft.ValidationError) -> String {
        switch error {
        case .nameRequired:
            "Enter a label name."
        case .nameTooLong:
            "Use \(IssueLabelDraft.maximumNameLength) characters or fewer for the name."
        case .nameTaken:
            nameTaken
        case .colorInvalid:
            "Choose a color with six hexadecimal digits, for example d73a4a."
        case .descriptionTooLong:
            "Use \(IssueLabelDraft.maximumDescriptionLength) characters or fewer for the description."
        }
    }

    private static func repositoryMessage(_ error: GitHubIssueLabelError) -> String {
        switch error {
        case .notAuthenticated:
            "Sign in to GitHub in Settings to create labels."
        case .repositoryNotFound:
            "GitHub did not find this repository, or your account cannot access it."
        case .forbidden:
            "Your GitHub account cannot create labels in this repository. Ask a repository admin for write access."
        case .labelNameTaken:
            nameTaken
        case .invalidLabel:
            "GitHub rejected the label details. Check the name, color, and description."
        case .requestFailed:
            "Could not create the label. Check your connection and try again."
        }
    }

    private static let nameTaken = "That name already exists in this repository. Apply the existing label from the tag menu, or enter a different name."
}

#Preview("Issue Label Controls") {
    let issue = GitHubIssue(
        number: 42,
        title: "Consultar a lista de issues do projeto dentro do app",
        state: .open,
        authorLogin: "mourato",
        createdAt: Date(),
        updatedAt: Date(),
        labels: [GitHubIssueLabel(name: "bug", colorHex: "d73a4a", nodeID: "L_bug")],
        url: URL(fileURLWithPath: "/issues/42"),
        nodeID: "I_42"
    )
    let labels = [
        GitHubIssueLabel(name: "bug", colorHex: "d73a4a", nodeID: "L_bug"),
        GitHubIssueLabel(name: "enhancement", colorHex: "a2eeef", nodeID: "L_enh")
    ]

    VStack(alignment: .leading, spacing: WorkbenchMetrics.sectionSpacing) {
        HStack {
            Text(issue.title)
                .font(WorkbenchTypography.body)
            Spacer()
            IssueLabelMenu(
                issue: issue,
                labels: labels,
                canEdit: true,
                canCreate: true,
                isPending: false,
                isEnabled: true,
                onSet: { _, _ in },
                onCreate: {}
            )
        }
        IssueLabelStatusView(
            text: IssueLabelMessages.mutation(.forbidden),
            systemImage: "exclamationmark.triangle",
            retry: nil
        )
        IssueLabelStatusView(
            text: "Labels are read-only in this repository. Your GitHub account can view them but not change them.",
            systemImage: "lock",
            retry: nil
        )
    }
    .frame(width: WorkbenchMetrics.sidePanelWidth)
    .padding()
}

#Preview("Create Repository Label") {
    IssueLabelCreationSheet(
        repositoryName: "mourato/GitMenuBar",
        isSaving: false,
        errorMessage: nil,
        onCancel: {},
        onCreate: { _, _, _ in }
    )
}
