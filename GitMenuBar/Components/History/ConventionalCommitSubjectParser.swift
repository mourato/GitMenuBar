struct ConventionalCommitSubject: Equatable {
    let type: String?
    let scope: String?
    let subject: String
}

enum ConventionalCommitSubjectParser {
    static let knownTypes: Set<String> = [
        "build",
        "chore",
        "ci",
        "docs",
        "feat",
        "fix",
        "perf",
        "refactor",
        "revert",
        "style",
        "test"
    ]

    static func parse(_ value: String) -> ConventionalCommitSubject {
        guard let delimiter = value.firstIndex(of: ":") else {
            return ConventionalCommitSubject(type: nil, scope: nil, subject: value)
        }

        let prefix = value[..<delimiter]
        guard let parsedPrefix = parsePrefix(prefix) else {
            return ConventionalCommitSubject(type: nil, scope: nil, subject: value)
        }

        let subjectStart = value.index(after: delimiter)
        let subject = value[subjectStart...].drop(while: \.isWhitespace)

        return ConventionalCommitSubject(
            type: parsedPrefix.type,
            scope: parsedPrefix.scope,
            subject: String(subject)
        )
    }

    static func isKnownType(_ type: String) -> Bool {
        knownTypes.contains(type)
    }

    private static func parsePrefix(_ prefix: Substring) -> (type: String, scope: String?)? {
        var prefix = prefix
        if prefix.last == "!" {
            prefix = prefix.dropLast()
        }

        guard !prefix.isEmpty else {
            return nil
        }

        let type: Substring
        let scope: String?

        if let openingParenthesis = prefix.firstIndex(of: "(") {
            guard prefix.last == ")" else {
                return nil
            }

            let closingParenthesis = prefix.index(before: prefix.endIndex)
            let parsedScope = prefix[prefix.index(after: openingParenthesis) ..< closingParenthesis]
            guard !parsedScope.isEmpty, !parsedScope.contains(")") else {
                return nil
            }

            type = prefix[..<openingParenthesis]
            scope = String(parsedScope)
        } else {
            type = prefix
            scope = nil
        }

        guard isValidType(type) else {
            return nil
        }

        return (String(type), scope)
    }

    private static func isValidType(_ type: Substring) -> Bool {
        guard let firstCharacter = type.first,
              firstCharacter.isLetter
        else {
            return false
        }

        return type.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-"
        }
    }
}
