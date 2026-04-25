import SwiftUI

struct MetadataOverlayInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    private var allFonts: [String] { FontUtility.allFamilies }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Overlay.title(vm.lang))
                .font(.headline)

            Toggle(L10n.Overlay.enableOverlay(vm.lang), isOn: $vm.project.metadataOverlay.isEnabled)

            if vm.project.metadataOverlay.isEnabled {
                GroupBox(L10n.Overlay.titleLabel(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L10n.Overlay.songTitle(vm.lang), text: $vm.project.metadataOverlay.titleText)
                            .textFieldStyle(.roundedBorder)

                        Picker(L10n.Overlay.font(vm.lang), selection: $vm.project.metadataOverlay.titleFontFamily) {
                            ForEach(allFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Text(L10n.Style.size(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.titleFontSize, in: 20...100, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.titleFontSize))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        SubtitleColorPicker(
                            label: "Color:",
                            hexColor: $vm.project.metadataOverlay.titleTextColorHex
                        )
                    }
                }

                GroupBox(L10n.Overlay.artist(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L10n.Overlay.artistName(vm.lang), text: $vm.project.metadataOverlay.artistText)
                            .textFieldStyle(.roundedBorder)

                        Picker(L10n.Overlay.font(vm.lang), selection: $vm.project.metadataOverlay.artistFontFamily) {
                            ForEach(allFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Text(L10n.Style.size(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.artistFontSize, in: 16...72, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.artistFontSize))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        SubtitleColorPicker(
                            label: "Color:",
                            hexColor: $vm.project.metadataOverlay.artistTextColorHex
                        )
                    }
                }

                GroupBox(L10n.Overlay.background(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Overlay.opacity(vm.lang))
                                .frame(width: 52, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.backgroundOpacity, in: 0...1, step: 0.05)
                            Text("\(Int(vm.project.metadataOverlay.backgroundOpacity * 100))%")
                                .monospacedDigit()
                                .frame(width: 36)
                        }

                        HStack {
                            Text(L10n.Overlay.radius(vm.lang))
                                .frame(width: 52, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.cornerRadius, in: 0...30, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.cornerRadius))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                }

                GroupBox(L10n.Style.position(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Overlay.top(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.topMargin, in: 20...400, step: 5)
                            Text("\(Int(vm.project.metadataOverlay.topMargin))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        HStack {
                            Text(L10n.Overlay.left(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.leftMargin, in: 20...300, step: 5)
                            Text("\(Int(vm.project.metadataOverlay.leftMargin))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }
                    }
                }

                GroupBox(L10n.Overlay.padding(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("H:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.horizontalPadding, in: 8...50, step: 2)
                            Text("\(Int(vm.project.metadataOverlay.horizontalPadding))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }

                        HStack {
                            Text("V:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.verticalPadding, in: 6...40, step: 2)
                            Text("\(Int(vm.project.metadataOverlay.verticalPadding))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }

                        HStack {
                            Text(L10n.Style.gap(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.lineSpacing, in: 0...20, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.lineSpacing))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                }
            }
        }
        .onChange(of: vm.project.metadataOverlay) { _, _ in
            vm.isDirty = true
        }
    }
}
