import AppKit
import SwiftUI

struct ArtworkPlaybackControl: View {
    let artwork: NSImage?
    let trackKey: String
    let title: String
    let isPlaying: Bool
    let waveform: MusicWaveformLevels
    let size: CGFloat
    let cornerRadius: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var overlayColor = NSColor.white

    private var showsTransportGlyph: Bool { isHovered || isFocused || forcesPreviewHover }

    var body: some View {
        Button(action: action) {
            ArtworkPlaybackCanvas(
                artwork: artwork,
                overlayColor: overlayColor,
                availableSize: size,
                waveform: reduceMotion ? .silent : waveform,
                isPlaying: isPlaying,
                showsTransportGlyph: showsTransportGlyph
            )
                .id(artworkIdentity)
                .transition(reduceMotion ? .opacity : .musicArtworkSwap)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(overlayAnimation, value: showsTransportGlyph)
            .animation(overlayAnimation, value: isPlaying)
            .animation(
                reduceMotion ? NotchMotion.reducedMotion : NotchMotion.musicTrackSwap,
                value: artworkIdentity
            )
        }
        .buttonStyle(ArtworkPlaybackButtonStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .task(id: artworkIdentity) {
            overlayColor = ArtworkOverlayColor.color(from: artwork)
        }
        .help(isPlaying ? "Pause \(title)" : "Play \(title)")
        .accessibilityLabel(isPlaying ? "Pause \(title)" : "Play \(title)")
        .accessibilityValue(isPlaying ? "Playing" : "Paused")
    }

    private var artworkIdentity: ArtworkIdentity {
        ArtworkIdentity(
            trackKey: trackKey,
            imageIdentifier: artwork.map(ObjectIdentifier.init)
        )
    }

    private var forcesPreviewHover: Bool {
#if DEBUG
        CommandLine.arguments.contains("--preview-music-hover")
#else
        false
#endif
    }

    private var overlayAnimation: Animation? {
        guard !forcesPreviewHover else { return nil }
        return reduceMotion ? NotchMotion.reducedMotion : NotchMotion.hover
    }
}

private struct ArtworkIdentity: Hashable {
    let trackKey: String
    let imageIdentifier: ObjectIdentifier?
}

private struct ArtworkPlaybackButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : NotchMotion.controlPress, value: configuration.isPressed)
    }
}

private struct ArtworkPlaybackCanvas: View {
    let artwork: NSImage?
    let overlayColor: NSColor
    let availableSize: CGFloat
    let waveform: MusicWaveformLevels
    let isPlaying: Bool
    let showsTransportGlyph: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            artworkLayer
            waveformLayer
                .opacity(isPlaying && !showsTransportGlyph ? 1 : 0)
                .scaleEffect(isPlaying && !showsTransportGlyph ? 1 : 0.82)
            transportLayer
                .opacity(showsTransportGlyph ? 1 : 0)
                .scaleEffect(showsTransportGlyph ? 1 : 0.72)
        }
        .frame(width: availableSize, height: availableSize)
        .animation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.hover, value: showsTransportGlyph)
        .animation(reduceMotion ? NotchMotion.reducedMotion : NotchMotion.musicPlaybackState, value: isPlaying)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artworkLayer: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        } else {
            ZStack {
                Color.white.opacity(0.07)
                Image(systemName: "music.note")
                    .font(.system(size: availableSize * 0.42, weight: .bold))
                    .foregroundStyle(Color(nsColor: overlayColor))
            }
        }
    }

    private var waveformLayer: some View {
        ArtworkWaveformShape(levels: waveform)
            .fill(Color(nsColor: overlayColor))
            .animation(reduceMotion ? nil : NotchMotion.musicWaveform, value: waveform)
    }

    private var transportLayer: some View {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: max(8, availableSize * 0.36), weight: .bold))
            .foregroundStyle(Color(nsColor: overlayColor))
            .offset(x: isPlaying ? 0 : availableSize * 0.025)
            .contentTransition(.symbolEffect(.replace))
    }

}

private struct ArtworkWaveformShape: Shape {
    var levels: MusicWaveformLevels

