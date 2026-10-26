import FamilyControls
import SwiftUI

/// Second intro step, shown after Screen Time access while nothing is blocked yet.
/// RootView moves to Home once something is chosen.
struct ChooseTargetsView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false
    @State private var pickerSelection = FamilyActivitySelection()

    var body: some View {
        IntroScreen(
            heading: "Choose what to block",
            description: "Pick the apps and sites you lose time to, for example YouTube, Instagram or Facebook.",
            buttonTitle: "Choose apps and websites",
            buttonHint: "Opens the Screen Time picker.",
            notice: model.selectionNotice
        ) {
            isPickerPresented = true
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $pickerSelection)
        .onChange(of: isPickerPresented) { _, isPresented in
            if !isPresented {
                model.updateSelection(pickerSelection)
            }
        }
    }
}
