//
//  MeshGradientShaderView.swift
//  LifeOS
//
//  Shader de gradiente mesh animado - Exclusivo para página To-Do
//  Conversão fiel linha por linha do React/Three.js
//

import SwiftUI
import SceneKit

// MARK: - Mesh Gradient Shader Fragment

/// Fragment shader convertido linha por linha do original React/Three.js
/// Cria padrão de ruído animado com efeito de brilho
private let meshGradientFragmentShader = """
#pragma arguments
float iTime;
float intensity;
float3 color1;
float3 color2;

#pragma body
float2 uv = _surface.diffuseTexcoord;
// Efeito colorido destacado na parte superior
uv.y = 1.0 - uv.y;

// Create animated noise pattern - linha por linha do original
float noise = sin(uv.x * 20.0 + iTime) * cos(uv.y * 15.0 + iTime * 0.8);
noise += sin(uv.x * 35.0 - iTime * 2.0) * cos(uv.y * 25.0 + iTime * 1.2) * 0.5;

// ============ GRAIN EFFECT (granulado) ============
// Versão otimizada para GPUs móveis - hash simples sem sin() para evitar problemas de precisão
float2 grainUV = fract(uv * 50.0 + fract(iTime * 0.05) * 10.0);
float grain = fract(grainUV.x * 17.0 + grainUV.y * 13.0) * 2.0 - 1.0;
grain *= 0.15;  // Intensidade do granulado

// Mix colors based on noise - MAIS áreas pretas, MENOS verdes
// Usando pow para criar transição mais abrupta - preto domina
float mixFactor = pow(noise * 0.5 + 0.5, 3.0);  // Exponencial para menos verde
float3 color = mix(color1, color2, mixFactor * 0.4);  // 0.4 limita o máximo de verde
// Adicionar mais preto nas áreas de highlight
color = mix(color, float3(0.0), pow(abs(noise), 1.5) * intensity * 0.6);

// Aplicar grain ao color
color += grain;
color = max(color, float3(0.0));  // Clamp para não ter valores negativos

// Add glow effect - distância do centro
float glow = 1.0 - length(uv - 0.5) * 2.0;
glow = pow(max(glow, 0.0), 2.0);

// Output final com glow e grain
_surface.diffuse = float4(color * glow, glow * 0.95);
"""

/// Vertex shader com distorção de ondas - convertido do original
private let meshGradientVertexShader = """
#pragma arguments
float iTime;
float intensity;

#pragma body
// Wave distortion - linha por linha do original
float waveY = sin(_geometry.position.x * 10.0 + iTime) * 0.1 * intensity;
float waveX = cos(_geometry.position.y * 8.0 + iTime * 1.5) * 0.05 * intensity;

_geometry.position.y += waveY;
_geometry.position.x += waveX;
"""

// MARK: - Mesh Gradient Renderer

class MeshGradientSceneRenderer: NSObject, SCNSceneRendererDelegate {
    weak var sceneView: SCNView?
    private var startTime: CFTimeInterval = 0
    private var material: SCNMaterial?
    
    // Cores do tema To-Do - Preto puro nas escuras, verde vibrante nas claras
    private let color1 = SCNVector3(0.0, 0.0, 0.0)      // Preto puro #000000
    private let color2 = SCNVector3(0.12, 0.65, 0.25)   // Verde claro e vibrante
    
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
        
        // Criar plano com subdivisões para distorção de vértices
        let plane = SCNPlane(width: 4, height: 4)
        plane.widthSegmentCount = 32  // args={[2, 2, 32, 32]} do original
        plane.heightSegmentCount = 32
        
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(planeNode)
        
        // Configurar material com shaders
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.black
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.blendMode = .alpha
        
        // Adicionar shader modifiers
        material.shaderModifiers = [
            .geometry: meshGradientVertexShader,
            .surface: meshGradientFragmentShader
        ]
        
        // Valores iniciais dos uniforms
        material.setValue(Float(0), forKey: "iTime")
        material.setValue(Float(1.0), forKey: "intensity")
        material.setValue(color1, forKey: "color1")
        material.setValue(color2, forKey: "color2")
        
        plane.materials = [material]
        self.material = material
    }
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let material = material else { return }
        
        let elapsed = Float(CACurrentMediaTime() - startTime)
        material.setValue(elapsed, forKey: "iTime")
        
        // Intensity pulsante como no original: 1.0 + Math.sin(elapsedTime * 2) * 0.3
        let intensity = 1.0 + sin(elapsed * 2.0) * 0.3
        material.setValue(intensity, forKey: "intensity")
    }
}

// MARK: - Platform View Wrapper

#if os(iOS)
struct MeshGradientSceneView: UIViewRepresentable {
    func makeCoordinator() -> MeshGradientSceneRenderer { MeshGradientSceneRenderer() }
    func makeUIView(context: Context) -> SCNView { createView(context: context) }
    func updateUIView(_ uiView: SCNView, context: Context) { }
}
#else
struct MeshGradientSceneView: NSViewRepresentable {
    func makeCoordinator() -> MeshGradientSceneRenderer { MeshGradientSceneRenderer() }
    func makeNSView(context: Context) -> SCNView { createView(context: context) }
    func updateNSView(_ nsView: SCNView, context: Context) { }
}
#endif

extension MeshGradientSceneView {
    func createView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.antialiasingMode = .none
        scnView.preferredFramesPerSecond = 20
        context.coordinator.setup(in: scnView)
        return scnView
    }
}

// MARK: - Public SwiftUI View

/// View que renderiza o shader de gradiente mesh animado
/// Exclusivo para a página To-Do
struct MeshGradientShaderView: View {
    var progress: CGFloat
    
    init(progress: CGFloat = 1.0) {
        self.progress = progress
    }
    
    var body: some View {
        // Shader só aparece quando progress > 0 (ao arrastar)
        if progress > 0 {
            ZStack {
                // Shader de gradiente mesh - fundo escuro integrado
                MeshGradientSceneView()
                    .ignoresSafeArea()
                
                // Overlay effects sutis - convertido do demo.tsx
                GeometryReader { geometry in
                    ZStack {
                        // Primeiro círculo pulsante - muito sutil
                        Circle()
                            .fill(Color.gray.opacity(0.03))
                            .frame(width: 128, height: 128)
                            .blur(radius: 48)
                            .position(
                                x: geometry.size.width * 0.33,
                                y: geometry.size.height * 0.25
                            )
                        
                        // Segundo círculo pulsante
                        Circle()
                            .fill(Color.white.opacity(0.01))
                            .frame(width: 96, height: 96)
                            .blur(radius: 32)
                            .position(
                                x: geometry.size.width * 0.75,
                                y: geometry.size.height * 0.67
                            )
                    }
                }
            }
            .opacity(progress)
        }
    }
}

// MARK: - Preview

#Preview("Mesh Gradient Shader - To-Do Theme") {
    ZStack {
        MeshGradientShaderView(progress: 1.0)
        
        VStack {
            Text("To-Do Shader")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Mesh Gradient with Wave Distortion")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}
