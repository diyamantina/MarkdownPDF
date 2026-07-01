enum SourceCodeTokenKind: Equatable {
    case text
    case keyword
    case identifier
    case string
    case number
    case comment
    case operatorToken
    case punctuation
    case error
}
