import SwiftUI

struct SubtitleColorPicker: View {
    @EnvironmentObject var vm: ProjectViewModel
    let label: String
    @Binding var hexColor: String

    private static let presetHexes: [String] = [
        "#FFFFFF", "#E0FFFF", "#FFFACD", "#BDFCC9", "#FFB6C1",
    ]

    private func colorName(for hex: String) -> String {
        switch hex {
        case "#FFFFFF": return L10n.Style.colorWhite(vm.lang)
        case "#E0FFFF": return L10n.Style.colorCyan(vm.lang)
        case "#FFFACD": return L10n.Style.colorYellow(vm.lang)
        case "#BDFCC9": return L10n.Style.colorMint(vm.lang)
        case "#FFB6C1": return L10n.Style.colorPink(vm.lang)
        default: return hex
        }
    }

    var body: some View {
        HStack {
            Text(label)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 42, alignment: .trailing)

            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: hexColor) },
                    set: { hexColor = $0.toHex() }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 28)

            ForEach(Self.presetHexes, id: \.self) { hex in
                Button {
                    hexColor = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(
                            Circle().stroke(hex == hexColor ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: hex == hexColor ? 2 : 1)
                        )
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(colorName(for: hex))
            }
        }
    }
}
