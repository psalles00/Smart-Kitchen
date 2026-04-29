//
//  TexturedGradientView.swift
//  LifeOS
//
//  Textured Gradient Background with animated noise/grain effect and fluid movement
//  Inspired by: https://www.reddit.com/r/SwiftUI/comments/1e24wzk/textured_gradient/
//

import SwiftUI
import SceneKit

// MARK: - Animated Textured Gradient Fragment Shader

/// Fragment shader - mostly black with small color accents, unique shapes per preset
private let texturedGradientFragmentShader = """
#pragma arguments
float iTime;
float3 color1;
float3 color2;
float3 color3;
float grainIntensity;
float shapeType;

#pragma body
float2 uv = _surface.diffuseTexcoord;
// Flip vertically - effects appear at TOP of screen
uv.y = 1.0 - uv.y;

// ============ ANIMATED MOVEMENT ============
float slowTime = iTime * 0.25;

float2 flowUV = uv;

// Visible wave distortion
flowUV.x += sin(uv.y * 4.0 + slowTime) * 0.08;
flowUV.y += cos(uv.x * 3.5 + slowTime * 0.9) * 0.06;

// Secondary flowing waves
flowUV.x += sin(uv.y * 7.0 - slowTime * 1.4) * 0.04;
flowUV.y += cos(uv.x * 6.0 + slowTime * 1.1) * 0.03;

// ============ ORGANIC METABALL PATTERNS ============
float colorMask = 0.0;
int sType = int(shapeType);

// Helper: Metaball/blob function - creates soft organic shapes
// Returns influence value (higher = more inside the blob)
#define blob(p, center, radius) (radius / (0.001 + length(p - center)))

// Animate blob centers
float2 c1 = float2(0.25 + sin(slowTime * 0.7) * 0.15, 0.85 + cos(slowTime * 0.5) * 0.1);
float2 c2 = float2(0.7 + cos(slowTime * 0.6) * 0.12, 0.8 + sin(slowTime * 0.8) * 0.12);
float2 c3 = float2(0.5 + sin(slowTime * 0.9) * 0.18, 0.9 + cos(slowTime * 0.7) * 0.06);
float2 c4 = float2(0.15 + cos(slowTime * 0.4) * 0.1, 0.75 + sin(slowTime * 0.6) * 0.08);
float2 c5 = float2(0.85 + sin(slowTime * 0.55) * 0.08, 0.88 + cos(slowTime * 0.45) * 0.07);

if (sType == 0) {
    // SUN: Warm radiating organic blobs
    float metaball = 0.0;
    metaball += blob(flowUV, c1, 0.08);
    metaball += blob(flowUV, c2, 0.06);
    metaball += blob(flowUV, c3, 0.1);
    metaball += blob(flowUV, float2(0.4 + sin(slowTime * 0.8) * 0.2, 0.92), 0.12);
    colorMask = smoothstep(0.8, 2.5, metaball);

} else if (sType == 1) {
    // SUNSET: Horizontal flowing layers with soft edges
    float metaball = 0.0;
    metaball += blob(flowUV, float2(0.2 + sin(slowTime * 0.5) * 0.3, 0.9), 0.15);
    metaball += blob(flowUV, float2(0.6 + cos(slowTime * 0.7) * 0.25, 0.85), 0.12);
    metaball += blob(flowUV, float2(0.9 + sin(slowTime * 0.6) * 0.15, 0.88), 0.1);
    metaball += blob(flowUV, float2(0.4 + cos(slowTime * 0.4) * 0.2, 0.78), 0.08);
    colorMask = smoothstep(0.7, 2.0, metaball);

} else if (sType == 2) {
    // OCEAN: Wave-like organic flow
    float metaball = 0.0;
    metaball += blob(flowUV, float2(0.1 + sin(slowTime * 0.8) * 0.25, 0.88 + cos(slowTime * 0.6) * 0.05), 0.12);
    metaball += blob(flowUV, float2(0.4 + cos(slowTime * 0.7) * 0.2, 0.82 + sin(slowTime * 0.5) * 0.06), 0.1);
    metaball += blob(flowUV, float2(0.7 + sin(slowTime * 0.6) * 0.18, 0.86 + cos(slowTime * 0.4) * 0.04), 0.11);
    metaball += blob(flowUV, float2(0.95 + cos(slowTime * 0.9) * 0.1, 0.84), 0.08);
    colorMask = smoothstep(0.75, 2.2, metaball);

} else if (sType == 3) {
    // FOREST: Organic leaf-like clusters
    float metaball = 0.0;
    metaball += blob(flowUV, c1, 0.09);
    metaball += blob(flowUV, c2, 0.07);
    metaball += blob(flowUV, c3, 0.08);
    metaball += blob(flowUV, c4, 0.06);
    metaball += blob(flowUV, c5, 0.05);
    colorMask = smoothstep(0.85, 2.8, metaball);

} else if (sType == 4) {
    // LAVENDER: Soft dreamy blooms
    float metaball = 0.0;
    metaball += blob(flowUV, float2(0.3 + sin(slowTime * 0.4) * 0.2, 0.88), 0.14);
    metaball += blob(flowUV, float2(0.65 + cos(slowTime * 0.5) * 0.15, 0.82), 0.11);
    metaball += blob(flowUV, float2(0.5 + sin(slowTime * 0.6) * 0.18, 0.92), 0.09);
    metaball += blob(flowUV, float2(0.85 + cos(slowTime * 0.3) * 0.1, 0.86), 0.07);
    colorMask = smoothstep(0.8, 2.4, metaball);

} else if (sType == 5) {
    // MIDNIGHT: Sparse glowing orbs
    float metaball = 0.0;
    metaball += blob(flowUV, float2(0.2 + sin(slowTime * 0.3) * 0.08, 0.9), 0.05);
    metaball += blob(flowUV, float2(0.5 + cos(slowTime * 0.4) * 0.12, 0.85), 0.07);
    metaball += blob(flowUV, float2(0.75 + sin(slowTime * 0.35) * 0.1, 0.92), 0.04);
    metaball += blob(flowUV, float2(0.35 + cos(slowTime * 0.5) * 0.15, 0.78), 0.06);
    metaball += blob(flowUV, float2(0.6 + sin(slowTime * 0.25) * 0.2, 0.88), 0.12);
    colorMask = smoothstep(0.6, 2.0, metaball);

} else {
    // AURORA: Flowing ethereal bands
    float metaball = 0.0;
    metaball += blob(flowUV, float2(0.15 + sin(slowTime * 0.6) * 0.25, 0.88), 0.13);
    metaball += blob(flowUV, float2(0.45 + cos(slowTime * 0.7) * 0.2, 0.84), 0.1);
    metaball += blob(flowUV, float2(0.75 + sin(slowTime * 0.5) * 0.18, 0.9), 0.11);
    metaball += blob(flowUV, float2(0.3 + cos(slowTime * 0.8) * 0.15, 0.8), 0.08);
    metaball += blob(flowUV, float2(0.9 + sin(slowTime * 0.4) * 0.08, 0.86), 0.09);
    colorMask = smoothstep(0.7, 2.3, metaball);
}

colorMask = min(colorMask, 1.0);

// ============ COLOR GRADIENT IN SHAPES ============
float shapeGradient = (1.0 - flowUV.y) + sin(flowUV.x * 5.0 + slowTime) * 0.1;
shapeGradient = clamp(shapeGradient, 0.0, 1.0);

float3 shapeColor;
if (shapeGradient < 0.4) {
    float t = shapeGradient / 0.4;
    t = t * t * (3.0 - 2.0 * t);
    shapeColor = mix(color1, color2, t);
} else {
    float t = (shapeGradient - 0.4) / 0.6;
    t = t * t * (3.0 - 2.0 * t);
    shapeColor = mix(color2, color3, t);
}

// ============ MOSTLY BLACK WITH COLOR ACCENTS ============
float3 baseColor = float3(0.0);
float3 coloredArea = shapeColor * colorMask * 0.75;
float3 gradientColor = baseColor + coloredArea;

// ============ HEAVY GRAIN EFFECT ============
float2 grainUV = uv * 350.0;
float timeOffset = fract(iTime * 10.0);

float grain1 = fract(sin(dot(grainUV + timeOffset, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
float grain2 = fract(sin(dot(grainUV * 0.5 + timeOffset * 1.7, float2(39.346, 11.135))) * 43758.5453) - 0.5;
float grain3 = fract(sin(dot(grainUV * 0.25 + timeOffset * 0.8, float2(73.156, 52.235))) * 43758.5453) - 0.5;

float totalGrain = grain1 * 0.5 + grain2 * 0.35 + grain3 * 0.15;
// Only apply grain to colored areas - keep blacks truly black
totalGrain *= grainIntensity * colorMask;

// ============ FINAL OUTPUT ============
float3 finalColor = gradientColor + totalGrain;
// Ensure blacks stay black - clamp minimum to true black
finalColor = max(finalColor, float3(0.0));
finalColor = min(finalColor, float3(1.0));

_surface.diffuse = float4(finalColor, 1.0);
"""

