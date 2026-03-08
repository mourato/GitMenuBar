import SwiftUI

struct CreateBranchSheet: View {
    @Binding var branchName: String
    let currentBranch: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Branch")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Branch Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("feature/new-feature", text: $branchName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        if !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onCreate()
                        }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }

                Text("Will branch from: \(currentBranch)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Create", action: onCreate)
                    .buttonStyle(.borderless)
                    .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
