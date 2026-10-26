/// Persistence for the hot state (shared by all processes) and the usage history.
/// Implementations never throw; failures surface as `unavailable` / nil so callers fail closed.
public protocol StateStore: Sendable {
    func load() -> LoadResult<NotimeState>

    /// Reads without taking the lock and without ever writing or recovering.
    func loadWithoutLock() -> LoadResult<NotimeState>

    /// Load, change, save, then `afterSave`, all under one cross-process lock, so side effects
    /// (shields, monitoring) are applied from exactly the state that was saved, before any other
    /// process can change it. `afterSave` gets the saved state and whether it replaced a corrupt
    /// file (app only: the corrupt file is moved aside and the change runs on a fresh state).
    /// When the state is unavailable, `change` is not called, nothing is written, and nil is
    /// returned. Also nil (and no `afterSave`) if the save fails.
    /// `afterSave` must not call back into the store's locked operations.
    func modify<Result>(
        _ change: (inout NotimeState) -> Result,
        afterSave: (_ saved: NotimeState, _ replacedCorruptFile: Bool) -> Void
    ) -> Result?

    /// Lock-free read. History files are only replaced atomically.
    func loadHistory() -> LoadResult<UsageHistory>

    /// Same contract as `modify`, without a lock of its own: call it only from inside a
    /// `modify` closure, so the state lock serializes every history writer (the app and the
    /// monitor extension; the shield extensions never write history).
    func modifyHistory<Result>(_ change: (inout UsageHistory) -> Result) -> Result?
}

extension StateStore {
    /// `modify` without a post-save side effect.
    public func modify<Result>(_ change: (inout NotimeState) -> Result) -> Result? {
        modify(change, afterSave: { _, _ in })
    }
}
