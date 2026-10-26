import Foundation

/// Two JSON files in the app group container, each written atomically (temp file + rename):
/// `state.json` (hot state, every process, guarded by `state.lock`) and `history.json` (written by
/// the app and the monitor extension, only while they hold `state.lock`).
/// A corrupt file is never overwritten in place: the app moves it aside to `<name>.corrupt.json`
/// and starts fresh, extensions leave it alone. Files are written without data protection so the monitor
/// extension can read them before the first unlock after a reboot (contents are opaque tokens
/// and counters).
public struct AppGroupStateStore: StateStore {
    public static let appGroupIdentifier = "group.art.stillh.notime"

    public enum StoreError: Error, Equatable {
        case containerUnavailable
        /// App only: the file was corrupt and has been moved aside; the next load starts fresh.
        case corruptFileMovedAside
    }

    /// nil when the app group container is unavailable; the store then reports `unavailable`.
    public let directory: URL?
    public let role: StateStoreRole

    public init(directory: URL?, role: StateStoreRole) {
        self.directory = directory
        self.role = role
    }

    public static func shared(role: StateStoreRole) -> AppGroupStateStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        if container == nil {
            NotimeLog.persistence.fault("App group container unavailable; state is unavailable")
        }
        return AppGroupStateStore(directory: container, role: role)
    }

    public var stateFileURL: URL? { directory?.appendingPathComponent("state.json") }
    public var corruptStateFileURL: URL? { directory?.appendingPathComponent("state.corrupt.json") }
    public var historyFileURL: URL? { directory?.appendingPathComponent("history.json") }
    var corruptHistoryFileURL: URL? { directory?.appendingPathComponent("history.corrupt.json") }
    private var lock: StateFileLock? { directory.map { StateFileLock(fileURL: $0.appendingPathComponent("state.lock")) } }

    // MARK: Hot state

    public func load() -> LoadResult<NotimeState> {
        guard let fileURL = stateFileURL, let corruptURL = corruptStateFileURL, let lock = prepareLock() else {
            return .unavailable(StoreError.containerUnavailable)
        }
        do {
            return try lock.withLock { read(NotimeState.self, from: fileURL, corruptURL: corruptURL) }
        } catch {
            fail(String(describing: error))
            return .unavailable(error)
        }
    }

    /// Reads without the lock, never writes, never recovers. Safe because every writer
    /// replaces the file atomically; used to render the shield where writing may be denied.
    public func loadWithoutLock() -> LoadResult<NotimeState> {
        guard let fileURL = stateFileURL else {
            fail("app group container not found")
            return .unavailable(StoreError.containerUnavailable)
        }
        return read(NotimeState.self, from: fileURL, corruptURL: nil)
    }

    public func modify<Result>(
        _ change: (inout NotimeState) -> Result,
        afterSave: (_ saved: NotimeState, _ replacedCorruptFile: Bool) -> Void
    ) -> Result? {
        guard let fileURL = stateFileURL, let corruptURL = corruptStateFileURL, let lock = prepareLock() else {
            return nil
        }
        do {
            return try lock.withLock { () -> Result? in
                guard let saved = modifyFile(
                    at: fileURL,
                    corruptURL: corruptURL,
                    emptyValue: role == .app ? NotimeState() : nil,
                    change
                ) else { return nil }
                afterSave(saved.value, saved.replacedCorruptFile)
                return saved.result
            }
        } catch {
            fail(String(describing: error))
            return nil
        }
    }

    // MARK: History (no lock of its own; written only under the state lock)

    public func loadHistory() -> LoadResult<UsageHistory> {
        guard let fileURL = historyFileURL, let corruptURL = corruptHistoryFileURL else {
            return .unavailable(StoreError.containerUnavailable)
        }
        return read(UsageHistory.self, from: fileURL, corruptURL: corruptURL)
    }

    public func modifyHistory<Result>(_ change: (inout UsageHistory) -> Result) -> Result? {
        guard let fileURL = historyFileURL, let corruptURL = corruptHistoryFileURL else { return nil }
        return modifyFile(at: fileURL, corruptURL: corruptURL, emptyValue: UsageHistory(), change)?.result
    }

    // MARK: Files

    private func prepareLock() -> StateFileLock? {
        guard let directory, let lock else {
            fail("app group container not found")
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return lock
    }

    /// Starts from `emptyValue` when the file is missing, or (app only) when it was corrupt and
    /// has just been moved aside. Without an `emptyValue` both cases are unavailable.
    private func modifyFile<Value: Codable, Result>(
        at fileURL: URL,
        corruptURL: URL,
        emptyValue: Value?,
        _ change: (inout Value) -> Result
    ) -> (value: Value, result: Result, replacedCorruptFile: Bool)? {
        var value: Value
        var replacedCorruptFile = false
        switch read(Value.self, from: fileURL, corruptURL: corruptURL) {
        case .loaded(let loaded): value = loaded
        case .empty:
            guard let emptyValue else {
                fail("read: \(fileURL.lastPathComponent) does not exist yet")
                return nil
            }
            value = emptyValue
        case .unavailable(let error):
            guard error as? StoreError == .corruptFileMovedAside, let emptyValue else { return nil }
            value = emptyValue
            replacedCorruptFile = true
        }
        let result = change(&value)
        return write(value, to: fileURL) ? (value, result, replacedCorruptFile) : nil
    }

    /// A corrupt file is moved to `corruptURL` only by the app, and only when one is given.
    private func read<Value: Decodable>(_ type: Value.Type, from fileURL: URL, corruptURL: URL?) -> LoadResult<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch where Self.isFileMissing(error) {
            return .empty
        } catch {
            fail("read \(fileURL.lastPathComponent) failed: \(Self.describe(error))")
            return .unavailable(error)
        }
        do {
            return .loaded(try JSONDecoder().decode(Value.self, from: data))
        } catch {
            fail("decode \(fileURL.lastPathComponent) failed: \(Self.describe(error))")
            guard role == .app, let corruptURL else { return .unavailable(error) }
            moveAside(fileURL, to: corruptURL)
            return .unavailable(StoreError.corruptFileMovedAside)
        }
    }

    private func write<Value: Encodable>(_ value: Value, to fileURL: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(value).write(to: fileURL, options: Self.writingOptions)
            return true
        } catch {
            fail("write \(fileURL.lastPathComponent) failed: \(Self.describe(error))")
            return false
        }
    }

    #if os(iOS)
    private static let writingOptions: Data.WritingOptions = [.atomic, .noFileProtection]
    #else
    private static let writingOptions: Data.WritingOptions = [.atomic]
    #endif

    private func moveAside(_ fileURL: URL, to corruptURL: URL) {
        do {
            try? FileManager.default.removeItem(at: corruptURL)
            try FileManager.default.moveItem(at: fileURL, to: corruptURL)
        } catch {
            NotimeLog.persistence.error("Could not move corrupt file aside: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Logs a failed step.
    private func fail(_ message: String) {
        NotimeLog.persistence.error("\(message, privacy: .public)")
    }

    /// `domain code: description`, so the log names the exact error.
    static func describe(_ error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }

    private static func isFileMissing(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError { return true }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT) { return true }
        return false
    }
}
