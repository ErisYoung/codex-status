import Foundation

/// The derived status shown in the menu bar.
public struct TaskStatusSnapshot: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case idle
        case working
        case stalled
        case completed
        case interrupted
    }

    public let kind: Kind
    /// First user message of the current/latest task, used as a short preview.
    public let preview: String?
    /// Extra detail: last agent message for `.completed`, abort reason for `.interrupted`.
    public let detail: String?
    public let startedAt: Date?
    public let durationMs: Int?
    public let lastActivityAt: Date?
    public let trackedFileURL: URL?

    public init(
        kind: Kind,
        preview: String? = nil,
        detail: String? = nil,
        startedAt: Date? = nil,
        durationMs: Int? = nil,
        lastActivityAt: Date? = nil,
        trackedFileURL: URL? = nil
    ) {
        self.kind = kind
        self.preview = preview
        self.detail = detail
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.lastActivityAt = lastActivityAt
        self.trackedFileURL = trackedFileURL
    }

    public static let idle = TaskStatusSnapshot(kind: .idle)
}

/// A live task event emitted while watching (after `SessionLogWatcher.startWatching()`).
public struct TaskEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started
        case completed
        case interrupted
    }

    public let kind: Kind
    public let occurredAt: Date
    public let preview: String?
    public let detail: String?
    public let durationMs: Int?

    public init(
        kind: Kind,
        occurredAt: Date,
        preview: String? = nil,
        detail: String? = nil,
        durationMs: Int? = nil
    ) {
        self.kind = kind
        self.occurredAt = occurredAt
        self.preview = preview
        self.detail = detail
        self.durationMs = durationMs
    }
}
