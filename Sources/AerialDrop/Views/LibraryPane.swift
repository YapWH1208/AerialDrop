import AppKit
import SwiftUI

struct LibraryPane: View {
    @EnvironmentObject private var model: AppModel

    private let wallpaperColumns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    SectionHeader(title: "Imported Wallpapers", systemImage: "photo.stack")
                    Text("\(model.wallpapers.count)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }

                if model.wallpapers.isEmpty {
                    emptyLibrary
                } else {
                    LazyVGrid(columns: wallpaperColumns, spacing: 16) {
                        ForEach(model.wallpapers) { wallpaper in
                            WallpaperCard(wallpaper: wallpaper) {
                                model.remove(wallpaper)
                            }
                        }
                    }
                    .animation(.spring(duration: 0.35, bounce: 0.2), value: model.wallpapers)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No AerialDrop Wallpapers", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Imported videos will appear here and under the AerialDrop section in System Settings.")
        }
        .frame(maxWidth: .infinity, minHeight: 380)
        .glassEffect(.regular.tint(.accentColor.opacity(0.12)), in: .rect(cornerRadius: 22))
    }
}