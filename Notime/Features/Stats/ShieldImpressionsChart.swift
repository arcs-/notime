import Charts
import NotimeCore
import SwiftUI

/// Blocks shown per day as plain bars: no gridlines, a baseline, at most three y ticks.
struct ShieldImpressionsChart: View {
    let points: [(day: DayKey, shieldImpressions: Int)]
    let calendar: Calendar

    var body: some View {
        let maximum = max(points.map(\.shieldImpressions).max() ?? 0, 1)
        let showsWeekdays = points.count <= 7
        Chart {
            ForEach(points, id: \.day) { point in
                if let date = point.day.noon(in: calendar) {
                    BarMark(x: .value("Day", date, unit: .day), y: .value("Blocks shown", point.shieldImpressions))
                        .foregroundStyle(Color.primary)
                        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .accessibilityValue("\(point.shieldImpressions) \(point.shieldImpressions == 1 ? "block" : "blocks")")
                }
            }
            RuleMark(y: .value("Baseline", 0))
                .foregroundStyle(Color.primary)
        }
        .chartYScale(domain: 0...maximum)
        .chartYAxis {
            AxisMarks(values: Array(Set([0, maximum / 2, maximum])).sorted()) { _ in
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: showsWeekdays ? 1 : 7)) { _ in
                AxisValueLabel(format: showsWeekdays ? .dateTime.weekday(.narrow) : .dateTime.day(), centered: true)
            }
        }
        .frame(height: 160)
    }
}
