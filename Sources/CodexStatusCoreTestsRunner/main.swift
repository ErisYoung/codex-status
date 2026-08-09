import Foundation
@testable import CodexStatusCore

// Plain assertion harness — XCTest/swift-testing are unavailable in the
// CommandLineTools-only environment, so tests run as a standalone executable.

var total = 0
var failures = 0

@MainActor
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    total += 1
    if condition() {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

@MainActor
func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    check(actual == expected, "\(name) (expected \(expected), got \(actual))")
}

// MARK: - FileTurnState

let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func makeLine(
    type: String,
    payloadType: String?,
    turnId: String? = nil,
    startedAt: Int? = nil,
    durationMs: Int? = nil,
    reason: String? = nil,
    message: String? = nil,
    lastAgentMessage: String? = nil,
    timestamp: String? = "2026-08-08T00:00:00.000Z"
) -> SessionLogLine {
    SessionLogLine(
        timestamp: timestamp,
        type: type,
        payload: .init(
            type: payloadType,
            threadSource: nil,
            turnId: turnId,
            startedAt: startedAt,
            completedAt: nil,
            durationMs: durationMs,
            reason: reason,
            message: message,
            phase: nil,
            lastAgentMessage: lastAgentMessage
        )
    )
}

@MainActor
func testFileTurnState() {
    do {
        let state = FileTurnState()
        let event = state.apply(
            line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t1", startedAt: 1_700_000_000),
            now: t0
        )
        checkEqual(state.phase, .working, "task_started -> working")
        checkEqual(state.currentTurnId, "t1", "task_started sets turn id")
        checkEqual(state.startedAt, Date(timeIntervalSince1970: 1_700_000_000), "task_started sets startedAt")
        checkEqual(event?.kind, .started, "task_started emits started event")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started"), now: t0)
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "user_message", message: "帮我修个 bug"), now: t0)
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "user_message", message: "第二条"), now: t0)
        checkEqual(state.preview, "帮我修个 bug", "user_message sets preview only once")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t1"), now: t0)
        _ = state.apply(
            line: makeLine(
                type: "event_msg",
                payloadType: "agent_message",
                message: "已修复",
                timestamp: "2026-08-08T00:00:05.000Z"
            ),
            now: t0
        )
        let event = state.apply(
            line: makeLine(
                type: "event_msg",
                payloadType: "task_complete",
                turnId: "t1",
                durationMs: 5000,
                lastAgentMessage: "已修复",
                timestamp: "2026-08-08T00:00:05.000Z"
            ),
            now: t0
        )
        checkEqual(state.phase, .completed, "task_complete -> completed")
        checkEqual(event?.kind, .completed, "task_complete emits completed event")
        checkEqual(event?.detail, "已修复", "completed event carries last agent message")
        checkEqual(event?.durationMs, 5000, "completed event carries duration")
        checkEqual(event?.occurredAt, LogTimestamp.parse("2026-08-08T00:00:05.000Z"), "completed event occurredAt parsed")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t1"), now: t0)
        let event = state.apply(
            line: makeLine(type: "event_msg", payloadType: "turn_aborted", turnId: "t1", reason: "interrupted"),
            now: t0
        )
        checkEqual(state.phase, .interrupted, "turn_aborted -> interrupted")
        checkEqual(state.abortReason, "interrupted", "turn_aborted stores reason")
        checkEqual(event?.kind, .interrupted, "turn_aborted emits interrupted event")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t1"), now: t0)
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_complete", turnId: "t1"), now: t0)
        checkEqual(state.phase, .completed, "multi-turn: first completes")
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t2"), now: t0)
        checkEqual(state.phase, .working, "multi-turn: new task starts working")
        check(state.preview == nil, "multi-turn: preview resets")
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "turn_aborted", turnId: "t2", reason: "steered"), now: t0)
        checkEqual(state.phase, .interrupted, "multi-turn: second aborts")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t1"), now: t0)
        let event = state.apply(line: makeLine(type: "event_msg", payloadType: "task_complete", turnId: "t999"), now: t0)
        check(event == nil, "completion for other turn ignored")
        checkEqual(state.phase, .working, "phase unchanged for other turn completion")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "token_count", timestamp: "2026-08-08T00:00:01.000Z"), now: t0)
        checkEqual(state.lastActivityAt, LogTimestamp.parse("2026-08-08T00:00:01.000Z"), "activity updates lastActivityAt")
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "token_count", timestamp: "2026-08-08T00:00:03.000Z"), now: t0)
        checkEqual(state.lastActivityAt, LogTimestamp.parse("2026-08-08T00:00:03.000Z"), "lastActivityAt advances")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "response_item", payloadType: "reasoning", timestamp: "2026-08-08T00:00:01.000Z"), now: t0)
        checkEqual(state.phase, .idle, "non-event line keeps phase idle")
        check(state.lastActivityAt != nil, "non-event line counts as activity")
    }

    do {
        let state = FileTurnState()
        _ = state.apply(line: makeLine(type: "event_msg", payloadType: "task_started", turnId: "t1"), now: t0)
        state.reset()
        checkEqual(state.phase, .idle, "reset -> idle")
        check(state.currentTurnId == nil && state.lastActivityAt == nil, "reset clears state")
    }
}

