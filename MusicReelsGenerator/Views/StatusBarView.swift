import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Export state
            switch vm.exportState {
            case .idle:
                EmptyView()
            case .preparing:
                ProgressView()
                    .controlSize(.mini)
                Text("Preparing export...")
            case .exporting(let progress):
                ProgressView(value: progress)
                    .frame(width: 100)
                Text("Exporting...")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Export complete")
            case .failed(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(msg)
                    .lineLimit(1)
            }

            Spacer()

            // Status message
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Dirty indicator
            if vm.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .help("Unsaved changes")
            }
        }
        .padding(.horizontal, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
