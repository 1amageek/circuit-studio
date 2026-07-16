public enum SignoffPDKContextError: Error, Sendable, Hashable {
    case rootNotFound(profileID: String, requirementID: String)
}
