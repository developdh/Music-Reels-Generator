import SwiftUI

struct CropInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    private var isHorizontal: Bool {
        vm.project.cropSettings.mode == .horizontal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Crop.settings(vm.lang))
                .font(.headline)

            // Mode picker
            GroupBox(L10n.Crop.mode(vm.lang)) {
                Picker("", selection: $vm.project.cropSettings.mode) {
                    ForEach(CropMode.allCases) { mode in
                        Text(L10n.CropModeName.displayName(mode, vm.lang)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.project.cropSettings.mode) { _, _ in
                    vm.isDirty = true
                }
            }

            // 세로모드: horizontal offset (가로모드에서는 항상 중앙)
            if !isHorizontal {
                GroupBox(L10n.Crop.horizontalPosition(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("L")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Slider(value: $vm.project.cropSettings.horizontalOffset, in: -1...1)
                                .onChange(of: vm.project.cropSettings.horizontalOffset) { _, _ in
                                    vm.isDirty = true
                                }
                            Text("R")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Button(L10n.Crop.centerH(vm.lang)) {
                            vm.project.cropSettings.horizontalOffset = 0
                            vm.isDirty = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            GroupBox(isHorizontal ? L10n.Crop.videoPosition(vm.lang) : L10n.Crop.verticalPosition(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("T")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: $vm.project.cropSettings.verticalOffset, in: -1...1)
                            .onChange(of: vm.project.cropSettings.verticalOffset) { _, _ in
                                vm.isDirty = true
                            }
                        Text("B")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Button(L10n.Crop.centerV(vm.lang)) {
                        vm.project.cropSettings.verticalOffset = 0
                        vm.isDirty = true
                    }
                    .controlSize(.small)
                }
            }

            GroupBox(L10n.Crop.zoom(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("1x")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: $vm.project.cropSettings.zoomScale, in: 1.0...3.0, step: 0.05)
                            .onChange(of: vm.project.cropSettings.zoomScale) { _, _ in
                                vm.isDirty = true
                            }
                        Text("\(String(format: "%.1f", vm.project.cropSettings.zoomScale))x")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 30)
                    }

                    if vm.project.cropSettings.zoomScale > 1.0 {
                        Button(L10n.Crop.resetZoom(vm.lang)) {
                            vm.project.cropSettings.zoomScale = 1.0
                            vm.isDirty = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            // 가로모드: blur intensity
            if isHorizontal {
                GroupBox(L10n.Crop.blur(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Crop.blurWeak(vm.lang))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Slider(value: $vm.project.cropSettings.blurRadius, in: 10...50, step: 1)
                                .onChange(of: vm.project.cropSettings.blurRadius) { _, _ in
                                    vm.isDirty = true
                                }
                            Text(L10n.Crop.blurStrong(vm.lang))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(L10n.Crop.blurIntensity(vm.lang, value: Int(vm.project.cropSettings.blurRadius)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            GroupBox(L10n.Crop.output(vm.lang)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resolution: \(vm.project.cropSettings.outputWidth)x\(vm.project.cropSettings.outputHeight)")
                        .font(.caption)
                    Text("Aspect: 9:16 (Reels/Shorts)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
