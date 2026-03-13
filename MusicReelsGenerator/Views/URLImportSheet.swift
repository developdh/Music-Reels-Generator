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
            Text("URL Import")
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
            Text("Enter a video URL to download and import.")
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
                    Text("Validating...")
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
                    Text("Download complete, importing...")
                        .font(.caption)
                }
            }

            HStack {
                Button("Cancel") {
                    vm.youtubeDownloadState = .idle
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Download & Import") {
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

            Text("이 기능은 현재 비활성화 상태입니다.")
                .font(.body)

            Text("This feature is not available in the public build.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("OK") { dismiss() }
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