/// Vertex shader with visible wave distortion
private let texturedGradientVertexShader = """
#pragma arguments
float iTime;

#pragma body
// Visible vertex wave distortion
float slowTime = iTime * 0.12;
float waveY = sin(_geometry.position.x * 5.0 + slowTime) * 0.04;
float waveX = cos(_geometry.position.y * 4.0 + slowTime * 0.9) * 0.03;

_geometry.position.y += waveY;
_geometry.position.x += waveX;
"""

// MARK: - Scene Renderer

class TexturedGradientSceneRenderer: NSObject, SCNSceneRendererDelegate {
    weak var sceneView: SCNView?
    private var startTime: CFTimeInterval = 0
    private var material: SCNMaterial?

    // Colors (will be set from preset)
    var color1 = SCNVector3(0.0, 0.0, 0.0)
    var color2 = SCNVector3(0.0, 0.0, 0.0)
    var color3 = SCNVector3(0.0, 0.0, 0.0)
    var grainIntensity: Float = 0.25
    var shapeType: Float = 0.0

    @MainActor
    func setup(in view: SCNView) {
        self.sceneView = view
        self.startTime = CACurrentMediaTime()

        let scene = SCNScene()
        view.scene = scene
        view.delegate = self
        view.isPlaying = true
        view.loops = true
        view.backgroundColor = .black

        // Orthographic camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 1
        cameraNode.position = SCNVector3(0, 0, 1)
        scene.rootNode.addChildNode(cameraNode)

        // Plane with subdivisions for vertex distortion
        let plane = SCNPlane(width: 4, height: 4)
        plane.widthSegmentCount = 32
        plane.heightSegmentCount = 32
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(planeNode)

        // Material with shaders
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.black
        material.lightingModel = .constant
        material.isDoubleSided = true

        material.shaderModifiers = [
            .geometry: texturedGradientVertexShader,
            .surface: texturedGradientFragmentShader
        ]

        // Initial uniform values
        material.setValue(Float(0), forKey: "iTime")
        material.setValue(color1, forKey: "color1")
        material.setValue(color2, forKey: "color2")
        material.setValue(color3, forKey: "color3")
        material.setValue(grainIntensity, forKey: "grainIntensity")
        material.setValue(shapeType, forKey: "shapeType")

        plane.materials = [material]
        self.material = material
    }

