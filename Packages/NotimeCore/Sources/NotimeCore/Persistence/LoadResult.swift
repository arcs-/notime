/// The outcome of reading a stored file. `empty` and `unavailable` are deliberately distinct:
/// a missing file means "start fresh", an unreadable or corrupt one means "touch nothing".
public enum LoadResult<Value> {
    case loaded(Value)
    /// The file does not exist yet.
    case empty
    /// The file (or its container) could not be read or decoded, e.g. data protection
    /// before the first unlock, a missing app group, or corruption.
    case unavailable(any Error)
}
