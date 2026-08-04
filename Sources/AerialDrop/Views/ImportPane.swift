import SwiftUI

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
    }
}

struct ImportPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var hoveringDropZone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Import a Video", systemImage: "square.and.arrow.down")

                dropZone

                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallpaper name")
                        .font(.callout.weight(.medium))
                    TextField("Example: Yoimiya 4K", text: $model.title)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                }

                if model.isWorking {
                    progressCard
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }

                Button {
                    model.importSelectedVideo()
                } label: {
                    Label {
                        Text("Import into Aerials")
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .symbolEffect(.pulse, options: .repeating, isActive: model.isWorking)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!model.canImport)

                whatHappensCard

                Spacer(minLength: 8)

                Text("After importing, select the new item in System Settings → Wallpaper; macOS applies it to Desktop, Lock Screen and Screen Saver natively. You may quit AerialDrop after setup; macOS handles playback natively.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }

    private var dropZone: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .allowsHitTesting(false)
            dropZoneButton
        }
        .frame(maxWidth: .infinity)
    }

    private var dropZoneButton: some View {
        Button {
            model.showingFileImporter = true
        } label: {
            VStack(spacing: 12) {
                if let url = model.selectedVideo {
                    Image(systemName: "film.fill")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Click to choose another file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 30, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .padding(18)
                        .glassEffect(.regular, in: Circle())
                        .symbolEffect(.pulse, isActive: hoveringDropZone)
                    Text("Choose or drop a video")
                        .font(.headline)
                    Text("MP4 or MOV · The source file is not modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(16)
            .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    .foregroundStyle(hoveringDropZone ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.quaternary))
            }
            .scaleEffect(hoveringDropZone ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hoveringDropZone = $0 }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: hoveringDropZone)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            model.chooseVideo(first)
            return true
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: model.stage.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: model.stage != .finished)
                    .foregroundStyle(.tint)
                Text(model.stage.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            ProgressView(value: model.stage.progress)
                .tint(.accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var whatHappensCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happens")
                .font(.callout.weight(.semibold))
            ForEach(whatHappensRows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 26, height: 26)
                        .background(.tint.opacity(0.14), in: Circle())
                    Text(row.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private struct WhatHappensRow: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }

    private let whatHappensRows: [WhatHappensRow] = [
        WhatHappensRow(icon: "film", text: "Builds an 80-second, 30 fps HEVC Main10 stream with native temporal sub-layers"),
        WhatHappensRow(icon: "photo", text: "Normalizes timestamp zero and creates a Tahoe-compatible HEIF preview"),
        WhatHappensRow(icon: "doc.badge.gearshape", text: "Backs up entries.json and preserves other apps’ entries"),
        WhatHappensRow(icon: "rectangle.stack", text: "Adds a complete Tahoe Aerial catalogue entry")
    ]
}