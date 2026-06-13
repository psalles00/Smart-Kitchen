import SwiftUI
import SceneKit

// MARK: - CPPN Shader Fragment (GLSL -> Metal Shading Language via SceneKit)

private let cppnFragmentShader = """
#pragma arguments
float iTime;
float2 iResolution;
float3 tintColor;
float tintStrength;
float3 tintColor2;
float tint2Strength;

#pragma body
float2 uv = _surface.diffuseTexcoord * 2.0 - 1.0;
uv.x *= -1.0;

float4 buf0, buf1, buf2, buf3, buf4, buf5, buf6, buf7;

float in0 = 0.1 * sin(0.3 * iTime);
float in1 = 0.1 * sin(0.69 * iTime);
float in2 = 0.1 * sin(0.44 * iTime);

#define sigmoid(x) (1.0 / (1.0 + exp(-(x))))

// ===================== LAYER 1 =====================
buf6 = float4(uv.x, uv.y, 0.3948333106474662 + in0, 0.36 + in1);
buf7 = float4(0.14 + in2, sqrt(uv.x * uv.x + uv.y * uv.y), 0.0, 0.0);

// ===================== LAYER 2 =====================
float4x4 m2_0 = float4x4(
    float4(6.5404263, -3.6126034, 0.7590882, -1.13613),
    float4(2.4582713, 3.1660357, 1.2219609, 0.06276096),
    float4(-5.478085, -6.159632, 1.8701609, -4.7742867),
    float4(6.039214, -5.542865, -0.90925294, 3.251348)
);
float4x4 m2_1 = float4x4(
    float4(0.8473259, -5.722911, 3.975766, 1.6522468),
    float4(-0.24321538, 0.5839259, -1.7661959, -5.350116),
    float4(0.0, 0.0, 0.0, 0.0),
    float4(0.0, 0.0, 0.0, 0.0)
);
float4 b2_0 = float4(0.21808943, 1.1243913, -1.7969975, 5.0294676);
buf0 = m2_0 * buf6 + m2_1 * buf7 + b2_0;

float4x4 m2_2 = float4x4(
    float4(-3.3522482, -6.0612736, 0.55641043, -4.4719114),
    float4(0.8631464, 1.7432913, 5.643898, 1.6106541),
    float4(2.4941394, -3.5012043, 1.7184316, 6.357333),
    float4(3.310376, 8.209261, 1.1355612, -1.165539)
);
float4x4 m2_3 = float4x4(
    float4(5.24046, -13.034365, 0.009859298, 15.870829),
    float4(2.987511, 3.129433, -0.89023495, -1.6822904),
    float4(0.0, 0.0, 0.0, 0.0),
    float4(0.0, 0.0, 0.0, 0.0)
);
float4 b2_1 = float4(-5.9457836, -6.573602, -0.8812491, 1.5436668);
buf1 = m2_2 * buf6 + m2_3 * buf7 + b2_1;

buf0 = sigmoid(buf0);
buf1 = sigmoid(buf1);

// ===================== LAYER 3 =====================
float4x4 m3_0 = float4x4(
    float4(-15.219568, 8.095543, -2.429353, -1.9381982),
    float4(-5.951362, 4.3115187, 2.6393783, 1.274315),
    float4(-7.3145227, 6.7297835, 5.2473326, 5.9411426),
    float4(5.0796127, 8.979051, -1.7278991, -1.158976)
);
float4x4 m3_1 = float4x4(
    float4(-11.967154, -11.608155, 6.1486754, 11.237008),
    float4(2.124141, -6.263192, -1.7050359, -0.7021966),
    float4(0.0, 0.0, 0.0, 0.0),
    float4(0.0, 0.0, 0.0, 0.0)
);
float4 b3_0 = float4(-4.17164, -3.2281182, -4.576417, -3.6401186);
buf2 = m3_0 * buf6 + m3_1 * buf7 + b3_0;

float4x4 m3_2 = float4x4(
    float4(3.1832156, -13.738922, 1.879223, 3.233465),
    float4(0.64300746, 12.768129, 1.9141049, 0.50990224),
    float4(-0.049295485, 4.4807224, 1.4733979, 1.801449),
    float4(5.0039253, 13.000481, 3.3991797, -4.5561905)
);
float4x4 m3_3 = float4x4(
    float4(-0.1285731, 7.720628, -3.1425676, 4.742367),
    float4(0.6393625, 3.714393, -0.8108378, -0.39174938),
    float4(0.0, 0.0, 0.0, 0.0),
    float4(0.0, 0.0, 0.0, 0.0)
);
float4 b3_1 = float4(-1.1811101, -21.621881, 0.7851888, 1.2329718);
buf3 = m3_2 * buf6 + m3_3 * buf7 + b3_1;

buf2 = sigmoid(buf2);
buf3 = sigmoid(buf3);

// ===================== LAYER 5 & 6 =====================
float4x4 m5_0 = float4x4(
    float4(5.214916, -7.183024, 2.7228765, 2.6592617),
    float4(-5.601878, -25.3591, 4.067988, 0.4602802),
    float4(-10.57759, 24.286327, 21.102104, 37.546658),
    float4(4.3024497, -1.9625226, 2.3458803, -1.372816)
);
float4x4 m5_1 = float4x4(
    float4(-17.6526, -10.507558, 2.2587414, 12.462782),
    float4(6.265566, -502.75443, -12.642513, 0.9112289),
    float4(-10.983244, 20.741234, -9.701768, -0.7635988),
    float4(5.383626, 1.4819539, -4.1911616, -4.8444734)
);
float4x4 m5_2 = float4x4(
    float4(12.785233, -16.345072, -0.39901125, 1.7955981),
    float4(-30.48365, -1.8345358, 1.4542528, -1.1118771),
    float4(19.872723, -7.337935, -42.941723, -98.52709),
    float4(8.337645, -2.7312303, -2.2927687, -36.142323)
);
float4x4 m5_3 = float4x4(
    float4(-16.298317, 3.5471997, -0.44300047, -9.444417),
    float4(57.5077, -35.609753, 16.163465, -4.1534753),
    float4(-0.07470326, -3.8656476, -7.0901804, 3.1523974),
    float4(-12.559385, -7.077619, 1.490437, -0.8211543)
);
float4 b5_0 = float4(-7.67914, 15.927437, 1.3207729, -1.6686112);
buf4 = m5_0 * buf0 + m5_1 * buf1 + m5_2 * buf2 + m5_3 * buf3 + b5_0;

float4x4 m6_0 = float4x4(
    float4(-1.4109162, -0.372762, -3.770383, -21.367174),
    float4(-6.2103205, -9.35908, 0.92529047, 8.82561),
    float4(11.460242, -22.348068, 13.625772, -18.693201),
    float4(-0.3429052, -3.9905605, -2.4626114, -0.45033523)
);
float4x4 m6_1 = float4x4(
    float4(7.3481627, -4.3661838, -6.3037653, -3.868115),
    float4(1.5462853, 6.5488915, 1.9701879, -0.58291394),
    float4(6.5858274, -2.2180402, 3.7127688, -1.3730392),
    float4(-5.7973905, 10.134961, -2.3395722, -5.965605)
);
float4x4 m6_2 = float4x4(
    float4(-2.5132585, -6.6685553, -1.4029363, -0.16285264),
    float4(-0.37908727, 0.53738135, 4.389061, -1.3024765),
    float4(-0.70647055, 2.0111287, -5.1659346, -3.728635),
    float4(-13.562562, 10.487719, -0.9173751, -2.6487076)
);
float4x4 m6_3 = float4x4(
    float4(-8.645013, 6.5546675, -6.3944063, -5.5933375),
    float4(-0.57783127, -1.077275, 36.91025, 5.736769),
    float4(14.283112, 3.7146652, 7.1452246, -4.5958776),
    float4(2.7192075, 3.6021907, -4.366337, -2.3653464)
);
float4 b6_0 = float4(-5.9000807, -4.329569, 1.2427121, 8.59503);
buf5 = m6_0 * buf0 + m6_1 * buf1 + m6_2 * buf2 + m6_3 * buf3 + b6_0;

buf4 = sigmoid(buf4);
buf5 = sigmoid(buf5);

// ===================== LAYER 7 & 8 =====================
float4x4 m7_0 = float4x4(
    float4(-1.61102, 0.7970257, 1.4675229, 0.20917463),
    float4(-28.793737, -7.1390953, 1.5025433, 4.656581),
    float4(-10.94861, 39.66238, 0.74318546, -10.095605),
    float4(-0.7229728, -1.5483948, 0.7301322, 2.1687684)
);
float4x4 m7_1 = float4x4(
    float4(3.2547753, 21.489103, -1.0194173, -3.3100595),
    float4(-3.7316632, -3.3792162, -7.223193, -0.23685838),
    float4(13.1804495, 0.7916005, 5.338587, 5.687114),
    float4(-4.167605, -17.798311, -6.815736, -1.6451967)
);
float4x4 m7_2 = float4x4(
    float4(0.604885, -7.800309, -7.213122, -2.741014),
    float4(-3.522382, -0.12359311, -0.5258442, 0.43852118),
    float4(9.6752825, -22.853785, 2.062431, 0.099892326),
    float4(-4.3196306, -17.730087, 2.5184598, 5.30267)
);
float4x4 m7_3 = float4x4(
    float4(-6.545563, -15.790176, -6.0438633, -5.415399),
    float4(-43.591583, 28.551912, -16.00161, 18.84728),
    float4(4.212382, 8.394307, 3.0958717, 8.657522),
    float4(-5.0237565, -4.450633, -4.4768, -5.5010443)
);
float4x4 m7_4 = float4x4(
    float4(1.6985557, -67.05806, 6.897715, 1.9004834),
    float4(1.8680354, 2.3915145, 2.5231109, 4.081538),
    float4(11.158006, 1.7294737, 2.0738268, 7.386411),
    float4(-4.256034, -306.24686, 8.258898, -17.132736)
);
float4x4 m7_5 = float4x4(
    float4(1.6889864, -4.5852966, 3.8534803, -6.3482175),
    float4(1.3543309, -1.2640043, 9.932754, 2.9079645),
    float4(-5.2770967, 0.07150358, -0.13962056, 3.3269649),
    float4(28.34703, -4.918278, 6.1044083, 4.085355)
);
float4 b7_0 = float4(6.6818056, 12.522166, -3.7075126, -4.104386);
buf6 = m7_0 * buf0 + m7_1 * buf1 + m7_2 * buf2 + m7_3 * buf3 + m7_4 * buf4 + m7_5 * buf5 + b7_0;

float4x4 m8_0 = float4x4(
    float4(-8.265602, -4.7027016, 5.098234, 0.7509808),
    float4(8.6507845, -17.15949, 16.51939, -8.884479),
    float4(-4.036479, -2.3946867, -2.6055532, -1.9866527),
    float4(-2.2167742, -1.8135649, -5.9759874, 4.8846445)
);
float4x4 m8_1 = float4x4(
    float4(6.7790847, 3.5076547, -2.8191125, -2.7028968),
    float4(-5.743024, -0.27844876, 1.4958696, -5.0517144),
    float4(13.122226, 15.735168, -2.9397483, -4.101023),
    float4(-14.375265, -5.030483, -6.2599335, 2.9848232)
);
float4x4 m8_2 = float4x4(
    float4(4.0950394, -0.94011575, -5.674733, 4.755022),
    float4(4.3809423, 4.8310084, 1.7425908, -3.437416),
    float4(2.117492, 0.16342592, -104.56341, 16.949184),
    float4(-5.22543, -2.994248, 3.8350096, -1.9364246)
);
float4x4 m8_3 = float4x4(
    float4(-5.900337, 1.7946124, -13.604192, -3.8060522),
    float4(6.6583457, 31.911177, 25.164474, 91.81147),
    float4(11.840538, 4.1503043, -0.7314397, 6.768467),
    float4(-6.3967767, 4.034772, 6.1714606, -0.32874924)
);
float4x4 m8_4 = float4x4(
    float4(3.4992442, -196.91893, -8.923708, 2.8142626),
    float4(3.4806502, -3.1846354, 5.1725626, 5.1804223),
    float4(-2.4009497, 15.585794, 1.2863957, 2.0252278),
    float4(-71.25271, -62.441242, -8.138444, 0.50670296)
);
float4x4 m8_5 = float4x4(
    float4(-12.291733, -11.176166, -7.3474145, 4.390294),
    float4(10.805477, 5.6337385, -0.9385842, -4.7348723),
    float4(-12.869276, -7.039391, 5.3029537, 7.5436664),
    float4(1.4593618, 8.91898, 3.5101583, 5.840625)
);
float4 b8_0 = float4(2.2415268, -6.705987, -0.98861027, -2.117676);
buf7 = m8_0 * buf0 + m8_1 * buf1 + m8_2 * buf2 + m8_3 * buf3 + m8_4 * buf4 + m8_5 * buf5 + b8_0;

buf6 = sigmoid(buf6);
buf7 = sigmoid(buf7);

// ===================== LAYER 9 (OUTPUT) =====================
float4x4 m9_0 = float4x4(
    float4(1.6794263, 1.3817469, 2.9625452, 0.0),
    float4(-1.8834411, -1.4806935, -3.5924516, 0.0),
    float4(-1.3279216, -1.0918057, -2.3124623, 0.0),
    float4(0.2662234, 0.23235129, 0.44178495, 0.0)
);
float4x4 m9_1 = float4x4(
    float4(-0.6299101, -0.5945583, -0.9125601, 0.0),
    float4(0.17828953, 0.18300213, 0.18182953, 0.0),
    float4(-2.96544, -2.5819945, -4.9001055, 0.0),
    float4(1.4195864, 1.1868085, 2.5176322, 0.0)
);
float4x4 m9_2 = float4x4(
    float4(-1.2584374, -1.0552157, -2.1688404, 0.0),
    float4(-0.7200217, -0.52666044, -1.438251, 0.0),
    float4(0.15345335, 0.15196142, 0.272854, 0.0),
    float4(0.945728, 0.8861938, 1.2766753, 0.0)
);
float4x4 m9_3 = float4x4(
    float4(-2.4218085, -1.968602, -4.35166, 0.0),
    float4(-22.683098, -18.0544, -41.954372, 0.0),
    float4(0.63792, 0.5470648, 1.1078634, 0.0),
    float4(-1.5489894, -1.3075932, -2.6444845, 0.0)
);
float4x4 m9_4 = float4x4(
    float4(-0.49252132, -0.39877754, -0.91366625, 0.0),
    float4(0.95609266, 0.7923952, 1.640221, 0.0),
    float4(0.30616966, 0.15693925, 0.8639857, 0.0),
    float4(1.1825981, 0.94504964, 2.176963, 0.0)
);
float4x4 m9_5 = float4x4(
    float4(0.35446745, 0.3293795, 0.59547555, 0.0),
    float4(-0.58784515, -0.48177817, -1.0614829, 0.0),
    float4(2.5271258, 1.9991658, 4.6846647, 0.0),
    float4(0.13042648, 0.08864098, 0.30187556, 0.0)
);
float4x4 m9_6 = float4x4(
    float4(-1.7718065, -1.4033192, -3.3355875, 0.0),
    float4(3.1664357, 2.638297, 5.378702, 0.0),
    float4(-3.1724713, -2.6107926, -5.549295, 0.0),
    float4(-2.851368, -2.249092, -5.3013067, 0.0)
);
float4x4 m9_7 = float4x4(
    float4(1.5203838, 1.2212278, 2.8404984, 0.0),
    float4(1.5210563, 1.2651345, 2.683903, 0.0),
    float4(2.9789467, 2.4364579, 5.2347264, 0.0),
    float4(2.2270417, 1.8825914, 3.8028636, 0.0)
);
float4 b9_0 = float4(-1.5468478, -3.6171484, 0.24762098, 0.0);

buf0 = m9_0 * buf0 + m9_1 * buf1 + m9_2 * buf2 + m9_3 * buf3 + m9_4 * buf4 + m9_5 * buf5 + m9_6 * buf6 + m9_7 * buf7 + b9_0;
buf0 = sigmoid(buf0);

// ============ GRAIN EFFECT ============
float2 grainUV = _surface.diffuseTexcoord * 350.0;
float timeOffset = fract(iTime * 10.0);

float grain1 = fract(sin(dot(grainUV + timeOffset, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
float grain2 = fract(sin(dot(grainUV * 0.5 + timeOffset * 1.7, float2(39.346, 11.135))) * 43758.5453) - 0.5;
float grain3 = fract(sin(dot(grainUV * 0.25 + timeOffset * 0.8, float2(73.156, 52.235))) * 43758.5453) - 0.5;

float totalGrain = grain1 * 0.5 + grain2 * 0.35 + grain3 * 0.15;
totalGrain *= 0.28;

float3 baseColor = float3(buf0.x, buf0.y, buf0.z);

float colorIntensity = dot(baseColor, float3(0.299, 0.587, 0.114));
totalGrain *= smoothstep(0.0, 0.3, colorIntensity);

float3 outputColor;
if (tintStrength > 0.0) {
    float luminance = dot(baseColor, float3(0.299, 0.587, 0.114));
    float3 tinted1 = float3(luminance) * tintColor * 2.0;
    float3 tinted2 = float3(luminance) * tintColor2 * 2.0;

    // Position-based blend between tint1 and tint2
    float zoneMix = smoothstep(0.3, 0.7, baseColor.z * 0.6 + uv.y * 0.25 + 0.35 + 0.15 * sin(iTime * 0.4 + uv.x * 2.0));
    float3 tinted = mix(tinted1, tinted2, zoneMix * tint2Strength);
    outputColor = mix(baseColor, tinted, tintStrength);
} else {
    outputColor = baseColor;
}

float3 finalColor = outputColor + totalGrain;
finalColor = max(finalColor, float3(0.0));
finalColor = min(finalColor, float3(1.0));

_surface.diffuse = float4(finalColor, 1.0);
"""

