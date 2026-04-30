import SwiftUI

struct SaveTemplateSheet: View {
    @ObservedObject var vm: ProjectViewModel
    @ObservedObject var store: ProjectTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.Template.saveTitle(vm.lang))
                .font(.headline)

            TextField(L10n.Template.name(vm.lang), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit { save() }

            if let error = errorText {
                Text(error).font(.caption).foregroundColor(.red)
            }

            Text(L10n.Template.saveNote(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(L10n.Common.cancel(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.Common.save(vm.lang)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorText = L10n.Template.enterName(vm.lang)
            return
        }
        if store.nameExists(trimmed) {
            errorText = L10n.Template.duplicateName(vm.lang)
            return
        }
        vm.saveCurrentAsTemplate(name: trimmed)
        dismiss()
    }
}

struct ManageTemplatesSheet: View {
    @ObservedObject var vm: ProjectViewModel
    @ObservedObject var store: ProjectTemplateStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var editName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.Template.manageTitle(vm.lang))
                    .font(.headline)
                Spacer()
                Button(L10n.Common.close(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if store.templates.isEmpty {
                VStack {
                    Text(L10n.Template.noneStored(vm.lang))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.templates) { template in
                        TemplateRow(
                            template: template,
                            isEditing: editingID == template.id,
                            editName: editingID == template.id ? $editName : .constant(""),
                            onApply: {
                                vm.applyTemplate(template)
                                dismiss()
                            },
                            onNewProject: {
                                vm.newProject(fromTemplate: template)
                                dismiss()
                            },
                            onStartRename: {
                                editingID = template.id
                                editName = template.name
                            },
                            onConfirmRename: {
                                let trimmed = editName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    store.renameTemplate(id: template.id, newName: trimmed)
                                }
                                editingID = nil
                            },
                            onCancelRename: { editingID = nil },
                            onDuplicate: {
                                _ = store.duplicateTemplate(
                                    id: template.id,
                                    copySuffix: L10n.Preset.copySuffix(vm.lang)
                                )
                            },
                            onDelete: { store.deleteTemplate(id: template.id) }
                        )
                    }
                }
            }
        }
        .frame(width: 480, height: 400)
    }
}

private struct TemplateRow: View {
    @EnvironmentObject var vm: ProjectViewModel
    let template: ProjectTemplate
    let isEditing: Bool
    @Binding var editName: String
    let onApply: () -> Void
    let onNewProject: () -> Void
    let onStartRename: () -> Void
    let onConfirmRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if isEditing {
                TextField(L10n.Template.name(vm.lang), text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onConfirmRename() }
                Button(L10n.Common.ok(vm.lang)) { onConfirmRename() }.controlSize(.small)
                Button(L10n.Common.cancel(vm.lang)) { onCancelRename() }.controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.body)
                    Text(summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(L10n.Template.apply(vm.lang)) { onApply() }
                    .controlSize(.small)

                Menu {
                    Button(L10n.Template.newFromThis(vm.lang)) { onNewProject() }
                    Divider()
                    Button(L10n.Template.rename(vm.lang)) { onStartRename() }
                    Button(L10n.Template.duplicate(vm.lang)) { onDuplicate() }
                    Divider()
                    Button(L10n.Common.delete(vm.lang), role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let lang = L10n.PrimaryLang.displayName(template.primaryLanguage, vm.lang)
        let mode = L10n.CropModeName.displayName(template.cropMode, vm.lang)
        return "\(lang) · \(mode) · \(template.subtitleStyle.japaneseFontFamily) \(Int(template.subtitleStyle.japaneseFontSize))pt"
    }
}
