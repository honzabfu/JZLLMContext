import AppKit
import CoreServices
import PDFKit
import Vision

enum ContextResult {
    case text(String, isOCR: Bool)
    case error(ContextError)
}

enum ContextError: Error, LocalizedError {
    case empty
    case ocrFailed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .empty: "Zkopíruj text nebo obrázek do schránky (⌘C)"
        case .ocrFailed: "Text nebyl rozpoznán"
        case .fileReadFailed: "Soubor nelze přečíst"
        }
    }
}

enum ContextResolver {
    static func resolve() async -> ContextResult {
        let pasteboard = NSPasteboard.general

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text, isOCR: false)
        }

        // File copied from Finder (Cmd+C): non-image files carry only a file URL,
        // no text or image data — route them through extractText.
        // Image files carry both a file URL and full image data; let NSImage handle those.
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "bmp", "gif"]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = urls.first,
           !imageExts.contains(fileURL.pathExtension.lowercased()) {
            return await extractText(from: fileURL)
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return await performOCR(on: image)
        }

        return .error(.empty)
    }

    static func extractText(from fileURL: URL) async -> ContextResult {
        let maxBytes = 5 * 1024 * 1024
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes {
            return .error(.fileReadFailed)
        }

        let ext = fileURL.pathExtension.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "bmp", "gif"]

        if imageExts.contains(ext) {
            guard let image = NSImage(contentsOf: fileURL) else { return .error(.fileReadFailed) }
            return await performOCR(on: image)
        }

        if ext == "pdf" {
            if let doc = PDFDocument(url: fileURL) {
                let text = (0..<doc.pageCount)
                    .compactMap { doc.page(at: $0)?.string }
                    .joined(separator: "\n")
                if !text.isEmpty { return .text(text, isOCR: false) }
            }
            return .error(.fileReadFailed)
        }

        // Spotlight handles DOCX, XLSX, RTF, HTML, PPTX, Pages, Numbers, Keynote, etc.
        let spotlightText: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let text = MDItemCreateWithURL(nil, fileURL as CFURL)
                    .flatMap { MDItemCopyAttribute($0, kMDItemTextContent) as? String }
                continuation.resume(returning: text)
            }
        }
        if let text = spotlightText, !text.isEmpty {
            return .text(text, isOCR: false)
        }

        // Plain text fallback for .txt, .md, .csv, .json, source code, etc. (off main thread)
        // Auto-detect encoding via BOM/heuristics; fall back to common legacy encodings.
        let plainText: String? = await Task.detached {
            var enc: String.Encoding = .utf8
            if let text = try? String(contentsOf: fileURL, usedEncoding: &enc) { return text }
            for fallback: String.Encoding in [.windowsCP1250, .isoLatin2, .isoLatin1] {
                if let text = try? String(contentsOf: fileURL, encoding: fallback) { return text }
            }
            return nil
        }.value
        if let text = plainText, !text.isEmpty {
            return .text(text, isOCR: false)
        }

        return .error(.fileReadFailed)
    }

    static func performOCR(on image: NSImage) async -> ContextResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .error(.ocrFailed)
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty
                else {
                    continuation.resume(returning: .error(.ocrFailed))
                    return
                }

                let text = observations
                    .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text.isEmpty ? .error(.ocrFailed) : .text(text, isOCR: true))
            }

            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
