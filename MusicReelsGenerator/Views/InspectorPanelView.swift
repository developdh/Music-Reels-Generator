import SwiftUI

struct InspectorPanelView: View {
    @EnvironmentObject var vm: ProjectViewModel
    @State private var selectedTab: InspectorTab = .block

    enum InspectorTab: String, CaseIterable {
        case block = "Block"
        case trim = "Trim"
        case crop = "Crop"
        case style = "Style"
        case overlay = "Overlay"
        case watermark = "Watermark"
        case ignore = "Ignore"
        case info = "Info"
    }

    private func tabName(_ tab: InspectorTab) -> String {
        switch tab {
        case .block: return L10n.Tab.block(vm.lang)
        case .trim: return L10n.Tab.trim(vm.lang)
        case .crop: return L10n.Tab.crop(vm.lang)
        case .style: return L10n.Tab.style(vm.lang)
        case .overlay: return L10n.Tab.overlay(vm.lang)
        case .watermark: return L10n.Tab.watermark(vm.lang)
        case .ignore: return L10n.Tab.ignore(vm.lang)
        case .info: return L10n.Tab.info(vm.lang)
        }
    }

    private func tabIcon(_ tab: InspectorTab) -> String {
        switch tab {
        case .block: return "text.alignleft"
        case .trim: return "scissors"
        case .crop: return "crop"
        case .style: return "paintbrush"
        case .overlay: return "text.below.photo"
        case .watermark: return "photo.badge.checkmark"
        case .ignore: return "eye.slash"
        case .info: return "info.circle"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Icon-only segmented control — stays readable at any inspector width.
            // The current tab's full label is shown below for clarity.
            Picker("", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Image(systemName: tabIcon(tab))
                        .help(tabName(tab))
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.top, 8)

            HStack(spacing: 6) {
                Image(systemName: tabIcon(selectedTab))
                    .foregroundColor(.secondary)
                Text(tabName(selectedTab))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case .block:
                        BlockInspectorView()
                    case .trim:
                        TrimInspectorView()
                    case .crop:
                        CropInspectorView()
                    case .style:
                        StyleInspectorView()
                    case .overlay:
                        MetadataOverlayInspectorView()
                    case .watermark:
                        WatermarkInspectorView()
                    case .ignore:
                        IgnoreRegionsInspectorView()
                    case .info:
                        InfoInspectorView()
                    }
                }
                .padding(12)
            }
        }
    }
}
