import SwiftUI

/// Edits one setting in a number field. The value is clamped to `range` and saved on Done.
struct NumberSettingSheet: View {
    let setting: PolicySetting
    let save: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFieldFocused: Bool

    init(setting: PolicySetting, value: Int, save: @escaping (Int) -> Void) {
        self.setting = setting
        self.save = save
        _text = State(initialValue: String(value))
    }

    var body: some View {
        let range = setting.range
        NavigationStack {
            Form {
                Section {
                    TextField(setting.unitName.capitalized, text: $text)
                        .keyboardType(.numberPad)
                        .focused($isFieldFocused)
                        .accessibilityLabel("\(setting.title) in \(setting.unitName)")
                } footer: {
                    Text("\(range.lowerBound) to \(range.upperBound) \(setting.unitName).")
                }
            }
            .navigationTitle(setting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityHint("Closes without saving.")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let value = Int(text.trimmingCharacters(in: .whitespaces)) {
                            save(min(max(value, range.lowerBound), range.upperBound))
                        }
                        dismiss()
                    }
                    .accessibilityHint("Saves the value and closes.")
                }
            }
            .onAppear { isFieldFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
