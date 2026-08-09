import Foundation

/// Tracks the most recently active Codex session log and derives a status snapshot.
public final class SessionLogWatcher {
    public let sessionsDirectory: URL
    public let staleAfter: TimeInterval
    public let idleWindow: TimeInterval
    /// Injectable clock for deterministic tests.
    public var now: () -> Date = { Date() }
    /// Called whenever the derived snapshot changes.
    public var onUpdate: ((TaskStatusSnapshot) -> Void)?
    /// Called when a live task completes or is interrupted (after `startWatching()`).
    public var onTaskEvent: ((TaskEvent) -> Void)?
    public private(set) var currentSnapshot = TaskStatusSnapshot.idle

    private var trackers: [URL: FileTracker] = [:]
    private var watchingSince: Date?
    private var lastPollAt: Date?

    public init(
        sessionsDirectory: URL,
        staleAfter: TimeInterval = 600,
        idleWindow: TimeInterval = 1800
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.staleAfter = staleAfter
        self.idleWindow = idleWindow
    }

    /// Marks the current time as the boundary after which task events are "live".
    /// Events parsed from older log lines are treated as backfill and suppressed.
    public func startWatching() {
        watchingSince = now()
    }

    /// Scans session logs and updates `currentSnapshot`. Call repeatedly from a timer.
    public func poll(pollInterval: TimeInterval = 2) {
        let current = now()
        if let last = lastPollAt, current.timeIntervalSince(last) < pollInterval {
            return
        }
        lastPollAt = current
        updateTrackers(now: current)
        publishSnapshot(now: current)
    }

    // MARK: - Discovery

