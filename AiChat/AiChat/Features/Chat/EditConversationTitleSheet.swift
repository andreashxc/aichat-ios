import SwiftUI

struct EditConversationTitleSheet: View {
    @Binding var isPresented: Bool
    @State var title: String
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Conversation Title", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 17, weight: .regular))
                } header: {
                    Text("Edit Title")
                        .textCase(.uppercase)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Give this conversation a meaningful name")
                        .font(.system(size: 13))
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.system(size: 17, weight: .regular))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        isPresented = false
                    } label: {
                        Text("Save")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.blue.gradient))
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}
