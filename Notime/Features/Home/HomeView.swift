import FamilyControls
import NotimeCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var editedSetting: PolicySetting?

    var body: some View {
        NavigationStack {
            List {
                if model.authorizationStatus != .approved {
                    authorizationNotice
                }
                if model.wasStateReset {
                    Section {
                        Text("Settings could not be read and were reset. Choose apps again.")
                    }
                }
                if !model.isStateAvailable {
                    Section {
                        Text("notime can't read its data right now. Existing blocks are left as they are.")
                    }
                }
                blockedSection
                settingsSection
                todaySection
                // The app's only outbound link; it opens Safari only when tapped.
                if let authorURL = URL(string: "https://stillh.art") {
                    Section {
                        Link("Made by Patrick", destination: authorURL)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("Made by Patrick, opens stillh.art")
                    }
                }
            }
            .listSectionSpacing(20)
            .navigationTitle("notime")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AppMark() }
            }
            .sheet(item: $editedSetting) { setting in
                NumberSettingSheet(setting: setting, value: value(of: setting)) { newValue in
                    model.updatePolicy { $0[keyPath: setting.keyPath] = newValue }
                }
            }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $pickerSelection)
            .onChange(of: isPickerPresented) { _, isPresented in
                if !isPresented {
                    model.updateSelection(pickerSelection)
                }
            }
        }
    }

    private var authorizationNotice: some View {
        Section {
            Text("Screen Time access is off. notime cannot block anything until you allow it again. Your settings are kept.")
            Button("Allow Screen Time access") {
                Task { await model.requestAuthorization() }
            }
            .accessibilityHint("Shows the system request for Screen Time access.")
        }
    }

    private var blockedSection: some View {
        let selection = model.state.selection
        return Section("Blocked") {
            if selection.isEmpty {
                Text("Nothing blocked yet.")
            }
            ForEach(Array(selection.applicationTokens), id: \.self) { BlockedTargetLabel(target: .application($0)) }
            ForEach(Array(selection.categoryTokens), id: \.self) { Label($0) }
            ForEach(Array(selection.webDomainTokens), id: \.self) { BlockedTargetLabel(target: .webDomain($0)) }
            if !selection.categoryTokens.isEmpty {
                Text("Whole categories can only be closed, not opened. Pick individual apps or sites to open them.")
            }
            if let notice = model.selectionNotice {
                Text(notice)
            }
            Button {
                pickerSelection = FamilyActivitySelection(selection)
                isPickerPresented = true
            } label: {
                Text("Choose apps and websites")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .prominentButton()
            .accessibilityHint("Opens the Screen Time picker.")
        }
    }

    private var settingsSection: some View {
        Section {
            ForEach(PolicySetting.allCases) { setting in
                Button {
                    editedSetting = setting
                } label: {
                    FactRow(setting.title, value: "\(value(of: setting)) \(setting.unit)")
                }
                .accessibilityHint("Opens a field to change it.")
            }
        } header: {
            Text("Settings")
        } footer: {
            Text("The first tap on Open starts the wait; a tap after it opens the app or website for the access length. Each further opening of it today adds the added seconds to the wait, up to \(Self.maximumWaitText). Counts reset at midnight.")
        }
    }

    private var todaySection: some View {
        let totals = model.state.ledger(for: model.today).totals
        return Section("Today") {
            FactRow("Blocks shown", value: "\(totals.shieldImpressions)")
            FactRow("Times opened", value: "\(totals.accessesGranted)")
            NavigationLink("Stats") { StatsView() }
        }
    }

    /// "3 minutes", from `WaitCalculator.maximumWaitSeconds`.
    private static let maximumWaitText = Duration.seconds(WaitCalculator.maximumWaitSeconds)
        .formatted(.units(allowed: [.minutes, .seconds], width: .wide))

    private func value(of setting: PolicySetting) -> Int {
        model.state.policy[keyPath: setting.keyPath]
    }
}
