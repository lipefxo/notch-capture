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
        Image(
            nsImage: ArtworkPlaybackRenderer.image(
                artwork: artwork,
                accentColor: accentColor,
                size: availableSize,
                overlay: overlay
            )
        )
        .resizable()
        .interpolation(.high)
        .accessibilityHidden(true)
    }
}

private enum ArtworkPlaybackRenderer {
    static func image(
        artwork: NSImage?,
        accentColor: NSColor,
        size: CGFloat,
        overlay: ArtworkCanvasOverlay
    ) -> NSImage {
        let scale = max(2, NSScreen.main?.backingScaleFactor ?? 2)
        let pixels = max(1, Int(ceil(size * scale)))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: representation) else {
            return artwork ?? NSImage(size: NSSize(width: size, height: size))
        }

        representation.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: scale, y: scale)
        drawArtwork(artwork, in: context, size: size, accentColor: accentColor)

        context.saveGState()
        context.setBlendMode(artwork == nil ? .normal : .difference)
        switch overlay {
        case .clean:
            break
        case let .waveform(time):
            drawBars(in: context, size: size, time: time, accentColor: accentColor)
        case let .transport(isPlaying):
            drawTransportGlyph(
                in: context,
                size: size,
                isPlaying: isPlaying,
                accentColor: accentColor
            )
        }
        context.restoreGState()
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let rendered = NSImage(size: NSSize(width: size, height: size))
        rendered.addRepresentation(representation)
        return rendered
    }

    private static func barHeight(index: Int, size: CGFloat, time: TimeInterval) -> CGFloat {
        let maximum = size * 0.44
        let minimum = max(2.5, size * 0.14)
        let wave = CGFloat((sin((time * 5.2) + Double(index) * 1.7) + 1) / 2)
        return minimum + ((maximum - minimum) * wave)
    }

    private static func drawArtwork(
        _ artwork: NSImage?,
        in context: CGContext,
        size: CGFloat,
        accentColor: NSColor
    ) {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        if let artwork {
            artwork.draw(
                in: aspectFillRect(imageSize: artwork.size, bounds: bounds),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            context.setFillColor(NSColor.white.withAlphaComponent(0.07).cgColor)
            context.fill(bounds)
            drawSymbol(
                named: "music.note",
                in: context,
                size: size * 0.42,
                canvasSize: size,
                accentColor: accentColor,
                opticalOffset: 0
            )
        }
    }

    private static func drawBars(
        in context: CGContext,
        size: CGFloat,
        time: TimeInterval,
        accentColor: NSColor
    ) {
        let barWidth = max(1.5, size * 0.07)
        let barSpacing = max(0.9, size * 0.045)
        let totalWidth = (barWidth * 4) + (barSpacing * 3)
        let startX = (size - totalWidth) / 2
        context.setFillColor(deviceColor(accentColor).cgColor)

        for index in 0..<4 {
            let barHeight = barHeight(index: index, size: size, time: time)
            let rect = CGRect(
                x: startX + (CGFloat(index) * (barWidth + barSpacing)),
                y: (size - barHeight) / 2,
                width: barWidth,
                height: barHeight
            )
            context.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
            context.fillPath()
        }
    }

    private static func drawTransportGlyph(
        in context: CGContext,
        size: CGFloat,
        isPlaying: Bool,
        accentColor: NSColor
    ) {
        drawSymbol(
            named: isPlaying ? "pause.fill" : "play.fill",
            in: context,
            size: max(8, size * 0.36),
            canvasSize: size,
            accentColor: accentColor,
            opticalOffset: isPlaying ? 0 : size * 0.025
        )
    }

    private static func drawSymbol(
        named name: String,
        in context: CGContext,
        size: CGFloat,
        canvasSize: CGFloat,
        accentColor: NSColor,
        opticalOffset: CGFloat
    ) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let pointConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
        let paletteConfiguration = NSImage.SymbolConfiguration(paletteColors: [deviceColor(accentColor)])
        guard let configured = symbol.withSymbolConfiguration(pointConfiguration.applying(paletteConfiguration)) else {
            return
        }
        let aspect = configured.size.width / max(1, configured.size.height)
        let drawSize = CGSize(width: size * aspect, height: size)
        configured.draw(
            in: CGRect(
                x: ((canvasSize - drawSize.width) / 2) + opticalOffset,
                y: (canvasSize - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    private static func deviceColor(_ color: NSColor) -> NSColor {
        color.usingColorSpace(.deviceRGB) ?? color
    }

    private static func aspectFillRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - (scaled.width / 2),
            y: bounds.midY - (scaled.height / 2),
            width: scaled.width,
            height: scaled.height
        )
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
