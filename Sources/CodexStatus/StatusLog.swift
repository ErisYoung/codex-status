import Foundation

/// Tiny append-only log for diagnosing notification issues on the user's machine.
enum StatusLog {
    private static let fileURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/CodexStatus.log")

    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