    private func discoveredFiles() -> [(url: URL, mtime: Date, size: UInt64)] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: [(url: URL, mtime: Date, size: UInt64)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ])
            guard values?.isRegularFile == true else { continue }
            result.append((
                url,
                values?.contentModificationDate ?? .distantPast,
                UInt64(values?.fileSize ?? 0)
            ))
        }
        return result
    }

    private func updateTrackers(now: Date) {
        let files = discoveredFiles()
        let cutoff = now.addingTimeInterval(-idleWindow)

        // Create trackers for every discovered file so later writes are noticed.
        for file in files {
            if trackers[file.url] == nil {
                trackers[file.url] = FileTracker(url: file.url)
            }
        }

        // Drop trackers whose file no longer exists.
        trackers = trackers.filter { (url, _) in
            files.contains { $0.url == url }
        }

        // Reset trackers whose file shrank (replaced or truncated).
        for (url, tracker) in trackers {
            if let file = files.first(where: { $0.url == url }), file.size < tracker.offset {
                tracker.reset()
            }
        }

        // Choose the live file with the most recent activity.
        let live = files.compactMap { file -> (url: URL, mtime: Date, size: UInt64, tracker: FileTracker)? in
            guard let tracker = trackers[file.url] else { return nil }
            guard !tracker.isExcluded else { return nil }
            guard isLive(tracker, file: file, cutoff: cutoff) else { return nil }
            return (file.url, file.mtime, file.size, tracker)
        }
        // Parse the most recent live files until we have parsed a user-facing
        // one (subagent/guardian files are excluded once their meta is read).
        let sortedLive = live.sorted { activity(of: $0) > activity(of: $1) }
        for entry in sortedLive {
            let tracker = entry.tracker
            if !tracker.fullyParsed {
                readAndParse(tracker, now: now, full: true)
                tracker.fullyParsed = true
            } else {
                readAndParse(tracker, now: now, full: false)
            }
            if !tracker.isExcluded {
                break
            }
        }

        // Incrementally read other already-parsed user files so background
        // completions are noticed as soon as they become the newest activity.
        for (url, tracker) in trackers where tracker.fullyParsed && !tracker.isExcluded {
            readAndParse(tracker, now: now, full: false)
            _ = url
        }
    }

    private func isLive(_ tracker: FileTracker, file: (url: URL, mtime: Date, size: UInt64), cutoff: Date) -> Bool {
        if file.mtime >= cutoff { return true }
        if file.size > tracker.offset { return true }
        return (tracker.lastEventAt ?? .distantPast) >= cutoff
    }

    private func activity(of entry: (url: URL, mtime: Date, size: UInt64, tracker: FileTracker)) -> Date {
        // Unread bytes mean the file was written recently; mtime is the write time.
        if entry.size > entry.tracker.offset {
            return entry.mtime
        }
        return entry.tracker.lastEventAt ?? entry.mtime
    }

    // MARK: - Reading

    private func readAndParse(_ tracker: FileTracker, now: Date, full: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: tracker.url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if full {
            tracker.offset = 0
            tracker.partialLine = ""
            tracker.state.reset()
        } else if size < tracker.offset {
            return
        }
        guard size > tracker.offset else { return }

        try? handle.seek(toOffset: tracker.offset)
        guard let data = try? handle.read(upToCount: Int(size - tracker.offset)) else { return }
        tracker.offset = size
        guard let text = String(data: data, encoding: .utf8) else { return }

        let pending = tracker.partialLine + text
        let lines = pending.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if pending.hasSuffix("\n") {
            tracker.partialLine = ""
            parse(lines, tracker: tracker, now: now)
        } else if lines.isEmpty {
            tracker.partialLine = pending
        } else {
            tracker.partialLine = lines.last ?? ""
            parse(Array(lines.dropLast()), tracker: tracker, now: now)
        }
    }

    private func parse(_ lines: [String], tracker: FileTracker, now: Date) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let line = try? decoder.decode(SessionLogLine.self, from: data) else { continue }
            if line.type == "session_meta", tracker.threadSource == nil {
                tracker.threadSource = line.payload?.threadSource
            }
            if let event = tracker.state.apply(line: line, now: now) {
                emit(event)
            }
        }
    }

    private func emit(_ event: TaskEvent) {
        if let since = watchingSince, event.occurredAt >= since {
            onTaskEvent?(event)
        }
    }

    // MARK: - Snapshot

    private func publishSnapshot(now: Date) {
        let snapshot = computeSnapshot(now: now)
        if snapshot != currentSnapshot {
            currentSnapshot = snapshot
            onUpdate?(snapshot)
        }
    }

    private func computeSnapshot(now: Date) -> TaskStatusSnapshot {
        let cutoff = now.addingTimeInterval(-idleWindow)
        var best: (tracker: FileTracker, activity: Date)?
        for (_, tracker) in trackers {
            guard !tracker.isExcluded else { continue }
            guard let last = tracker.lastEventAt, last >= cutoff else { continue }
            if best == nil || last > best!.activity {
                best = (tracker, last)
            }
        }
        guard let top = best else { return .idle }

        let state = top.tracker.state
        let url = top.tracker.url
        switch state.phase {
        case .idle:
            return .idle
        case .working:
            if now.timeIntervalSince(top.activity) > staleAfter {
                return TaskStatusSnapshot(
                    kind: .stalled,
                    preview: state.preview,
                    startedAt: state.startedAt,
                    lastActivityAt: top.activity,
                    trackedFileURL: url
                )
            }
            return TaskStatusSnapshot(
                kind: .working,
                preview: state.preview,
                startedAt: state.startedAt,
                lastActivityAt: top.activity,
                trackedFileURL: url
            )
        case .completed:
            return TaskStatusSnapshot(
                kind: .completed,
                preview: state.preview,
                detail: state.lastAgentMessage,
                durationMs: state.durationMs,
                lastActivityAt: top.activity,
                trackedFileURL: url
            )
        case .interrupted:
            return TaskStatusSnapshot(
                kind: .interrupted,
                preview: state.preview,
                detail: state.abortReason,
                durationMs: state.durationMs,
                lastActivityAt: top.activity,
                trackedFileURL: url
            )
        }
    }
}

/// Incremental reader state for one session log file.
final class FileTracker {
    let url: URL
    var offset: UInt64 = 0
    var partialLine = ""
    var fullyParsed = false
    var threadSource: String?
    let state = FileTurnState()

    init(url: URL) {
        self.url = url
    }

    var lastEventAt: Date? {
        state.lastActivityAt
    }

    /// Internal sub-threads (guardian/approval, spawned agents) are not
    /// user-facing tasks and must not drive the menu bar status.
    var isExcluded: Bool {
        threadSource == "subagent"
    }

    func reset() {
        offset = 0
        partialLine = ""
        fullyParsed = false
        state.reset()
    }
}
