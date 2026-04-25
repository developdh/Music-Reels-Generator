import SwiftUI

struct StyleInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel
    @ObservedObject private var presetStore = StylePresetStore.shared
    @State private var showSaveSheet = false
    @State private var showManageSheet = false

    private var allFonts: [String] { FontUtility.allFamilies }
    private var jaDefaults: [String] { FontUtility.japaneseFamilies }
    private var koDefaults: [String] { FontUtility.koreanFamilies }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Style.subtitleStyle(vm.lang))
                .font(.headline)

            // Style Presets
            GroupBox(L10n.Style.presets(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    if !presetStore.presets.isEmpty {
                        HStack {
                            Menu {
                                ForEach(presetStore.presets) { preset in
                                    Button(preset.name) {
                                        vm.applyPreset(preset)
                                    }
                                }
                            } label: {
                                Label(L10n.Style.applyPreset(vm.lang), systemImage: "paintbrush")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(L10n.Style.noPresets(vm.lang))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(L10n.Style.saveCurrentStyle(vm.lang)) {
                            showSaveSheet = true
                        }
                        .controlSize(.small)

                        if !presetStore.presets.isEmpty {
                            Button(L10n.Style.manage(vm.lang)) {
                                showManageSheet = true
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                SavePresetSheet(vm: vm, presetStore: presetStore)
            }
            .sheet(isPresented: $showManageSheet) {
                ManagePresetsSheet(vm: vm, presetStore: presetStore)
            }

            GroupBox(L10n.Style.primaryFont(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    FontFamilyPicker(
                        selection: $vm.project.subtitleStyle.japaneseFontFamily,
                        recommended: jaDefaults,
                        allFonts: allFonts
                    )

                    HStack {
                        Text(L10n.Style.size(vm.lang))
                            .frame(width: 36, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.japaneseFontSize, in: 24...120, step: 1)
                        Text("\(Int(vm.project.subtitleStyle.japaneseFontSize))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    SubtitleColorPicker(
                        label: "Color:",
                        hexColor: $vm.project.subtitleStyle.japaneseTextColorHex
                    )
                }
            }

            GroupBox(L10n.Style.secondaryFont(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    FontFamilyPicker(
                        selection: $vm.project.subtitleStyle.koreanFontFamily,
                        recommended: koDefaults,
                        allFonts: allFonts
                    )

                    HStack {
                        Text(L10n.Style.size(vm.lang))
                            .frame(width: 36, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.koreanFontSize, in: 20...100, step: 1)
                        Text("\(Int(vm.project.subtitleStyle.koreanFontSize))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    SubtitleColorPicker(
                        label: "Color:",
                        hexColor: $vm.project.subtitleStyle.koreanTextColorHex
                    )
                }
            }

            GroupBox(L10n.Style.appearance(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.Style.outline(vm.lang))
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.outlineWidth, in: 0...8, step: 0.5)
                        Text("\(String(format: "%.1f", vm.project.subtitleStyle.outlineWidth))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }

                    Toggle(L10n.Style.shadow(vm.lang), isOn: $vm.project.subtitleStyle.shadowEnabled)
                }
            }

            GroupBox(L10n.Style.position(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.Style.bottom(vm.lang))
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.bottomMargin, in: 50...960, step: 5)
                        Text("\(Int(vm.project.subtitleStyle.bottomMargin))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    HStack {
                        Text(L10n.Style.gap(vm.lang))
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.lineSpacing, in: 0...40, step: 1)
                        Text("\(Int(vm.project.subtitleStyle.lineSpacing))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }
                }
            }
        }
        .onChange(of: vm.project.subtitleStyle) { _, _ in
            vm.isDirty = true
        }
    }
}

/// A font picker that shows recommended fonts first, then all system fonts
struct FontFamilyPicker: View {
    @EnvironmentObject var vm: ProjectViewModel
    @Binding var selection: String
    let recommended: [String]
    let allFonts: [String]

    var body: some View {
        Picker("Font", selection: $selection) {
            if !recommended.isEmpty {
                Section(L10n.Style.recommended(vm.lang)) {
                    ForEach(recommended, id: \.self) { font in
                        Text(font)
                            .font(.custom(font, size: 13))
                            .tag(font)
                    }
                }
                Divider()
            }

            Section(L10n.Style.allFonts(vm.lang)) {
                ForEach(allFonts, id: \.self) { font in
                    Text(font).tag(font)
                }
            }
        }
        .labelsHidden()
    }
}

struct SavePresetSheet: View {
    @ObservedObject var vm: ProjectViewModel
    @ObservedObject var presetStore: StylePresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var presetName: String = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.Preset.saveTitle(vm.lang))
                .font(.headline)

            TextField(L10n.Preset.presetName(vm.lang), text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { save() }

            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text(L10n.Preset.saveNote(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(L10n.Common.cancel(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(L10n.Common.save(vm.lang)) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }

    private func save() {
        let trimmed = presetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorText = L10n.Preset.enterName(vm.lang)
            return
        }
        if presetStore.nameExists(trimmed) {
            errorText = L10n.Preset.duplicateName(vm.lang)
            return
        }
        vm.saveCurrentStyleAsPreset(name: trimmed)
        dismiss()
    }
}

struct ManagePresetsSheet: View {
    @ObservedObject var vm: ProjectViewModel
    @ObservedObject var presetStore: StylePresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var editName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.Preset.manageTitle(vm.lang))
                    .font(.headline)
                Spacer()
                Button(L10n.Common.close(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if presetStore.presets.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.Preset.noPresetsStored(vm.lang))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(presetStore.presets) { preset in
                        PresetRow(
                            preset: preset,
                            isEditing: editingID == preset.id,
                            editName: editingID == preset.id ? $editName : .constant(""),
                            onApply: {
                                vm.applyPreset(preset)
                                dismiss()
                            },
                            onStartRename: {
                                editingID = preset.id
                                editName = preset.name
                            },
                            onConfirmRename: {
                                let trimmed = editName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    presetStore.renamePreset(id: preset.id, newName: trimmed)
                                }
                                editingID = nil
                            },
                            onCancelRename: {
                                editingID = nil
                            },
                            onDuplicate: {
                                _ = presetStore.duplicatePreset(id: preset.id)
                            },
                            onDelete: {
                                presetStore.deletePreset(id: preset.id)
                            }
                        )
                    }
                }
            }
        }
        .frame(width: 420, height: 360)
    }
}

struct PresetRow: View {
    @EnvironmentObject var vm: ProjectViewModel
    let preset: StylePreset
    let isEditing: Bool
    @Binding var editName: String
    let onApply: () -> Void
    let onStartRename: () -> Void
    let onConfirmRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if isEditing {
                TextField(L10n.Preset.name(vm.lang), text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onConfirmRename() }

                Button(L10n.Common.ok(vm.lang)) { onConfirmRename() }
                    .controlSize(.small)
                Button(L10n.Common.cancel(vm.lang)) { onCancelRename() }
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body)
                    Text("JP: \(preset.subtitleStyle.japaneseFontFamily) \(Int(preset.subtitleStyle.japaneseFontSize))pt")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(L10n.Preset.apply(vm.lang)) { onApply() }
                    .controlSize(.small)

                Menu {
                    Button(L10n.Preset.rename(vm.lang)) { onStartRename() }
                    Button(L10n.Preset.duplicate(vm.lang)) { onDuplicate() }
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
}
