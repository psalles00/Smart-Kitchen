import SwiftUI
#if os(iOS)
import UIKit
import MetalKit
#endif

struct ThemedBackgroundView: View {
    let theme: PageTheme
    var progress: CGFloat = 1.0
    var animates: Bool = true

    var body: some View {
        #if os(iOS)
        SavoriaShaderBackground(theme: theme, animates: animates)
            .opacity(progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        StaticPageBackground(theme: theme)
            .opacity(progress)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if os(iOS)
/// Every page samples the same clock, viewport and palette transition.
struct SavoriaBackdropPalette {
    var target: PageTheme = .home
    private var source: SIMD3<Double> = PageTheme.home.shaderRGB
    private var startedAt: TimeInterval = 0

    func rgb(at time: TimeInterval) -> SIMD3<Double> {
        let fraction = min(1, max(0, (time - startedAt) / 0.55))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return source + (target.shaderRGB - source) * eased
    }

    mutating func transition(to theme: PageTheme) {
        let now = ProcessInfo.processInfo.systemUptime
        source = rgb(at: now)
        startedAt = now
        target = theme
    }
}

private struct SavoriaBackdropPaletteKey: EnvironmentKey {
    static let defaultValue: SavoriaBackdropPalette? = nil
}
private struct SavoriaBackdropViewportKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}
extension EnvironmentValues {
    var savoriaBackdropPalette: SavoriaBackdropPalette? {
        get { self[SavoriaBackdropPaletteKey.self] }
        set { self[SavoriaBackdropPaletteKey.self] = newValue }
    }
    var savoriaBackdropViewport: CGSize {
        get { self[SavoriaBackdropViewportKey.self] }
        set { self[SavoriaBackdropViewportKey.self] = newValue }
    }
}

private enum SavoriaShaderClock {
    static let epoch = ProcessInfo.processInfo.systemUptime
}

@MainActor
private enum SavoriaBackdropDiagnostics {
    static let enabled = ActionTrace.enabled && ProcessInfo.processInfo.arguments.contains("-SavoriaBackdropGPUTrace")
    static let maximumDimension: CGFloat = {
        let args = ProcessInfo.processInfo.arguments
        guard enabled, let index = args.firstIndex(of: "-SavoriaBackdropMaxDimension"),
              args.indices.contains(index + 1), let value = Double(args[index + 1]),
              value.isFinite, (96...384).contains(value) else { return 384 }
        return CGFloat(value)
    }()
}

/// GPU timestamps are read only after completion. No per-frame logging or I/O.
/// Normal launches never allocate this probe; each probe records one bounded file.
private final class SavoriaBackdropGPUProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    private var milliseconds: [Double] = []
    private var finished = false
    private let directory: URL
    private let id = UUID().uuidString

    struct Report: Codable, Sendable {
        let page: String
        let drawableWidth: Int
        let drawableHeight: Int
        let attempts: Int
        let gpuMilliseconds: [Double]
        let method: String
    }

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackdropGPUTraces", isDirectory: true)
        milliseconds.reserveCapacity(180)
    }

    func record(start: Double, end: Double, width: Int, height: Int, page: String) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        attempts += 1
        // Omit warmup, and never represent unavailable timestamps as zero cost.
        if attempts > 30, start > 0, end >= start { milliseconds.append((end - start) * 1000) }
        guard milliseconds.count >= 180 || attempts >= 300 else { lock.unlock(); return }
        finished = true
        let report = Report(page: page, drawableWidth: width, drawableHeight: height,
                            attempts: attempts, gpuMilliseconds: milliseconds,
                            method: "MTLCommandBuffer gpuEndTime - gpuStartTime after completion; shader pass only, not UI FPS")
        lock.unlock()
        let directory = directory
        let filename = "gpu-\(page)-\(id).json"
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(report).write(to: directory.appendingPathComponent(filename), options: .atomic)
            } catch {
                PerformanceLogger.error(.launch, "Backdrop GPU diagnostic could not be written")
            }
        }
    }
}

