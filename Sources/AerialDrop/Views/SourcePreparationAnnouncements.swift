import SwiftUI

struct SourcePreparationAnnouncements: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .onChange(of: model.isSelectedVideoValid) { wasValid, isValid in
                guard !wasValid, isValid, model.selectedVideo != nil else { return }
                AccessibilityNotification.Announcement(
                    "Video ready to configure."
                ).post()
            }
            .onChange(of: model.sourcePreparationError) { _, error in
                guard let error else { return }
                AccessibilityNotification.Announcement(
                    "Video preparation failed. \(error)"
                ).post()
            }
    }
}
