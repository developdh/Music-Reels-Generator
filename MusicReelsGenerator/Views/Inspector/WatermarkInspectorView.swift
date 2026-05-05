import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WatermarkInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    /// Soft cap on the embedded image size (5 MB). Anything larger and the project
    /// file balloons unnecessarily — guide the user to a smaller logo.
    private let maxImageBytes: Int = 5 * 1024 * 1024

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Watermark.title(vm.lang))
                .font(.headline)

            Toggle(L10n.Watermark.enable(vm.lang), isOn: $vm.project.watermark.enabled)
                .onChange(of: vm.project.watermark.enabled) { _, _ in
                    vm.isDirty = true
                }

            if vm.project.watermark.enabled {
                imagePicker
                if vm.project.watermark.imageData != nil {
                    positionPicker
                    sliders
                }
            }

            Text(L10n.Watermark.note(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Image picker

    @ViewBuilder
    private var imagePicker: some View {
        GroupBox(L10n.Watermark.image(vm.lang)) {
            VStack(alignment: .leading, spacing: 8) {
                if let data = vm.project.watermark.imageData,
                   let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .background(checkerboardBackground)
                        .cornerRadius(4)
                    Text(L10n.Watermark.imageSize(vm.lang, kb: data.count / 1024))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Button(L10n.Watermark.choose(vm.lang)) {
                        chooseImage()
                    }
                    if vm.project.watermark.imageData != nil {
                        Button(L10n.Watermark.remove(vm.lang)) {
                            vm.project.watermark.imageData = nil
                            vm.project.touch()
                            vm.isDirty = true
                        }
                    }
                }
            }
        }
    }

    private var checkerboardBackground: some View {
        Color.gray.opacity(0.15)
    }

    // MARK: - Position

    @ViewBuilder
    private var positionPicker: some View {
        GroupBox(L10n.Watermark.position(vm.lang)) {
            Picker("", selection: $vm.project.watermark.position) {
                ForEach(WatermarkPosition.allCases) { pos in
                    Text(L10n.WatermarkPos.displayName(pos, vm.lang)).tag(pos)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.project.watermark.position) { _, _ in
                vm.isDirty = true
            }
        }
    }

    // MARK: - Sliders

    @ViewBuilder
    private var sliders: some View {
        GroupBox(L10n.Watermark.appearance(vm.lang)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.Watermark.width(vm.lang))
                        .frame(width: 56, alignment: .trailing)
                    Slider(value: $vm.project.watermark.widthPercent, in: 5...50, step: 1)
                        .onChange(of: vm.project.watermark.widthPercent) { _, _ in vm.isDirty = true }
                    Text("\(Int(vm.project.watermark.widthPercent))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text(L10n.Watermark.opacity(vm.lang))
                        .frame(width: 56, alignment: .trailing)
                    Slider(value: $vm.project.watermark.opacity, in: 0.1...1.0, step: 0.05)
                        .onChange(of: vm.project.watermark.opacity) { _, _ in vm.isDirty = true }
                    Text("\(Int(vm.project.watermark.opacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text(L10n.Watermark.xMargin(vm.lang))
                        .frame(width: 56, alignment: .trailing)
                    Slider(value: $vm.project.watermark.xMargin, in: 0...400, step: 5)
                        .onChange(of: vm.project.watermark.xMargin) { _, _ in vm.isDirty = true }
                    Text("\(Int(vm.project.watermark.xMargin))")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text(L10n.Watermark.yMargin(vm.lang))
                        .frame(width: 56, alignment: .trailing)
                    Slider(value: $vm.project.watermark.yMargin, in: 0...400, step: 5)
                        .onChange(of: vm.project.watermark.yMargin) { _, _ in vm.isDirty = true }
                    Text("\(Int(vm.project.watermark.yMargin))")
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
        }
    }

    // MARK: - Image loading

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = L10n.Watermark.choose(vm.lang)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var allowed: [UTType] = [.png, .jpeg, .image]
        if let webp = UTType(filenameExtension: "webp") { allowed.append(webp) }
        panel.allowedContentTypes = allowed

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let raw = try Data(contentsOf: url)
            // Re-encode through NSImage → PNG so all formats land as PNG bytes.
            guard let img = NSImage(data: raw),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                vm.showError(L10n.Watermark.loadFailed(vm.lang))
                return
            }
            if png.count > maxImageBytes {
                vm.showError(L10n.Watermark.tooLarge(vm.lang, mb: maxImageBytes / (1024 * 1024)))
                return
            }
            vm.project.watermark.imageData = png
            vm.project.touch()
            vm.isDirty = true
        } catch {
            vm.showError(error.localizedDescription)
        }
    }
}
