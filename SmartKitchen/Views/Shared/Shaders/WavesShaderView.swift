//
//  WavesShaderView.swift
//  LifeOS
//
//  Shader de ondas animadas - Background "Ondas"
//  Baseado no padrão visual de ondas suaves com gradiente azul
//

import SwiftUI
import SceneKit

// MARK: - Waves Shader Fragment

/// Fragment shader para ondas animadas
/// Cria padrão de ondas suaves com transições de cor
private let wavesFragmentShader = """
#pragma arguments
float iTime;
float2 iResolution;

#pragma body
float2 uv = _surface.diffuseTexcoord;
// Inverter Y para que as ondas fluam de baixo para cima
uv.y = 1.0 - uv.y;

// Ajustar aspect ratio
float aspect = iResolution.x / iResolution.y;
uv.x *= aspect;

// ============ WAVE LAYERS ============
// Múltiplas camadas de ondas com diferentes frequências e velocidades

// Camada 1 - Ondas principais lentas
float wave1 = sin(uv.x * 3.0 + iTime * 0.5) * cos(uv.y * 2.0 + iTime * 0.3) * 0.5;
wave1 += sin(uv.x * 1.5 - iTime * 0.4) * 0.3;

// Camada 2 - Ondas secundárias médias
float wave2 = sin(uv.x * 5.0 + iTime * 0.8) * cos(uv.y * 4.0 - iTime * 0.5) * 0.3;
wave2 += cos(uv.x * 3.0 + uv.y * 2.0 + iTime * 0.6) * 0.2;

// Camada 3 - Ondas de detalhe rápidas
float wave3 = sin(uv.x * 8.0 - iTime * 1.2) * cos(uv.y * 6.0 + iTime * 0.9) * 0.15;
wave3 += sin((uv.x + uv.y) * 4.0 + iTime) * 0.1;

// Combinar todas as ondas
float waves = wave1 + wave2 + wave3;
waves = waves * 0.5 + 0.5; // Normalizar para [0, 1]

// ============ COLOR PALETTE ============
// Gradiente de azul profundo para ciano/turquesa

// Cores base - tons de azul oceânico
float3 deepBlue = float3(0.02, 0.05, 0.15);    // Azul muito escuro
float3 oceanBlue = float3(0.05, 0.2, 0.45);    // Azul oceano
float3 cyan = float3(0.1, 0.5, 0.7);           // Ciano
float3 lightCyan = float3(0.3, 0.7, 0.85);     // Ciano claro

// Criar gradiente baseado na posição Y e nas ondas
float yGradient = pow(uv.y / aspect, 1.5);
float waveInfluence = waves * 0.6;

// Mix de cores baseado em camadas
float3 color = mix(deepBlue, oceanBlue, yGradient);
color = mix(color, cyan, waveInfluence * yGradient);
color = mix(color, lightCyan, pow(waveInfluence, 2.0) * yGradient * 0.5);

// ============ FOAM/HIGHLIGHT EFFECT ============
// Efeito de espuma/brilho nas cristas das ondas
float foam = pow(max(waves - 0.6, 0.0) * 2.5, 2.0);
float3 foamColor = float3(0.6, 0.85, 0.95);
color = mix(color, foamColor, foam * 0.4);

// ============ DEPTH FADE ============
// Fade para preto nas bordas inferiores
float depthFade = smoothstep(0.0, 0.3, uv.y / aspect);
color *= depthFade;

// ============ GRAIN EFFECT ============
// Granulado sutil para textura
float2 grainUV = _surface.diffuseTexcoord * 200.0;
float timeOffset = fract(iTime * 8.0);
float grain = fract(sin(dot(grainUV + timeOffset, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
grain *= 0.08;

// Aplicar grain apenas em áreas mais claras
float brightness = dot(color, float3(0.299, 0.587, 0.114));
grain *= smoothstep(0.0, 0.2, brightness);
color += grain;

// ============ VIGNETTE ============
// Vinheta sutil nas bordas
float2 vignetteUV = _surface.diffuseTexcoord;
float vignette = 1.0 - pow(length(vignetteUV - 0.5) * 1.2, 2.0);
vignette = smoothstep(0.0, 1.0, vignette);
color *= mix(0.7, 1.0, vignette);

// Clamp final
color = clamp(color, float3(0.0), float3(1.0));

_surface.diffuse = float4(color, 1.0);
"""

// MARK: - Waves Scene Renderer

class WavesSceneRenderer: NSObject, SCNSceneRendererDelegate {
    weak var sceneView: SCNView?
    private var startTime: CFTimeInterval = 0
    private var material: SCNMaterial?
    
