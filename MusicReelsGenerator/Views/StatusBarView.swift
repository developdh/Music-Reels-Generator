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
                Text(L10n.Status.preparingExport(vm.lang))
            case .exporting(let progress):
                ProgressView(value: progress)
                    .frame(width: 100)
                Text(L10n.Status.exporting(vm.lang))
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(L10n.Status.exportComplete(vm.lang))
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
                    .help(L10n.Status.unsavedChanges(vm.lang))
            }
        }
        .padding(.horizontal, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