// MARK: - SceneKit Renderer

class CPPNSceneRenderer: NSObject, SCNSceneRendererDelegate {
    weak var sceneView: SCNView?
    private var startTime: CFTimeInterval = 0
    private var material: SCNMaterial?

    var tintColor: PlatformColor = .white
    var tintStrength: Float = 0.0
    var tintColor2: PlatformColor = .white
    var tint2Strength: Float = 0.0

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

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 1
        cameraNode.position = SCNVector3(0, 0, 1)
        scene.rootNode.addChildNode(cameraNode)

        let plane = SCNPlane(width: 4, height: 4)
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(planeNode)

        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.black
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: cppnFragmentShader]

        material.setValue(Float(0), forKey: "iTime")
        material.setValue(SCNVector3(1, 1, 0), forKey: "iResolution")
        material.setValue(SCNVector3(1, 1, 1), forKey: "tintColor")
        material.setValue(Float(0), forKey: "tintStrength")
        material.setValue(SCNVector3(1, 1, 1), forKey: "tintColor2")
        material.setValue(Float(0), forKey: "tint2Strength")

        plane.materials = [material]
        self.material = material
        updateUniforms()
    }

    func updateUniforms() {
        guard let material = material else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        let convertedColor = tintColor.usingColorSpace(.deviceRGB) ?? tintColor
        convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        tintColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        material.setValue(SCNVector3(Float(r), Float(g), Float(b)), forKey: "tintColor")
        material.setValue(tintStrength, forKey: "tintStrength")

        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        #if os(macOS)
        let convertedColor2 = tintColor2.usingColorSpace(.deviceRGB) ?? tintColor2
        convertedColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #else
        tintColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        #endif
        material.setValue(SCNVector3(Float(r2), Float(g2), Float(b2)), forKey: "tintColor2")
        material.setValue(tint2Strength, forKey: "tint2Strength")
    }

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

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard let material = material else { return }
        let elapsed = Float(CACurrentMediaTime() - startTime)
        material.setValue(elapsed, forKey: "iTime")

        let size = cachedSize
        let scale = cachedScale
        if size.width > 0 && size.height > 0 {
            material.setValue(
                SCNVector3(Float(size.width * scale), Float(size.height * scale), 0),
                forKey: "iResolution"
            )
        }
    }

    func updateParams(tintColor: PlatformColor, tintStrength: Float, tintColor2: PlatformColor = .white, tint2Strength: Float = 0.0, size: CGSize, scale: CGFloat) {
        self.tintColor = tintColor
        self.tintStrength = tintStrength
        self.tintColor2 = tintColor2
        self.tint2Strength = tint2Strength
        self.cachedSize = size
        self.cachedScale = scale
        updateUniforms()
    }
}

