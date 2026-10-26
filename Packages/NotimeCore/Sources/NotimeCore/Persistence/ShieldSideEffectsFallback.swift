import Foundation

/// Where the shield configuration extension keeps an impression when it cannot save the state
/// file. (On some devices these writes are dropped too; the action extension then counts the
/// impression on the tap.) The app group's shared `UserDefaults` is written by the system
/// on our behalf, so it works where direct file writes are denied. Processes that can write
/// the state file fold these entries in and clear them.
///
/// Keys: `impressions.<y-m-d>.<targetKey>` (a count) and `lastImpression.<targetKey>` (a date). `targetKey` is the base64 of the encoded target, or
/// `none` for category and token-less shields.
public struct ShieldSideEffectsFallback: @unchecked Sendable {
    static let impressionPrefix = "impressions."
    static let lastImpressionPrefix = "lastImpression."
    static let noTargetKey = "none"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public static func shared() -> ShieldSideEffectsFallback {
        ShieldSideEffectsFallback(defaults: UserDefaults(suiteName: AppGroupStateStore.appGroupIdentifier))
    }

    public func recordShieldImpression(for target: BlockedTarget?, at date: Date, calendar: Calendar) {
        let day = DayKey(date, calendar: calendar)
        guard let defaults else { return }
        let targetKey = target.flatMap(Self.key) ?? Self.noTargetKey
        let impressionKey = "\(Self.impressionPrefix)\(day.year)-\(day.month)-\(day.day).\(targetKey)"
        defaults.set(defaults.integer(forKey: impressionKey) + 1, forKey: impressionKey)
        if target != nil {
            defaults.set(date, forKey: Self.lastImpressionPrefix + targetKey)
        }
    }

    /// Adds every stored entry to `state` and returns the keys to `clear` once the state is
    /// saved. Unreadable entries are returned too, so they get cleared.
    public func fold(into state: inout NotimeState) -> [String] {
        guard let defaults else { return [] }
        var foldedKeys: [String] = []
        for (key, value) in defaults.dictionaryRepresentation() {
            if key.hasPrefix(Self.impressionPrefix) {
                foldImpressions(key: key, value: value, into: &state)
            } else if key.hasPrefix(Self.lastImpressionPrefix) {
                foldLastImpression(key: key, value: value, into: &state)
            } else {
                continue
            }
            foldedKeys.append(key)
        }
        return foldedKeys
    }

    public func clear(_ keys: [String]) {
        keys.forEach { defaults?.removeObject(forKey: $0) }
    }

    private func foldImpressions(key: String, value: Any, into state: inout NotimeState) {
        let parts = key.dropFirst(Self.impressionPrefix.count).split(separator: ".", maxSplits: 1)
        let dayParts = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
        guard parts.count == 2, dayParts.count == 3, let count = value as? Int else { return }
        let day = DayKey(year: dayParts[0], month: dayParts[1], day: dayParts[2])
        let target = Self.target(forKey: String(parts[1]))
        guard target != nil || parts[1] == Self.noTargetKey else { return }
        for _ in 0..<max(count, 0) {
            state.recordShieldImpression(for: target, on: day)
        }
    }

    private func foldLastImpression(key: String, value: Any, into state: inout NotimeState) {
        guard
            let target = Self.target(forKey: String(key.dropFirst(Self.lastImpressionPrefix.count))),
            let date = value as? Date
        else { return }
        state.lastImpressionAt[target] = max(state.lastImpressionAt[target] ?? date, date)
    }

    static func key(for target: BlockedTarget) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(target))?.base64EncodedString()
    }

    static func target(forKey key: String) -> BlockedTarget? {
        guard let data = Data(base64Encoded: key) else { return nil }
        return try? JSONDecoder().decode(BlockedTarget.self, from: data)
    }
}