    func updateUniforms() {
        guard let material = material else { return }
        material.setValue(color1, forKey: "color1")
        material.setValue(color2, forKey: "color2")
        material.setValue(color3, forKey: "color3")
        material.setValue(grainIntensity, forKey: "grainIntensity")
        material.setValue(shapeType, forKey: "shapeType")
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let material = material else { return }
        let elapsed = Float(CACurrentMediaTime() - startTime)
        material.setValue(elapsed, forKey: "iTime")
    }
}

// MARK: - Platform View Wrapper

#if os(iOS)
struct TexturedGradientSceneView: UIViewRepresentable {
    var color1: Color
    var color2: Color
    var color3: Color
    var grainIntensity: Float
    var shapeType: Float
    func makeCoordinator() -> TexturedGradientSceneRenderer { TexturedGradientSceneRenderer() }
    func makeUIView(context: Context) -> SCNView { createView(context: context) }
    func updateUIView(_ uiView: SCNView, context: Context) { updateCoordinator(context.coordinator) }
}
#else
struct TexturedGradientSceneView: NSViewRepresentable {
    var color1: Color
    var color2: Color
    var color3: Color
    var grainIntensity: Float
    var shapeType: Float
    func makeCoordinator() -> TexturedGradientSceneRenderer { TexturedGradientSceneRenderer() }
    func makeNSView(context: Context) -> SCNView { createView(context: context) }
    func updateNSView(_ nsView: SCNView, context: Context) { updateCoordinator(context.coordinator) }
}
#endif

extension TexturedGradientSceneView {
    func createView(context: Context) -> SCNView {
        let scnView = NonFocusableSCNView()
        scnView.antialiasingMode = .none
        scnView.preferredFramesPerSecond = 20
        context.coordinator.setup(in: scnView)
        updateCoordinator(context.coordinator)
        return scnView
    }

    private func updateCoordinator(_ coordinator: TexturedGradientSceneRenderer) {
        coordinator.color1 = colorToVector(color1)
        coordinator.color2 = colorToVector(color2)
        coordinator.color3 = colorToVector(color3)
        coordinator.grainIntensity = grainIntensity
        coordinator.shapeType = shapeType
        coordinator.updateUniforms()
    }

    private func colorToVector(_ color: Color) -> SCNVector3 {
        let platformColor = PlatformColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        let convertedColor = platformColor.usingColorSpace(.deviceRGB) ?? platformColor
        convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        platformColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return SCNVector3(Float(r), Float(g), Float(b))
    }
}

// MARK: - Public SwiftUI View

/// Textured gradient background with animated grain effect and fluid movement
struct TexturedGradientView: View {
    var preset: TexturedGradientPreset
    var progress: CGFloat

    init(preset: TexturedGradientPreset = .sun, progress: CGFloat = 1.0) {
        self.preset = preset
        self.progress = progress
    }

