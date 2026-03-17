import SwiftUI

struct LyricsPanelView: View {
    @EnvironmentObject var vm: ProjectViewModel
    @State private var showLyricsInput = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.Lyrics.lyrics(vm.lang))
                    .font(.headline)
                Spacer()
                Text(L10n.Lyrics.blocks(vm.lang, count: vm.project.lyricBlocks.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    showLyricsInput = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)
                .help(L10n.Lyrics.pasteEdit(vm.lang))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if vm.project.lyricBlocks.isEmpty {
                emptyState
            } else {
                lyricBlockList
            }
        }
        .sheet(isPresented: $showLyricsInput) {
            LyricsInputSheet(text: $vm.lyricsInputText) {
                vm.parseLyrics()
                showLyricsInput = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(L10n.Lyrics.noLyrics(vm.lang))
                .font(.title3)
                .foregroundColor(.secondary)
            Button(L10n.Lyrics.pasteLyrics(vm.lang)) {
                showLyricsInput = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var lyricBlockList: some View {
        ScrollViewReader { proxy in
            List(selection: $vm.selectedBlockID) {
                ForEach(Array(vm.project.lyricBlocks.enumerated()), id: \.element.id) { index, block in
                    LyricBlockRow(block: block, index: index, isActive: block.id == vm.currentBlock?.id)
                        .tag(block.id)
                        .id(block.id)
                        .onTapGesture {
                            vm.seekToBlock(block)
                        }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: vm.currentBlock?.id) { _, newID in
                if let id = newID {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct LyricBlockRow: View {
    @EnvironmentObject var vm: ProjectViewModel
    let block: LyricBlock
    let index: Int
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("#\(index + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)

                if block.isUserAnchor {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.blue)
                } else if block.isAnchor {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Spacer()

                if let confidence = block.confidence {
                    ConfidenceBadge(confidence: confidence, isManual: block.isManuallyAdjusted)
                }
            }

            Text(block.japanese)
                .font(.system(size: 14, weight: isActive ? .bold : .regular))
                .lineLimit(1)

            if !block.korean.isEmpty {
                Text(block.korean)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if block.hasTimingData {
                Text(block.durationString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(L10n.Block.noTiming(vm.lang))
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(block.isLowConfidence && !block.isManuallyAdjusted ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}

struct ConfidenceBadge: View {
    @EnvironmentObject var vm: ProjectViewModel
    let confidence: Double
    let isManual: Bool

    var color: Color {
        if isManual { return .blue }
        if confidence >= 0.7 { return .green }
        if confidence >= 0.4 { return .orange }
        return .red
    }

    var label: String {
        if isManual { return L10n.Block.manual(vm.lang) }
        return "\(Int(confidence * 100))%"
    }

    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

struct LyricsInputSheet: View {
    @EnvironmentObject var vm: ProjectViewModel
    @Binding var text: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.Lyrics.pasteBilingual(vm.lang))
                .font(.headline)

            Text(L10n.Lyrics.formatHelp(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)

            NativeTextEditor(text: $text)
                .frame(minWidth: 400, minHeight: 300)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button(L10n.Common.cancel(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.Lyrics.parseImport(vm.lang)) { onConfirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
