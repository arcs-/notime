import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A cross-process exclusive lock (`flock`) on a sidecar file. Held only for the few
/// milliseconds of a load-change-save, never across suspension points.
struct StateFileLock: Sendable {
    /// Which step failed and the `errno` it left.
    struct Failure: Error, CustomStringConvertible {
        let step: String
        let code: Int32

        var description: String {
            "\(step) failed: errno \(code) (\(String(cString: strerror(code))))"
        }
    }

    let fileURL: URL

    /// Throws without running `body` if the lock cannot be taken.
    func withLock<Result>(_ body: () -> Result) throws -> Result {
        let descriptor = open(fileURL.path, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure(step: "lock open", code: errno) }
        defer { close(descriptor) }
        #if os(iOS)
        // Readable before first unlock, like the state file it guards.
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: fileURL.path)
        #endif
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw Failure(step: "lock flock", code: errno) }
        }
        defer { flock(descriptor, LOCK_UN) }
        return body()
    }
}