    var body: some View {
        if progress > 0 {
            TexturedGradientSceneView(
                color1: preset.color1,
                color2: preset.color2,
                color3: preset.color3,
                grainIntensity: preset.grainIntensity,
                shapeType: preset.shapeType
            )
            .ignoresSafeArea()
            .opacity(progress)
        }
    }
}

// MARK: - Presets (Vibrant colors on mostly black background)

enum TexturedGradientPreset: String, CaseIterable, Identifiable, Codable {
    case sun = "sun"
    case sunset = "sunset"
    case ocean = "ocean"
    case forest = "forest"
    case lavender = "lavender"
    case midnight = "midnight"
    case aurora = "aurora"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sun: return String(localized: "Sun")
        case .sunset: return String(localized: "Sunset")
        case .ocean: return String(localized: "Ocean")
        case .forest: return String(localized: "Forest")
        case .lavender: return String(localized: "Lavender")
        case .midnight: return String(localized: "Midnight")
        case .aurora: return String(localized: "Aurora")
        }
    }

    // Color 1: Brightest accent (vibrant since background is mostly black)
    var color1: Color {
        switch self {
        case .sun: return Color(red: 1.0, green: 0.6, blue: 0.1)         // Bright yellow-orange (light)
        case .sunset: return Color(red: 0.9, green: 0.35, blue: 0.15)    // Vibrant coral/orange
        case .ocean: return Color(red: 0.15, green: 0.5, blue: 0.85)     // Bright blue
        case .forest: return Color(red: 0.15, green: 0.55, blue: 0.2)    // Vibrant green
        case .lavender: return Color(red: 0.55, green: 0.35, blue: 0.75) // Bright purple
        case .midnight: return Color(red: 0.2, green: 0.25, blue: 0.45)  // Deep blue
        case .aurora: return Color(red: 0.1, green: 0.75, blue: 0.55)    // Bright teal
        }
    }

    // Color 2: Middle tone
    var color2: Color {
        switch self {
        case .sun: return Color(red: 0.95, green: 0.35, blue: 0.05)       // Saturated orange (mid)
        case .sunset: return Color(red: 0.7, green: 0.15, blue: 0.1)     // Deep red
        case .ocean: return Color(red: 0.08, green: 0.3, blue: 0.6)      // Medium blue
        case .forest: return Color(red: 0.08, green: 0.35, blue: 0.12)   // Medium green
        case .lavender: return Color(red: 0.35, green: 0.2, blue: 0.55)  // Medium purple
        case .midnight: return Color(red: 0.1, green: 0.12, blue: 0.25)  // Dark blue
        case .aurora: return Color(red: 0.05, green: 0.45, blue: 0.5)    // Medium cyan
        }
    }

    // Color 3: Darker accent (still visible but dark)
    var color3: Color {
        switch self {
        case .sun: return Color(red: 0.7, green: 0.15, blue: 0.0)        // Deep reddish-orange (dark)
        case .sunset: return Color(red: 0.4, green: 0.05, blue: 0.1)     // Dark red
        case .ocean: return Color(red: 0.03, green: 0.12, blue: 0.3)     // Dark blue
        case .forest: return Color(red: 0.03, green: 0.18, blue: 0.06)   // Dark green
        case .lavender: return Color(red: 0.18, green: 0.1, blue: 0.3)   // Dark purple
        case .midnight: return Color(red: 0.04, green: 0.05, blue: 0.12) // Very dark blue
        case .aurora: return Color(red: 0.02, green: 0.2, blue: 0.25)    // Dark teal
        }
    }

    // Strong grain for all presets
    var grainIntensity: Float {
        switch self {
        case .sun: return 0.22
        case .sunset: return 0.20
        case .ocean: return 0.18
        case .forest: return 0.18
        case .lavender: return 0.16
        case .midnight: return 0.14
        case .aurora: return 0.20
        }
    }

    // Shape type for unique patterns per preset
    // 0=Sun, 1=Sunset, 2=Ocean, 3=Forest, 4=Lavender, 5=Midnight, 6=Aurora
    var shapeType: Float {
        switch self {
        case .sun: return 0.0
        case .sunset: return 1.0
        case .ocean: return 2.0
        case .forest: return 3.0
        case .lavender: return 4.0
        case .midnight: return 5.0
        case .aurora: return 6.0
        }
    }
}

// MARK: - Preview

#Preview("Textured Gradient - Sun") {
    ZStack {
        TexturedGradientView(preset: .sun, progress: 1.0)
            .scaleEffect(y: -1)

        VStack {
            Text("Sun")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Animated Textured Gradient")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

#Preview("All Presets") {
    ScrollView(.horizontal) {
        HStack(spacing: 20) {
            ForEach(TexturedGradientPreset.allCases) { preset in
                VStack {
                    TexturedGradientView(preset: preset, progress: 1.0)
                        .scaleEffect(y: -1)
                        .frame(width: 150, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(preset.displayName)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}
