import Foundation
import Vision
import ImageIO
let locales = ["en":"en-US", "es":"es-ES", "fr":"fr-FR", "de":"de-DE", "it":"it-IT", "ja":"ja-JP"]
let language = CommandLine.arguments[1]
var output: [[String: Any]] = []
for file in CommandLine.arguments.dropFirst(2) {
    let url = URL(fileURLWithPath: file)
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [locales[language] ?? "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    let lines = (request.results ?? []).compactMap { observation -> [String: Any]? in
        guard let text = observation.topCandidates(1).first else { return nil }
        let b = observation.boundingBox
        return ["text": text.string, "confidence": text.confidence,
                "left": b.minX * Double(image.width), "top": (1-b.maxY) * Double(image.height),
                "width": b.width * Double(image.width), "height": b.height * Double(image.height)]
    }
    output.append(["file": url.lastPathComponent, "width": image.width, "height": image.height, "lines": lines])
}
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys])
FileHandle.standardOutput.write(data)
