import SwiftUI

struct RenameDialog: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var name: String
    let onSave: (String) -> Void

    @SwiftUI.Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title3.monospaced().bold())
            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($nameFocused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: DialogMetrics.formWidth)
        .frame(minHeight: DialogMetrics.formMinHeight)
        .onAppear { nameFocused = true }
        .environment(\.locale, Locale(identifier: appLanguage))
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
        dismiss()
    }
}