// MARK: - Platform View Wrapper

#if os(iOS)
struct CPPNSceneView: UIViewRepresentable {
    var tintColor: PlatformColor
    var tintStrength: Float
    var tintColor2: PlatformColor = .white
    var tint2Strength: Float = 0.0
    func makeCoordinator() -> CPPNSceneRenderer { CPPNSceneRenderer() }
    func makeUIView(context: Context) -> SCNView { createView(context: context) }
    func updateUIView(_ uiView: SCNView, context: Context) { updateView(uiView, context: context) }
}
#else
struct CPPNSceneView: NSViewRepresentable {
    var tintColor: PlatformColor
    var tintStrength: Float
    var tintColor2: PlatformColor = .white
    var tint2Strength: Float = 0.0
    func makeCoordinator() -> CPPNSceneRenderer { CPPNSceneRenderer() }
    func makeNSView(context: Context) -> SCNView { createView(context: context) }
    func updateNSView(_ nsView: SCNView, context: Context) { updateView(nsView, context: context) }
}
#endif

extension CPPNSceneView {
    func createView(context: Context) -> SCNView {
        let scnView = NonFocusableSCNView()
        scnView.antialiasingMode = .none
        scnView.preferredFramesPerSecond = 20
        #if os(iOS)
        // Purely decorative background — opt out of the UIKit focus system so
        // SCNView does not spam "focusItemsInRect: caching for linear focus
        // movement is limited…" every layout pass.
        scnView.isUserInteractionEnabled = false
        #endif
        context.coordinator.setup(in: scnView)
        let scale = scnView.displayScale
        context.coordinator.updateParams(
            tintColor: tintColor,
            tintStrength: tintStrength,
            tintColor2: tintColor2,
            tint2Strength: tint2Strength,
            size: scnView.bounds.size,
            scale: scale
        )
        return scnView
    }