private struct SavoriaShaderBackground: View {
    let theme: PageTheme
    let animates: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.savoriaBackdropPalette) private var palette
    @Environment(\.savoriaBackdropViewport) private var viewport

    var body: some View {
        Group {
            if SavoriaMetalBackdropResources.shared.pipeline != nil {
                SavoriaMetalBackdrop(theme: theme, palette: palette, viewport: viewport,
                                     animates: animates && scenePhase == .active,
                                     reduceMotion: reduceMotion)
            } else {
                StaticPageBackground(theme: theme)
            }
        }
        .overlay {
            LinearGradient(colors: [.black.opacity(contrast == .increased ? 0.60 : 0.42), .black.opacity(contrast == .increased ? 0.85 : 0.72)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The CPPN is independent of SwiftUI's update/render passes. Its drawable has
/// a bounded pixel size; Core Animation scales the soft field to the viewport.
@MainActor
private final class SavoriaMetalBackdropResources {
    static let shared = SavoriaMetalBackdropResources()
    let device: MTLDevice?
    let pipeline: MTLRenderPipelineState?

    private init() {
        device = MTLCreateSystemDefaultDevice()
        guard let device, let library = device.makeDefaultLibrary() else { pipeline = nil; return }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "savoriaBackdropVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "savoriaBackdropFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            PerformanceLogger.event(.launch, "Backdrop Metal pipeline ready")
        } catch {
            pipeline = nil
            PerformanceLogger.error(.launch, "Backdrop Metal pipeline failed: \(error.localizedDescription)")
        }
    }
}

private struct SavoriaMetalBackdrop: UIViewRepresentable {
    let theme: PageTheme
    let palette: SavoriaBackdropPalette?
    let viewport: CGSize
    let animates: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SavoriaBackdropMetalView {
        let view = SavoriaBackdropMetalView(frame: .zero, device: SavoriaMetalBackdropResources.shared.device)
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = true
        view.backgroundColor = .black
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SavoriaBackdropMetalView, context: Context) {
        context.coordinator.theme = theme
        context.coordinator.palette = palette
        context.coordinator.viewport = viewport
        context.coordinator.reduceMotion = reduceMotion
        view.wantsAnimation = animates && !reduceMotion
        view.updateRenderState()
        if view.isPaused { view.draw() }
    }

    static func dismantleUIView(_ view: SavoriaBackdropMetalView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MTKViewDelegate {
        var theme: PageTheme = .home
        var palette: SavoriaBackdropPalette?
        var viewport: CGSize = .zero
        var reduceMotion = false
        private let queue = SavoriaMetalBackdropResources.shared.device?.makeCommandQueue()
        private let inFlight = DispatchSemaphore(value: 2)
        private lazy var gpuProbe: SavoriaBackdropGPUProbe? = SavoriaBackdropDiagnostics.enabled ? SavoriaBackdropGPUProbe() : nil

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

        func draw(in view: MTKView) {
            guard view.bounds.width > 0, view.bounds.height > 0,
                  let pipeline = SavoriaMetalBackdropResources.shared.pipeline,
                  let queue, inFlight.wait(timeout: .now()) == .success else { return }
            guard let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let command = queue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else {
                inFlight.signal()
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let tint = !reduceMotion && palette?.target == theme ? palette!.rgb(at: now) : theme.shaderRGB
            let field = viewport.width > 0 ? viewport : view.bounds.size
            // Three float4s keep Swift/Metal alignment explicit.
            var uniforms = (SIMD4<Float>(Float(view.bounds.width), Float(view.bounds.height), Float(field.width), Float(field.height)),
                            SIMD4<Float>(Float(tint.x), Float(tint.y), Float(tint.z), 1),
                            SIMD4<Float>(reduceMotion ? 0 : Float(now - SavoriaShaderClock.epoch), 0, 0, 0))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout.size(ofValue: uniforms), index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            let semaphore = inFlight
            let probe = gpuProbe
            let width = Int(view.drawableSize.width)
            let height = Int(view.drawableSize.height)
            let page = theme.rawValue
            command.addCompletedHandler { buffer in
                semaphore.signal()
                probe?.record(start: buffer.gpuStartTime, end: buffer.gpuEndTime,
                              width: width, height: height, page: page)
            }
            command.present(drawable)
            command.commit()
        }
    }
}

private final class SavoriaBackdropMetalView: MTKView {
    var wantsAnimation = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRenderState()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = min(1, SavoriaBackdropDiagnostics.maximumDimension / max(bounds.width, bounds.height))
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()),
                          height: max(1, (bounds.height * scale).rounded()))
        if drawableSize != size { drawableSize = size }
        if isPaused { draw() }
    }

    func updateRenderState() {
        isPaused = !wantsAnimation || window == nil
    }
}

private extension PageTheme {
    var shaderRGB: SIMD3<Double> {
        let hue: Double = switch self {
        case .home: 0.9841
        case .lists: 0.5982
        case .recipes: 0.1050
        case .nutrients: 0.3958
        case .settings: 0.6000
        case .assistant: 0.6667
        }
        let chroma = 0.82 * 0.86
        let sector = hue * 6
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: SIMD3<Double> = switch Int(sector) {
        case 0: SIMD3(chroma, x, 0)
        case 1: SIMD3(x, chroma, 0)
        case 2: SIMD3(0, chroma, x)
        case 3: SIMD3(0, x, chroma)
        case 4: SIMD3(x, 0, chroma)
        default: SIMD3(chroma, 0, x)
        }
        return rgb + SIMD3(repeating: 0.82 - chroma)
    }

    var shaderTint: Color {
        let rgb = shaderRGB
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    var shaderHighlight: Color {
        let rgb = shaderRGB + (SIMD3<Double>(repeating: 1) - shaderRGB) * 0.6
        return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }
}

/// Rotina's neutral column and two-layer edge, fitted to Savoria's existing geometry.
struct SavoriaColumnSurface: View {
    let theme: PageTheme
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: cornerRadius)
    }

    var body: some View {
        shape
            .fill(colorScheme == .dark ? Color(red: 14 / 255.0, green: 14 / 255.0, blue: 16 / 255.0) : .white)
            .overlay {
                LinearGradient(colors: [theme.shaderTint.opacity(contrast == .increased ? 0 : (colorScheme == .dark ? 0.04 : 0.015)), .clear],
                               startPoint: .topLeading, endPoint: UnitPoint(x: 0.5, y: 0.3))
                    .clipShape(shape)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct SavoriaColumnBorder: View {
    let theme: PageTheme
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: cornerRadius)
    }

    var body: some View {
        SavoriaLuminousBorder(accent: theme.shaderTint, cornerRadius: cornerRadius,
                             topCornersOnly: true, highlight: theme.shaderHighlight)
    }
}

/// A decorative edge with a brighter top, fading into the panel's own tint.
struct SavoriaLuminousBorder: View {
    let accent: Color
    var cornerRadius: CGFloat = 28
    var topCornersOnly = false
    var highlight: Color? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var topColor: Color {
        if let highlight { return highlight }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        return Color(red: Double(r + (1 - r) * 0.6),
                     green: Double(g + (1 - g) * 0.6),
                     blue: Double(b + (1 - b) * 0.6))
    }

    private var gradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: topColor.opacity(colorScheme == .dark ? 0.58 : 0.45), location: 0),
            .init(color: accent.opacity(0.18), location: 0.025),
            .init(color: accent.opacity(0.025), location: 0.12),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        Group {
            if topCornersOnly {
                UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: cornerRadius)
                    .strokeBorder(gradient, lineWidth: contrast == .increased ? 1.25 : 0.75)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: contrast == .increased ? 1.25 : 0.75)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#endif

struct StaticPageBackground: View {
    let theme: PageTheme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let orbSize = max(width, height) * 1.05

            ZStack {
                Color.black

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.88, green: 0.94, blue: 1.00).opacity(0.92),
                                orbAccentTint.opacity(0.58),
                                orbDarkTint.opacity(0.86),
                                Color.black.opacity(0.0)
                            ],
                            center: .topLeading,
                            startRadius: 40,
                            endRadius: orbSize * 0.62
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                    .blur(radius: 54)
                    .offset(x: -width * 0.34, y: -height * 0.28)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                orbAccentTint.opacity(0.28),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: width * 1.15, height: height * 0.42)
                    .blur(radius: 38)
                    .rotationEffect(.degrees(-16))
                    .offset(x: width * 0.18, y: height * 0.12)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.clear,
                        Color.black.opacity(0.84)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.12)
                    .blendMode(.screen)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var orbAccentTint: Color {
        Color(
            hue: themeOrbHue,
            saturation: 0.98,
            brightness: 0.43
        )
    }

    private var orbDarkTint: Color {
        Color(
            hue: themeOrbHue,
            saturation: 0.96,
            brightness: 0.30
        )
    }

    private var themeOrbHue: Double {
        switch theme {
        case .home:
            0.9841
        case .lists:
            0.5982
        case .recipes:
            0.1050
        case .nutrients:
            0.3958
        case .settings:
            0.6000
        case .assistant:
            0.6667
        }
    }
}

extension View {
    @ViewBuilder
    func savoriaModalBorder(theme: PageTheme, cornerRadius: CGFloat = 28) -> some View {
        #if os(iOS)
        overlay {
            SavoriaLuminousBorder(accent: theme.shaderTint, cornerRadius: cornerRadius)
        }
        #else
        self
        #endif
    }
}
