import Foundation

/// A repository label typed in the creation sheet, trimmed and with the color
/// in the six-digit form GitHub expects. GitHub limits a name to 50
/// characters and a description to 100.
struct IssueLabelDraft: Equatable, Sendable {
    static let maximumNameLength = 50
    static let maximumDescriptionLength = 100

    let name: String
    /// Six lowercase hexadecimal digits without `#`.
    let color: String
    let description: String?

    enum ValidationError: Error, Equatable, Sendable {
        case nameRequired
        case nameTooLong
        case nameTaken
        case colorInvalid
        case descriptionTooLong
    }

    /// Checks every field before any request runs. `existingNames` holds the
    /// repository labels already shown in the picker, compared without case
    /// because GitHub treats label names that way.
    static func make(
        name: String,
        color: String,
        description: String,
        existingNames: [String] = []
    ) throws(ValidationError) -> IssueLabelDraft {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .nameRequired }
        guard name.count <= maximumNameLength else { throw .nameTooLong }
        guard !existingNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw .nameTaken
        }
        guard let color = normalizedColor(color) else { throw .colorInvalid }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard description.count <= maximumDescriptionLength else { throw .descriptionTooLong }
        return IssueLabelDraft(
            name: name,
            color: color,
            description: description.isEmpty ? nil : description
        )
    }

    /// Accepts GitHub's hex forms (`d73a4a` or `#D73A4A`) and returns the six
    /// lowercase digits the API expects.
    static func normalizedColor(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return digits.lowercased()
    }
}

/// Why creating a label did not reach the repository. A validation problem
/// stays on the form; a repository problem comes back from GitHub.
enum IssueLabelCreationError: Error, Equatable, Sendable {
    case validation(IssueLabelDraft.ValidationError)
    case repository(GitHubIssueLabelError)
}
