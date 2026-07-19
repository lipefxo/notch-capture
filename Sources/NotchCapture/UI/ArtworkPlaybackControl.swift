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
    @State private var accentColor = NSColor(
        srgbRed: 0.23,
        green: 0.78,
        blue: 0.50,
        alpha: 1
    )

    private var showsTransportGlyph: Bool { isHovered || isFocused || forcesPreviewHover }

    var body: some View {
        Button(action: action) {
            ZStack {
                if showsTransportGlyph {
                    ArtworkPlaybackCanvas(
                        artwork: artwork,
                        accentColor: accentColor,
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
                            accentColor: accentColor,
                            availableSize: size,
                            overlay: .waveform(time: timeline.date.timeIntervalSinceReferenceDate)
                        )
                    }
                    .transition(.opacity)
                } else {
                    ArtworkPlaybackCanvas(
                        artwork: artwork,
                        accentColor: accentColor,
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
            accentColor = ArtworkAccentColor.color(from: artwork) ?? NSColor(
                srgbRed: 0.23,
                green: 0.78,
                blue: 0.50,
                alpha: 1
            )
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
    let accentColor: NSColor
    let availableSize: CGFloat
    let overlay: ArtworkCanvasOverlay

    var body: some View {
        ZStack {
            artworkLayer
            overlayLayer
                .blendMode(artwork == nil ? .normal : .difference)
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
                    .foregroundStyle(Color(nsColor: accentColor))
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
                    with: .color(Color(nsColor: accentColor))
                )
            }
        case let .transport(isPlaying):
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: max(8, availableSize * 0.36), weight: .bold))
                .foregroundStyle(Color(nsColor: accentColor))
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

enum ArtworkAccentColor {
    struct Sample {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
    }

    static func color(from image: NSImage?) -> NSColor? {
        guard let image, let resolved = resolvedColor(from: samples(from: image)) else {
            return nil
        }
        return resolved
    }

    static func resolvedColor(from samples: [Sample]) -> NSColor? {
        let visible = samples.filter { $0.alpha >= 0.5 }
        guard !visible.isEmpty else { return nil }

        let binCount = 24
        var bins = Array(repeating: HueBin(), count: binCount)
        var chromaticWeight = 0.0

        for sample in visible {
            let hsv = hsv(red: sample.red, green: sample.green, blue: sample.blue)
            guard hsv.saturation >= 0.12 else { continue }

            let usableBrightness = max(0.18, 1 - abs(hsv.brightness - 0.58) * 1.25)
            let weight = hsv.saturation * usableBrightness * sample.alpha
            let index = min(binCount - 1, Int(hsv.hue * Double(binCount)))
            bins[index].weight += weight
            bins[index].saturation += hsv.saturation * weight
            chromaticWeight += weight
        }

        let chromaticThreshold = Double(visible.count) * 0.055
        guard chromaticWeight >= chromaticThreshold,
              let dominantIndex = bins.indices.max(by: { bins[$0].weight < bins[$1].weight }),
              bins[dominantIndex].weight > 0 else {
            return NSColor(srgbRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        }

        let dominant = bins[dominantIndex]
        let hue = (Double(dominantIndex) + 0.5) / Double(binCount)
        let saturation = min(0.88, max(0.52, dominant.saturation / dominant.weight))
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: 0.94, alpha: 1)
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
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
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

    private static func hsv(red: Double, green: Double, blue: Double) -> (
        hue: Double,
        saturation: Double,
        brightness: Double
    ) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        guard delta > 0 else { return (0, saturation, maximum) }

        let rawHue: Double
        if maximum == red {
            rawHue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            rawHue = ((blue - red) / delta) + 2
        } else {
            rawHue = ((red - green) / delta) + 4
        }
        let hue = ((rawHue / 6).truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1)
        return (hue, saturation, maximum)
    }

    private struct HueBin {
        var weight = 0.0
        var saturation = 0.0
    }
}
