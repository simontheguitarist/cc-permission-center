import Foundation

struct PermissionRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionId: String
    let projectLabel: String
    let terminalDisplay: String?
    let toolName: String
    let toolInput: String           // pretty-printed JSON, used as fallback
    let toolInputJSON: String       // raw JSON string for per-tool rendering
    let cwd: String

    enum Decision: String, Sendable {
        case approve
        case deny
        case ask
    }
}
