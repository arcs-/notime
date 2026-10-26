import NotimeCore
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var period: StatisticsPeriod = .today
    @State private var ledgers: [DailyUsageLedger] = []

    var body: some View {
        let report = UsageReport(
            ledgers: ledgers,
            period: period,
            today: model.today,
            calendar: model.calendar
        )
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(StatisticsPeriod.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ShieldImpressionsChart(
                    points: UsageReport.dailyShieldImpressions(
                        ledgers: ledgers,
                        dayCount: period.chartDayCount,
                        today: model.today,
                        calendar: model.calendar
                    ),
                    calendar: model.calendar
                )
                .padding(.vertical, 8)
            } header: {
                Text("Blocks shown per day")
            } footer: {
                if period == .today {
                    Text("Counts are kept per day, so the chart shows the last 7 days.")
                }
            }
            Section("Total") {
                FactRow("Blocks shown", value: "\(report.totals.shieldImpressions)")
                FactRow("Times opened", value: "\(report.totals.accessesGranted)")
            }
            Section("By app or website") {
                if report.targetsByImpressions.isEmpty {
                    Text("Nothing yet.")
                }
                ForEach(report.targetsByImpressions, id: \.self) { target in
                    let statistics = report.statisticsByTarget[target] ?? BlockStatistics()
                    let summary = "\(statistics.shieldImpressions) blocks, opened \(statistics.accessesGranted)×"
                    VStack(alignment: .leading, spacing: 4) {
                        BlockedTargetLabel(target: target)
                        Text(summary)
                            .font(.footnote)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue("\(statistics.shieldImpressions) blocks, opened \(statistics.accessesGranted) times")
                }
            }
        }
        .listSectionSpacing(20)
        .navigationTitle("Stats")
        .onAppear { ledgers = model.statisticsLedgers() }
    }
}
