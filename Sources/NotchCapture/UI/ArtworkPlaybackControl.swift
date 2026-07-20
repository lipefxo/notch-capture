import AppKit
import SwiftUI

struct ArtworkPlaybackControl: View {
    let artwork: NSImage?
    let trackKey: String
    let title: String
    let isPlaying: Bool
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
            ZStack {
                if showsTransportGlyph {
                    ArtworkPlaybackCanvas(
                        artwork: artwork,
                        overlayColor: overlayColor,
                        availableSize: size,
                        overlay: .transport(isPlaying: isPlaying)
                    )
                    .transition(.opacity)
                } else if isPlaying {
                    TimelineView(
                        .animation(
                            minimumInterval: 1 / 20,
                            paused: reduceMotion
                        )
                    ) { timeline in
                        ArtworkPlaybackCanvas(
                            artwork: artwork,
                            overlayColor: overlayColor,
                            availableSize: size,
                            overlay: .waveform(time: timeline.date.timeIntervalSinceReferenceDate)
                        )
                    }
                    .transition(.opacity)
                } else {
                    ArtworkPlaybackCanvas(
                        artwork: artwork,
                        overlayColor: overlayColor,
                        availableSize: size,
                        overlay: .clean
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(overlayAnimation, value: showsTransportGlyph)
            .animation(overlayAnimation, value: isPlaying)
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

private enum ArtworkCanvasOverlay {
    case clean
    case waveform(time: TimeInterval)
    case transport(isPlaying: Bool)
}

private struct ArtworkPlaybackCanvas: View {
    let artwork: NSImage?
    let overlayColor: NSColor
    let availableSize: CGFloat
    let overlay: ArtworkCanvasOverlay

    var body: some View {
        ZStack {
            artworkLayer
            overlayLayer
        }
        .frame(width: availableSize, height: availableSize)
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

    @ViewBuilder
    private var overlayLayer: some View {
        switch overlay {
        case .clean:
            EmptyView()
        case let .waveform(time):
            Canvas { context, size in
                let barWidth = max(1.5, size.width * 0.07)
                let barSpacing = max(0.9, size.width * 0.045)
                let totalWidth = (barWidth * 4) + (barSpacing * 3)
                let startX = (size.width - totalWidth) / 2
                context.fill(
                    Path { path in
                        for index in 0..<4 {
                            let height = barHeight(index: index, size: size.width, time: time)
                            path.addRoundedRect(
                                in: CGRect(
                                    x: startX + (CGFloat(index) * (barWidth + barSpacing)),
                                    y: (size.height - height) / 2,
                                    width: barWidth,
                                    height: height
                                ),
                                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
                            )
                        }
                    },
                    with: .color(Color(nsColor: overlayColor))
                )
            }
        case let .transport(isPlaying):
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: max(8, availableSize * 0.36), weight: .bold))
                .foregroundStyle(Color(nsColor: overlayColor))
                .offset(x: isPlaying ? 0 : availableSize * 0.025)
        }
    }

    private func barHeight(index: Int, size: CGFloat, time: TimeInterval) -> CGFloat {
        let maximum = size * 0.44
        let minimum = max(2.5, size * 0.14)
        let wave = CGFloat((sin((time * 5.2) + Double(index) * 1.7) + 1) / 2)
        return minimum + ((maximum - minimum) * wave)
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