    func updateView(_ view: SCNView, context: Context) {
        let scale = view.displayScale
        context.coordinator.updateParams(
            tintColor: tintColor,
            tintStrength: tintStrength,
            tintColor2: tintColor2,
            tint2Strength: tint2Strength,
            size: view.bounds.size,
            scale: scale
        )
    }
}

// MARK: - NebulaShaderView

enum NebulaTheme: Int {
    case home = 0
    case lists = 1
    case recipes = 2
    case nutrients = 3
    case settings = 4
    case assistant = 5
}

struct NebulaShaderView: View {
    var theme: NebulaTheme
    var progress: CGFloat

    init(theme: NebulaTheme = .home, progress: CGFloat = 1.0) {
        self.theme = theme
        self.progress = progress
    }

    var body: some View {
        ZStack {
            let tintInfo: (color: Color, strength: Float, color2: Color, strength2: Float) = {
                switch theme {
                case .home:
                    // Bright crimson tint only.
                    return (Color(red: 0.95, green: 0.08, blue: 0.18), 1.32,
                            Color.white, 0.0)
                case .lists:
                    return (Color(red: 0.12, green: 0.55, blue: 1.0), 1.22,
                            Color.white, 0.0)
                case .recipes:
                    return (Color(red: 1.0, green: 0.66, blue: 0.06), 1.20,
                            Color.white, 0.0)
                case .nutrients:
                    return (Color(red: 0.04, green: 1.0, blue: 0.34), 1.22,
                            Color.white, 0.0)
                case .settings:
                    // Cool slate gray — low strength keeps the shader neutral.
                    return (Color(red: 0.50, green: 0.55, blue: 0.62), 0.75,
                            Color.white, 0.0)
                case .assistant:
                    // Soft warm gray — low strength keeps the shader neutral.
                    return (Color(red: 0.58, green: 0.58, blue: 0.62), 0.75,
                            Color.white, 0.0)
                }
            }()

            CPPNSceneView(
                tintColor: PlatformColor(tintInfo.color),
                tintStrength: tintInfo.strength,
                tintColor2: PlatformColor(tintInfo.color2),
                tint2Strength: tintInfo.strength2
            )
            .ignoresSafeArea()
            .opacity(progress)

            // Darken layer for home
            if theme == .home {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
            }

            GeometryReader { geo in
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.black.opacity(0.6), location: 0),
                        .init(color: Color.black.opacity(0.3), location: 0.3),
                        .init(color: Color.clear, location: 0.6)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: geo.size.height * 0.4
                )
            }
            .ignoresSafeArea()
            .opacity(progress)
        }
    }
}
