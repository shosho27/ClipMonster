import Cocoa
import Vision

// MARK: - OCR (Apple Vision)
enum ImageOCR {
    static func recognizeText(in image: NSImage, completion: @escaping (String?) -> Void) {
        guard let cgImage = image.cgImageForOCR else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(joined.isEmpty ? nil : joined)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}

extension NSImage {
    var cgImageForOCR: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        if let cg = cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }
}

