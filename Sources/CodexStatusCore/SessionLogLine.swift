import Foundation

/// One JSONL line of a Codex session rollout. Only `event_msg` lines drive the
/// state machine; other lines still count as activity.
struct SessionLogLine: Decodable {
    let timestamp: String?
    let type: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let threadSource: String?
        let turnId: String?
        let startedAt: Int?
        let completedAt: Int?
        let durationMs: Int?
        let reason: String?
        let message: String?
        let phase: String?
        let lastAgentMessage: String?
    }
}

/// Parses the ISO-8601 timestamps written by Codex (e.g. `2026-08-08T13:54:58.464Z`).
enum LogTimestamp {
    static func parse(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }
        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: string)
    }
}