    // Thread-safe size storage
    private var _cachedSize: CGSize = .zero
    private var _cachedScale: CGFloat = 1.0
    private let sizeLock = NSLock()
    
    var cachedSize: CGSize {
        get { sizeLock.lock(); defer { sizeLock.unlock() }; return _cachedSize }
        set { sizeLock.lock(); defer { sizeLock.unlock() }; _cachedSize = newValue }
    }
    
    var cachedScale: CGFloat {
        get { sizeLock.lock(); defer { sizeLock.unlock() }; return _cachedScale }
        set { sizeLock.lock(); defer { sizeLock.unlock() }; _cachedScale = newValue }
    }
    
    @MainActor
    func setup(in view: SCNView) {
        self.sceneView = view
        self.startTime = CACurrentMediaTime()
        
        // Criar cena
        let scene = SCNScene()
        view.scene = scene
        view.delegate = self
        view.isPlaying = true
        view.loops = true
        view.backgroundColor = .black
        
        // Criar câmera ortográfica
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 1
        cameraNode.position = SCNVector3(0, 0, 1)
        scene.rootNode.addChildNode(cameraNode)
        
        // Criar plano fullscreen
        let plane = SCNPlane(width: 4, height: 4)
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(planeNode)
        
        // Configurar material com shader
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.black
        material.lightingModel = .constant
        material.isDoubleSided = true
        
        // Adicionar shader modifier
        material.shaderModifiers = [
            .surface: wavesFragmentShader
        ]
        
        // Valores iniciais dos uniforms
        material.setValue(Float(0), forKey: "iTime")
        material.setValue(SIMD2<Float>(1, 1), forKey: "iResolution")
        
        plane.materials = [material]
        self.material = material
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let material = material else { return }
        
        let elapsed = Float(CACurrentMediaTime() - startTime)
        material.setValue(elapsed, forKey: "iTime")
        
        // Use cached size/scale
        let size = cachedSize
        let scale = cachedScale
        
        if size.width > 0 && size.height > 0 {
            material.setValue(
                SIMD2<Float>(Float(size.width * scale), Float(size.height * scale)),
                forKey: "iResolution"
            )
        }
    }
    
    func updateGeometry(size: CGSize, scale: CGFloat) {
        self.cachedSize = size
        self.cachedScale = scale
    }
}

// MARK: - Platform View Wrapper

#if os(iOS)
struct WavesSceneView: UIViewRepresentable {
    func makeCoordinator() -> WavesSceneRenderer { WavesSceneRenderer() }
    func makeUIView(context: Context) -> SCNView { createView(context: context) }
    func updateUIView(_ uiView: SCNView, context: Context) {
        let scale = uiView.displayScale
        context.coordinator.updateGeometry(size: uiView.bounds.size, scale: scale)
    }
}
#else
struct WavesSceneView: NSViewRepresentable {
    func makeCoordinator() -> WavesSceneRenderer { WavesSceneRenderer() }
    func makeNSView(context: Context) -> SCNView { createView(context: context) }
    func updateNSView(_ nsView: SCNView, context: Context) {
        let scale = nsView.displayScale
        context.coordinator.updateGeometry(size: nsView.bounds.size, scale: scale)
    }
}
#endif

extension WavesSceneView {
    func createView(context: Context) -> SCNView {
        let scnView = NonFocusableSCNView()
        scnView.antialiasingMode = .none
        scnView.preferredFramesPerSecond = 20
        context.coordinator.setup(in: scnView)
        let scale = scnView.displayScale
        context.coordinator.updateGeometry(size: scnView.bounds.size, scale: scale)
        return scnView
    }
}

// MARK: - Public SwiftUI View

/// View que renderiza o shader de ondas animadas
/// Background "Ondas" - visual oceânico com ondas suaves
struct WavesShaderView: View {
    var progress: CGFloat
    
    init(progress: CGFloat = 1.0) {
        self.progress = progress
    }
    
    var body: some View {
        ZStack {
            // Shader de ondas
            WavesSceneView()
                .ignoresSafeArea()
            
            // Overlay effects sutis
            GeometryReader { geometry in
                ZStack {
                    // Reflexo de luz suave no topo
                    Ellipse()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.4
                            )
                        )
                        .frame(width: geometry.size.width * 0.8, height: geometry.size.height * 0.3)
                        .position(
                            x: geometry.size.width * 0.5,
                            y: geometry.size.height * 0.15
                        )
                }
            }
        }
        .opacity(progress)
    }
}

// MARK: - Preview

#Preview("Waves Shader") {
    ZStack {
        WavesShaderView(progress: 1.0)
        
        VStack {
            Text("Ondas")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Animated Ocean Waves")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