// MARK: - SessionLogWatcher

final class ClockBox {
    var current: Date
    init(_ date: Date) { current = date }
}

struct WatcherContext {
    let directory: URL
    let watcher: SessionLogWatcher
    let clock: ClockBox
}

func makeContext() throws -> WatcherContext {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-status-runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let clock = ClockBox(Date(timeIntervalSince1970: 1_700_000_000))
    let watcher = SessionLogWatcher(sessionsDirectory: directory, staleAfter: 600, idleWindow: 1800)
    watcher.now = { [clock] in clock.current }
    watcher.startWatching()
    return WatcherContext(directory: directory, watcher: watcher, clock: clock)
}

func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func line(timestamp: Date, type: String, payload: String) -> String {
    "{\"timestamp\":\"\(iso(timestamp))\",\"type\":\"\(type)\",\"payload\":\(payload)}"
}

func startedPayload(turnId: String = "t1", startedAt: Int) -> String {
    "{\"type\":\"task_started\",\"turn_id\":\"\(turnId)\",\"started_at\":\(startedAt)}"
}

func sessionMeta(threadSource: String) -> String {
    "{\"type\":\"session_meta\",\"payload\":{\"thread_source\":\"\(threadSource)\"}}"
}

func activityPayload() -> String {
    "{\"type\":\"token_count\",\"turn_id\":\"t1\"}"
}

func userMessagePayload(_ message: String) -> String {
    "{\"type\":\"user_message\",\"message\":\"\(message)\"}"
}

func completePayload(turnId: String = "t1", durationMs: Int, lastAgentMessage: String? = nil) -> String {
    let message = lastAgentMessage.map { ",\"last_agent_message\":\"\($0)\"" } ?? ""
    return "{\"type\":\"task_complete\",\"turn_id\":\"\(turnId)\",\"duration_ms\":\(durationMs)\(message)}"
}

func abortPayload(turnId: String = "t1", reason: String) -> String {
    "{\"type\":\"turn_aborted\",\"turn_id\":\"\(turnId)\",\"reason\":\"\(reason)\"}"
}

func write(_ ctx: WatcherContext, _ name: String, lines: [String]) throws {
    let url = ctx.directory.appendingPathComponent(name)
    try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: url)
}

func append(_ ctx: WatcherContext, _ name: String, lines: [String]) throws {
    let url = ctx.directory.appendingPathComponent(name)
    let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8)!
    if FileManager.default.fileExists(atPath: url.path) {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    } else {
        try data.write(to: url)
    }
}