    var animatableData: AnimatablePair<
        AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>,
        Double
    > {
        get {
            AnimatablePair(
                AnimatablePair(
                    AnimatablePair(level(at: 0), level(at: 1)),
                    AnimatablePair(level(at: 2), level(at: 3))
                ),
                level(at: 4)
            )
        }
        set {
            levels = MusicWaveformLevels(values: [
                newValue.first.first.first,
                newValue.first.first.second,
                newValue.first.second.first,
                newValue.first.second.second,
                newValue.second,
            ])
        }
    }

    func path(in rect: CGRect) -> Path {
        let barCount = CGFloat(MusicWaveformLevels.barCount)
        let barWidth = max(1.4, rect.width * 0.06)
        let barSpacing = max(0.8, rect.width * 0.038)
        let totalWidth = (barWidth * barCount) + (barSpacing * (barCount - 1))
        let startX = rect.minX + ((rect.width - totalWidth) / 2)
        let maximum = rect.width * 0.44
        let minimum = max(2.5, rect.width * 0.14)

        return Path { path in
            for index in 0..<MusicWaveformLevels.barCount {
                let height = minimum + ((maximum - minimum) * CGFloat(level(at: index)))
                path.addRoundedRect(
                    in: CGRect(
                        x: startX + (CGFloat(index) * (barWidth + barSpacing)),
                        y: rect.midY - (height / 2),
                        width: barWidth,
                        height: height
                    ),
                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                )
            }
        }
    }

    private func level(at index: Int) -> Double {
        levels.values.indices.contains(index) ? levels.values[index] : 0
    }
}

enum ArtworkOverlayColor {
    struct Sample {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    static func color(from image: NSImage?) -> NSColor {
        guard let image else { return .white }
        return resolvedColor(from: samples(from: image)) ?? .white
    }

    static func resolvedColor(from samples: [Sample]) -> NSColor? {
        let weightedSamples = samples.filter { $0.alpha > 0 }
        guard !weightedSamples.isEmpty else { return nil }

        let totalAlpha = weightedSamples.reduce(0) { $0 + $1.alpha }
        let luminance = weightedSamples.reduce(0) { result, sample in
            result + (relativeLuminance(of: sample) * sample.alpha)
        } / totalAlpha

        // At this point the contrast ratios for black and white are equal.
        return luminance <= 0.179 ? .white : .black
    }

    private static func samples(from image: NSImage) -> [Sample] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        let width = 24
        let height = 24
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .medium
            let crop = centeredFootprint(in: cgImage)
            guard let footprintImage = cgImage.cropping(to: crop) else { return false }
            context.draw(footprintImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return [] }

        return stride(from: 0, to: pixels.count, by: 4).map { offset in
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else {
                return Sample(red: 0, green: 0, blue: 0, alpha: 0)
            }
            return Sample(
                red: min(1, (Double(pixels[offset]) / 255) / alpha),
                green: min(1, (Double(pixels[offset + 1]) / 255) / alpha),
                blue: min(1, (Double(pixels[offset + 2]) / 255) / alpha),
                alpha: alpha
            )
        }
    }

    private static func centeredFootprint(in image: CGImage) -> CGRect {
        let fraction = 0.55
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let footprintWidth = max(1, (width * fraction).rounded(.down))
        let footprintHeight = max(1, (height * fraction).rounded(.down))
        return CGRect(
            x: ((width - footprintWidth) / 2).rounded(.down),
            y: ((height - footprintHeight) / 2).rounded(.down),
            width: footprintWidth,
            height: footprintHeight
        )
    }

    private static func relativeLuminance(of sample: Sample) -> Double {
        let red = linearizedSRGB(sample.red)
        let green = linearizedSRGB(sample.green)
        let blue = linearizedSRGB(sample.blue)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private static func linearizedSRGB(_ component: Double) -> Double {
        let clamped = min(1, max(0, component))
        return clamped <= 0.04045
            ? clamped / 12.92
            : pow((clamped + 0.055) / 1.055, 2.4)
    }
}
