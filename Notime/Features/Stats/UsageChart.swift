import Charts
import NotimeCore
import SwiftUI

/// Blocks shown and times opened as side-by-side bars: no gridlines, a baseline, at most three
/// y ticks, a legend below.
struct UsageChart: View {
    struct Bar: Identifiable {
        /// The bar's place on the x axis, unique within the chart.
        let id: String
        /// Shown under the bar; nil leaves it unlabelled.
        let axisLabel: String?
        let accessibilityLabel: String
        let statistics: BlockStatistics
    }

    private enum Series: CaseIterable {
        case blocksShown, opened

        var title: String {
            switch self {
            case .blocksShown: "Blocks shown"
            case .opened: "Opened"
            }
        }

        var color: Color {
            switch self {
            case .blocksShown: .primary
            case .opened: Color(.systemGray3)
            }
        }

        func count(in statistics: BlockStatistics) -> Int {
            switch self {
            case .blocksShown: statistics.shieldImpressions
            case .opened: statistics.accessesGranted
            }
        }
    }

    let bars: [Bar]

    var body: some View {
        let maximum = max(bars.flatMap { bar in Series.allCases.map { $0.count(in: bar.statistics) } }.max() ?? 0, 1)
        let axisLabels = Dictionary(uniqueKeysWithValues: bars.compactMap { bar in bar.axisLabel.map { (bar.id, $0) } })
        Chart {
            ForEach(bars) { bar in
                ForEach(Series.allCases, id: \.self) { series in
                    BarMark(x: .value("Time", bar.id), y: .value("Count", series.count(in: bar.statistics)))
                        .position(by: .value("Series", series.title))
                        .foregroundStyle(by: .value("Series", series.title))
                        .accessibilityLabel("\(bar.accessibilityLabel), \(series.title)")
                        .accessibilityValue(Self.accessibilityValue(of: bar.statistics))
                }
            }
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(Color.primary)
        }
        .chartForegroundStyleScale(domain: Series.allCases.map(\.title), range: Series.allCases.map(\.color))
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYScale(domain: 0...maximum)
        .chartYAxis {
            AxisMarks(values: Array(Set([0, maximum / 2, maximum])).sorted()) { _ in
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: bars.filter { $0.axisLabel != nil }.map(\.id)) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let label = axisLabels[id] {
                        Text(label)
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private static func accessibilityValue(of statistics: BlockStatistics) -> String {
        let blocks = statistics.shieldImpressions
        let openings = statistics.accessesGranted
        return "\(blocks) \(blocks == 1 ? "block" : "blocks") shown, opened \(openings) \(openings == 1 ? "time" : "times")"
    }
}

extension UsageChart {
    /// One bar per hour of `day`, labelled every 6 hours.
    static func hourly(_ hours: [(hour: Int, statistics: BlockStatistics)], of day: DayKey, calendar: Calendar) -> UsageChart {
        let noon = day.noon(in: calendar)
        return UsageChart(bars: hours.compactMap { hour, statistics in
            guard let start = noon.flatMap({ calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) }) else { return nil }
            return Bar(
                id: "\(hour)",
                axisLabel: hour % 6 == 0 ? start.formatted(.dateTime.hour()) : nil,
                accessibilityLabel: (start..<start.addingTimeInterval(3600)).formatted(.interval.hour()),
                statistics: statistics
            )
        })
    }

    /// One bar per day: up to a week labelled by weekday, longer spans weekly, ending today.
    static func daily(_ days: [(day: DayKey, statistics: BlockStatistics)], calendar: Calendar) -> UsageChart {
        let showsWeekdays = days.count <= 7
        return UsageChart(bars: days.enumerated().compactMap { index, point in
            guard let date = point.day.noon(in: calendar) else { return nil }
            let isLabelled = showsWeekdays || (days.count - 1 - index) % 7 == 0
            return Bar(
                id: "\(point.day.year)-\(point.day.month)-\(point.day.day)",
                axisLabel: isLabelled ? date.formatted(showsWeekdays ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated)) : nil,
                accessibilityLabel: date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                statistics: point.statistics
            )
        })
    }
}
