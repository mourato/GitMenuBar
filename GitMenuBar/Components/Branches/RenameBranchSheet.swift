import SwiftUI

struct RenameBranchSheet: View {
    let oldBranchName: String
    @Binding var newBranchName: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onRename: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Branch")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("New name for '\(oldBranchName)':")
                    .foregroundColor(.secondary)

                TextField("new-branch-name", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(onRename)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename", action: onRename)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newBranchName == oldBranchName)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

private struct RenameBranchSheetPreviewContainer: View {
    @State private var branchName = "feature/new-menu"

    var body: some View {
        RenameBranchSheet(
            oldBranchName: "feature/menu",
            newBranchName: $branchName,
            errorMessage: nil,
            onCancel: {},
            onRename: {}
        )
    }
}

#Preview("Rename Branch Sheet") {
    RenameBranchSheetPreviewContainer()
}
