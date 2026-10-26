import Foundation

/// The wall-clock interval of one grant's Device Activity. Pure, so the maths is tested on the host.
///
/// Device Activity rejects intervals shorter than 15 minutes, and the schedule has minute
/// precision: the start is truncated to the minute and the end is built from that truncated
/// start, so the interval is exactly `intervalMinutes`, always above 15.
/// The components carry a fixed-offset time zone (the device's offset at `now`), so an interval
/// across a daylight-saving change is neither ambiguous nor negative.
public struct AccessWindowSchedule: Hashable, Sendable {
    public static let minimumIntervalMinutes = 15
    public static let slackMinutes = 1
    static let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]

    public let intervalMinutes: Int
    public let start: DateComponents
    public let end: DateComponents

    public init(accessWindowMinutes: Int, now: Date, calendar: Calendar) {
        intervalMinutes = max(accessWindowMinutes, Self.minimumIntervalMinutes) + Self.slackMinutes
        var fixedCalendar = calendar
        let offset = calendar.timeZone.secondsFromGMT(for: now)
        fixedCalendar.timeZone = TimeZone(secondsFromGMT: offset) ?? calendar.timeZone
        var start = fixedCalendar.dateComponents(Self.components, from: now)
        start.timeZone = fixedCalendar.timeZone
        let truncatedStart = fixedCalendar.date(from: start) ?? now
        var end = fixedCalendar.dateComponents(
            Self.components,
            from: truncatedStart.addingTimeInterval(TimeInterval(intervalMinutes * 60))
        )
        end.timeZone = fixedCalendar.timeZone
        self.start = start
        self.end = end
    }
}
