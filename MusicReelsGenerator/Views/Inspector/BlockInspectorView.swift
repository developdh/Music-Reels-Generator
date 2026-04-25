import SwiftUI

struct BlockInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        if let block = vm.selectedBlock, let idx = vm.selectedBlockIndex {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Block.title(vm.lang, index: idx + 1))
                    .font(.headline)

                GroupBox(L10n.Block.primaryLine(vm.lang)) {
                    TextField("", text: Binding(
                        get: { block.japanese },
                        set: { vm.updateBlockText(id: block.id, primary: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(L10n.Block.secondaryLine(vm.lang)) {
                    TextField("", text: Binding(
                        get: { block.korean },
                        set: { vm.updateBlockText(id: block.id, secondary: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(L10n.Block.timing(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Block.start(vm.lang))
                                .frame(width: 40, alignment: .trailing)
                            if let start = block.startTime {
                                Text(TimeFormatter.format(start))
                                    .monospacedDigit()
                            } else {
                                Text(L10n.Block.notSet(vm.lang))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L10n.Block.setNow(vm.lang)) {
                                vm.setStartTimeToCurrent()
                            }
                            .controlSize(.small)
                        }

                        HStack {
                            Text(L10n.Block.end(vm.lang))
                                .frame(width: 40, alignment: .trailing)
                            if let end = block.endTime {
                                Text(TimeFormatter.format(end))
                                    .monospacedDigit()
                            } else {
                                Text(L10n.Block.notSet(vm.lang))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L10n.Block.setNow(vm.lang)) {
                                vm.setEndTimeToCurrent()
                            }
                            .controlSize(.small)
                        }

                        if let confidence = block.confidence {
                            HStack {
                                Text(L10n.Block.confidence(vm.lang))
                                ConfidenceBadge(confidence: confidence, isManual: block.isManuallyAdjusted)
                            }
                        }
                    }
                }

                HStack {
                    Button(L10n.Block.seekToStart(vm.lang)) {
                        if let start = block.startTime {
                            vm.seek(to: start)
                        }
                    }
                    .disabled(block.startTime == nil)

                    Button(L10n.Block.seekToEnd(vm.lang)) {
                        if let end = block.endTime {
                            vm.seek(to: end)
                        }
                    }
                    .disabled(block.endTime == nil)
                }

                Divider()

                GroupBox(L10n.Block.correction(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(L10n.Block.setStartShiftFollowing(vm.lang)) {
                            vm.setStartTimeAndShiftFollowing()
                        }
                        .controlSize(.small)
                        .help(L10n.Block.setStartShiftHelp(vm.lang))

                        HStack(spacing: 4) {
                            Button("-0.5s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: -0.5) }
                            Button("-0.1s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: -0.1) }
                            Button("+0.1s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: 0.1) }
                            Button("+0.5s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: 0.5) }
                        }
                        .controlSize(.mini)
                    }
                }

                GroupBox(L10n.Anchor.anchorCorrection(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Anchor controls
                        HStack {
                            if block.isUserAnchor {
                                Label(L10n.Anchor.userAnchor(vm.lang), systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                                Button(L10n.Anchor.releaseAnchor(vm.lang)) {
                                    vm.unsetAnchor(id: block.id)
                                }
                                .controlSize(.small)
                            } else if block.isAnchor {
                                Label(L10n.Anchor.autoAnchor(vm.lang), systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(L10n.Anchor.promoteToUser(vm.lang)) {
                                    vm.setAnchor(id: block.id)
                                }
                                .controlSize(.small)
                                .help(L10n.Anchor.promoteHelp(vm.lang))
                            } else {
                                Button(L10n.Anchor.setAsAnchor(vm.lang)) {
                                    vm.setAnchor(id: block.id)
                                }
                                .controlSize(.small)
                                .help(L10n.Anchor.setAsAnchorHelp(vm.lang))
                            }
                        }

                        if block.isManuallyAdjusted && !block.isUserAnchor {
                            HStack(spacing: 4) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption2)
                                Text(L10n.Anchor.manuallyAdjustedHint(vm.lang))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        // Piecewise correction between anchors
                        Button(L10n.Anchor.correctBetween(vm.lang)) {
                            vm.correctBetweenSurroundingAnchors()
                        }
                        .controlSize(.small)
                        .disabled(!vm.hasSurroundingAnchors)
                        .help(L10n.Anchor.correctBetweenHelp(vm.lang))

                        Button(L10n.Anchor.correctAll(vm.lang)) {
                            vm.correctBetweenAllAnchors()
                        }
                        .controlSize(.small)
                        .disabled(vm.anchorCount < 2)
                        .help(L10n.Anchor.correctAllHelp(vm.lang))

                        Divider()

                        // Local re-alignment with legacy engine
                        Button(L10n.Anchor.localRealign(vm.lang)) {
                            Task { await vm.localRealignSurroundingRegion() }
                        }
                        .controlSize(.small)
                        .disabled(!vm.project.hasVideo || !vm.whisperAvailable || vm.isAligning)
                        .help(L10n.Anchor.localRealignHelp(vm.lang))
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text(L10n.Block.selectBlock(vm.lang))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
