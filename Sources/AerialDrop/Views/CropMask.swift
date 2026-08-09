import SwiftUI

struct CropMask: View {
    let cropOffset: Double
    let resolution: CGSize

    var body: some View {
        GeometryReader { geo in
            let horizontal = cropBandFractions(cropOffset: cropOffset, sourceSize: resolution)
            let vertical = verticalCropBandFractions(sourceSize: resolution)
            ZStack {
                Rectangle().fill(.black.opacity(0.45)).frame(width: geo.size.width * horizontal.left).frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(.black.opacity(0.45)).frame(width: geo.size.width * horizontal.right).frame(maxWidth: .infinity, alignment: .trailing)
                Rectangle().fill(.black.opacity(0.45)).frame(height: geo.size.height * vertical.top).frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(.black.opacity(0.45)).frame(height: geo.size.height * vertical.bottom).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
