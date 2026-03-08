import SwiftUI

struct RenameBranchSheet: View {
    let oldBranchName: String
    @Binding var newBranchName: String
    let onCancel: () -> Void
    let onRename: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Branch")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("New name for '\(oldBranchName)':")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("new-branch-name", text: $newBranchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(onRename)
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Rename", action: onRename)
                    .buttonStyle(.borderedProminent)
                    .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newBranchName == oldBranchName)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