@MainActor
func testWatcher() throws {
    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(1), type: "event_msg", payload: userMessagePayload("帮我写个脚本")),
            line(timestamp: ctx.clock.current.addingTimeInterval(2), type: "event_msg", payload: activityPayload())
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: working snapshot")
        checkEqual(ctx.watcher.currentSnapshot.preview, "帮我写个脚本", "watcher: preview captured")
    }

    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(5), type: "event_msg", payload: completePayload(durationMs: 5000, lastAgentMessage: "已完成"))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .completed, "watcher: completed snapshot")
        checkEqual(ctx.watcher.currentSnapshot.detail, "已完成", "watcher: completed detail")
    }

    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(5), type: "event_msg", payload: abortPayload(reason: "interrupted"))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .interrupted, "watcher: interrupted snapshot")
        checkEqual(ctx.watcher.currentSnapshot.detail, "interrupted", "watcher: interrupted reason")
    }

    do {
        let ctx = try makeContext()
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .idle, "watcher: idle with no files")
    }

    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(1), type: "event_msg", payload: activityPayload())
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: working before stall")
        ctx.clock.current = ctx.clock.current.addingTimeInterval(700)
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .stalled, "watcher: stale working -> stalled")
    }

    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(5), type: "event_msg", payload: completePayload(durationMs: 5000))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .completed, "watcher: completed before idle")
        ctx.clock.current = ctx.clock.current.addingTimeInterval(2000)
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .idle, "watcher: completed falls idle after window")
    }

    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(turnId: "a", startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(1), type: "event_msg", payload: userMessagePayload("任务 A"))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.preview, "任务 A", "watcher: file A active")

        ctx.clock.current = ctx.clock.current.addingTimeInterval(60)
        try write(ctx, "rollout-b.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(turnId: "b", startedAt: 1_700_000_060)),
            line(timestamp: ctx.clock.current.addingTimeInterval(1), type: "event_msg", payload: userMessagePayload("任务 B"))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.preview, "任务 B", "watcher: switches to newer file")
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: newer file working")
    }

    do {
        let ctx = try makeContext()
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: incremental working")
        ctx.clock.current = ctx.clock.current.addingTimeInterval(10)
        try append(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: completePayload(durationMs: 10000))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .completed, "watcher: incremental completion detected")
    }

    do {
        let ctx = try makeContext()
        let url = ctx.directory.appendingPathComponent("rollout-a.jsonl")
        let content = """
        {"broken json
        \(line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)))

        """
        try content.data(using: .utf8)!.write(to: url)
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: malformed line skipped")
    }

    do {
        let ctx = try makeContext()
        let url = ctx.directory.appendingPathComponent("rollout-a.jsonl")
        let firstChunk = line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000))
            + "\n"
            + "{\"timestamp\":\"\(iso(ctx.clock.current.addingTimeInterval(1)))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"t1\""
        try firstChunk.data(using: .utf8)!.write(to: url)
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: partial trailing line tolerated")

        ctx.clock.current = ctx.clock.current.addingTimeInterval(2)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: ",\"duration_ms\":2000}}\n".data(using: .utf8)!)
        try handle.close()
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .completed, "watcher: partial line completed on next poll")
        checkEqual(ctx.watcher.currentSnapshot.durationMs, 2000, "watcher: partial completion duration parsed")
    }

    do {
        let ctx = try makeContext()
        var events: [TaskEvent] = []
        ctx.watcher.onTaskEvent = { events.append($0) }

        let oldClock = ctx.clock.current.addingTimeInterval(-3600)
        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: oldClock, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000 - 3600)),
            line(timestamp: oldClock.addingTimeInterval(5), type: "event_msg", payload: completePayload(durationMs: 5000))
        ])
        ctx.watcher.poll(pollInterval: 0)
        check(events.isEmpty, "watcher: backfill completion suppressed")

        ctx.clock.current = ctx.clock.current.addingTimeInterval(30)
        try append(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(5), type: "event_msg", payload: completePayload(durationMs: 5000))
        ])
        ctx.watcher.poll(pollInterval: 0)
        let completions = events.filter { $0.kind == .completed }
        checkEqual(completions.count, 1, "watcher: live completion emitted")
        checkEqual(completions.first?.kind, .completed, "watcher: live event kind")
    }

    do {
        let ctx = try makeContext()
        var updates = 0
        ctx.watcher.onUpdate = { _ in updates += 1 }

        try write(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000))
        ])
        ctx.watcher.poll(pollInterval: 2)
        checkEqual(updates, 1, "watcher: first poll emits update")
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: throttled working")

        ctx.clock.current = ctx.clock.current.addingTimeInterval(1)
        try append(ctx, "rollout-a.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "event_msg", payload: completePayload(durationMs: 1000))
        ])
        ctx.watcher.poll(pollInterval: 2)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: poll throttled, still working")
        checkEqual(updates, 1, "watcher: no update while throttled")

        ctx.clock.current = ctx.clock.current.addingTimeInterval(2)
        ctx.watcher.poll(pollInterval: 2)
        checkEqual(ctx.watcher.currentSnapshot.kind, .completed, "watcher: completion after throttle window")
        checkEqual(updates, 2, "watcher: update emitted after throttle window")
    }

    do {
        // A subagent/guardian thread must not drive the displayed status.
        let ctx = try makeContext()
        try write(ctx, "rollout-guardian.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "session_meta", payload: "{\"thread_source\":\"subagent\"}"),
            line(timestamp: ctx.clock.current.addingTimeInterval(1), type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(2), type: "event_msg", payload: completePayload(durationMs: 2000))
        ])
        try write(ctx, "rollout-user.jsonl", lines: [
            line(timestamp: ctx.clock.current.addingTimeInterval(10), type: "session_meta", payload: "{\"thread_source\":\"user\"}"),
            line(timestamp: ctx.clock.current.addingTimeInterval(11), type: "event_msg", payload: startedPayload(turnId: "u", startedAt: 1_700_000_000)),
            line(timestamp: ctx.clock.current.addingTimeInterval(12), type: "event_msg", payload: userMessagePayload("用户任务"))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .working, "watcher: subagent ignored, user task shown")
        checkEqual(ctx.watcher.currentSnapshot.preview, "用户任务", "watcher: preview from user task")
    }

    do {
        // When only a subagent thread is active, the status is idle.
        let ctx = try makeContext()
        try write(ctx, "rollout-guardian.jsonl", lines: [
            line(timestamp: ctx.clock.current, type: "session_meta", payload: "{\"thread_source\":\"subagent\"}"),
            line(timestamp: ctx.clock.current.addingTimeInterval(1), type: "event_msg", payload: startedPayload(startedAt: 1_700_000_000))
        ])
        ctx.watcher.poll(pollInterval: 0)
        checkEqual(ctx.watcher.currentSnapshot.kind, .idle, "watcher: subagent-only is idle")
    }
}

// MARK: - Run

testFileTurnState()
try testWatcher()

print("----")
print("\(total - failures)/\(total) checks passed")
exit(failures == 0 ? 0 : 1)
