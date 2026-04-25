import SwiftUI

struct IgnoreRegionsInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Ignore.title(vm.lang))
                .font(.headline)

            Text(L10n.Ignore.help(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)

            // Add button
            Button {
                vm.addIgnoreRegionAtCurrentTime()
            } label: {
                Label(L10n.Ignore.addAtCurrent(vm.lang), systemImage: "plus.circle")
            }
            .controlSize(.small)
            .disabled(!vm.project.hasVideo)

            if vm.project.ignoreRegions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(L10n.Ignore.noRegions(vm.lang))
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(vm.project.ignoreRegions) { region in
                    IgnoreRegionRowView(region: region)
                }
            }
        }
    }
}

struct IgnoreRegionRowView: View {
    @EnvironmentObject var vm: ProjectViewModel
    let region: IgnoreRegion
    @State private var editingLabel: String = ""
    @State private var isEditingLabel: Bool = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Header with label and delete
                HStack {
                    if isEditingLabel {
                        TextField(L10n.Ignore.label(vm.lang), text: $editingLabel, onCommit: {
                            vm.updateIgnoreRegion(id: region.id, label: editingLabel)
                            isEditingLabel = false
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    } else {
                        Text(region.label.isEmpty ? L10n.Ignore.ignoreRegion(vm.lang) : region.label)
                            .font(.caption.bold())
                            .onTapGesture {
                                editingLabel = region.label
                                isEditingLabel = true
                            }
                    }
                    Spacer()
                    Button {
                        vm.removeIgnoreRegion(id: region.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                // Start time
                HStack {
                    Text(L10n.Ignore.startLabel(vm.lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(TimeFormatter.format(region.startTime))
                        .monospacedDigit()
                        .font(.caption)
                    Spacer()
                    Button(L10n.Ignore.current(vm.lang)) {
                        vm.updateIgnoreRegion(id: region.id, startTime: vm.currentTime)
                    }
                    .controlSize(.mini)
                    HStack(spacing: 2) {
                        Button("-1s") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime - 1) }
                        Button("-0.1") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime - 0.1) }
                        Button("+0.1") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime + 0.1) }
                        Button("+1s") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime + 1) }
                    }
                    .controlSize(.mini)
                }

                // End time
                HStack {
                    Text(L10n.Ignore.endLabel(vm.lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(TimeFormatter.format(region.endTime))
                        .monospacedDigit()
                        .font(.caption)
                    Spacer()
                    Button(L10n.Ignore.current(vm.lang)) {
                        vm.updateIgnoreRegion(id: region.id, endTime: vm.currentTime)
                    }
                    .controlSize(.mini)
                    HStack(spacing: 2) {
                        Button("-1s") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime - 1) }
                        Button("-0.1") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime - 0.1) }
                        Button("+0.1") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime + 0.1) }
                        Button("+1s") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime + 1) }
                    }
                    .controlSize(.mini)
                }

                // Duration display
                HStack {
                    Text(L10n.Ignore.length(vm.lang, time: TimeFormatter.formatMMSS(region.duration)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(L10n.Ignore.seekToRegion(vm.lang)) {
                        vm.seek(to: region.startTime)
                    }
                    .controlSize(.mini)
                }
            }
        }
    }
}
