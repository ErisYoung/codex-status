import Foundation

/// Per-session-log state machine derived from `event_msg` lines.
final class FileTurnState {
    enum Phase: Equatable {
        case idle
        case working
        case completed
        case interrupted
    }

    private(set) var phase: Phase = .idle
    private(set) var currentTurnId: String?
    private(set) var startedAt: Date?
    private(set) var preview: String?
    private(set) var lastAgentMessage: String?
    private(set) var abortReason: String?
    private(set) var durationMs: Int?
    private(set) var lastActivityAt: Date?

    func reset() {
        phase = .idle
        currentTurnId = nil
        startedAt = nil
        preview = nil
        lastAgentMessage = nil
        abortReason = nil
        durationMs = nil
        lastActivityAt = nil
    }

    /// Applies one parsed log line. Returns a task event for terminal
    /// transitions (`task_complete` / `turn_aborted`), or `nil`.
    @discardableResult
    func apply(line: SessionLogLine, now: Date) -> TaskEvent? {
        let lineDate = line.timestamp.flatMap(LogTimestamp.parse) ?? now
        lastActivityAt = max(lastActivityAt ?? lineDate, lineDate)

        guard line.type == "event_msg", let payload = line.payload, let kind = payload.type else {
            return nil
        }

        switch kind {
        case "task_started":
            currentTurnId = payload.turnId
            phase = .working
            startedAt = payload.startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            preview = nil
            lastAgentMessage = nil
            abortReason = nil
            durationMs = nil
            return TaskEvent(kind: .started, occurredAt: lineDate, preview: nil)

        case "user_message":
            if preview == nil, let message = payload.message, !message.isEmpty {
                preview = message
            }
            return nil

        case "agent_message":
            if let message = payload.message, !message.isEmpty {
                lastAgentMessage = message
            }
            return nil

        case "task_complete":
            guard currentTurnId == nil || currentTurnId == payload.turnId else { return nil }
            phase = .completed
            if let ms = payload.durationMs {
                durationMs = ms
            }
            if let message = payload.lastAgentMessage, !message.isEmpty {
                lastAgentMessage = message
            }
            return TaskEvent(
                kind: .completed,
                occurredAt: lineDate,
                preview: preview,
                detail: lastAgentMessage,
                durationMs: durationMs
            )

        case "turn_aborted":
            guard currentTurnId == nil || currentTurnId == payload.turnId else { return nil }
            phase = .interrupted
            abortReason = payload.reason
            if let ms = payload.durationMs {
                durationMs = ms
            }
            return TaskEvent(
                kind: .interrupted,
                occurredAt: lineDate,
                preview: preview,
                detail: payload.reason,
                durationMs: durationMs
            )

        default:
            return nil
        }
    }
}
