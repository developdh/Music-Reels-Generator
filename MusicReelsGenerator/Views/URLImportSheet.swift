import SwiftUI

struct URLImportSheet: View {
    @EnvironmentObject var vm: ProjectViewModel
    @State private var urlText: String = ""
    @Environment(\.dismiss) var dismiss

    private var provider: YouTubeDownloadProvider {
        YouTubeDownloadRegistry.provider
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.URLImport.title(vm.lang))
                .font(.headline)

            if provider.isEnabled {
                enabledContent
            } else {
                disabledContent
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var enabledContent: some View {
        VStack(spacing: 12) {
            Text(L10n.URLImport.enterURL(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("https://...", text: $urlText)
                .textFieldStyle(.roundedBorder)

            // Progress
            switch vm.youtubeDownloadState {
            case .idle:
                EmptyView()
            case .validating:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n.URLImport.validating(vm.lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .downloading(let progress, let statusText):
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            case .completed:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(L10n.URLImport.downloadComplete(vm.lang))
                        .font(.caption)
                }
            }

            HStack {
                Button(L10n.Common.cancel(vm.lang)) {
                    vm.youtubeDownloadState = .idle
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.URLImport.downloadImport(vm.lang)) {
                    Task { await vm.downloadFromURL(urlText) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDownloading)
            }
        }
    }

    private var disabledContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text(L10n.URLImport.disabled(vm.lang))
                .font(.body)

            Text(L10n.URLImport.installScript(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)

            Text("~/Library/Application Support/MusicReelsGenerator/Scripts/yt_download.sh")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)

            Button(L10n.Common.ok(vm.lang)) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var isDownloading: Bool {
        switch vm.youtubeDownloadState {
        case .validating, .downloading: return true
        default: return false
        }
    }
}
