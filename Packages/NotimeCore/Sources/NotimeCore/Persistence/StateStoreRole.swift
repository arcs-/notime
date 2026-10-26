/// Which process a store serves. Only the app may create or reset the state file;
/// extensions only ever work on an existing, valid file and otherwise fail closed.
public enum StateStoreRole: Sendable {
    /// Starts fresh when the file is missing; moves a corrupt file aside and starts fresh.
    case app
    /// Treats a missing state file as unavailable (never starts fresh, never applies an
    /// empty shield set) and leaves a corrupt file in place for the app to recover.
    case appExtension
}
