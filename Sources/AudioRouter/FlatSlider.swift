import SwiftUI

/// A flat fill-bar slider with a round knob, in the style of SoundSource's per-app
/// volume controls: drag the knob (or tap anywhere in the track) to set the value.
struct FlatSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1.5
    var tint: Color = .accentColor

    private let trackHeight: CGFloat = 4
    private let knobDiameter: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let usableWidth = max(geo.size.width - knobDiameter, 1)
            let fraction = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            let knobCenterX = knobDiameter / 2 + CGFloat(fraction) * usableWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: knobCenterX, height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
                    .offset(x: knobCenterX - knobDiameter / 2)
            }
            .frame(height: knobDiameter)
            .contentShape(Rectangle().inset(by: -6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = min(max((drag.location.x - knobDiameter / 2) / usableWidth, 0), 1)
                        value = range.lowerBound + Float(f) * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: knobDiameter)
    }
}
