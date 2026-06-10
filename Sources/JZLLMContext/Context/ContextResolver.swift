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

        // File copied from Finder (Cmd+C) — check before plain text because Finder also puts
        // the file path string on the pasteboard, which would be returned as raw text otherwise.
        // Image files carry full image data too; let NSImage handle those via OCR.
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "bmp", "gif"]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = urls.first,
           !imageExts.contains(fileURL.pathExtension.lowercased()) {
            return await extractText(from: fileURL)
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text, isOCR: false)
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

        // iWork files (Pages, Numbers, Keynote) — stored as bundle directories OR ZIP archives;
        // both formats contain preview.jpg at the root which we OCR as a fallback.
        // Some newer versions may also include QuickLook/Preview.pdf (higher fidelity).
        let iworkExts: Set<String> = ["pages", "numbers", "key"]
        if iworkExts.contains(ext) {
            if let doc = PDFDocument(url: fileURL.appendingPathComponent("QuickLook/Preview.pdf")) {
                let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
                if !text.isEmpty { return .text(text, isOCR: false) }
            }
            if let image = NSImage(contentsOf: fileURL.appendingPathComponent("preview.jpg")) {
                return await performOCR(on: image)
            }
            if let data = await unzipEntry(from: fileURL, path: "preview.jpg"),
               let image = NSImage(data: data) {
                return await performOCR(on: image)
            }
        }

        // textutil reliably extracts Word, RTF, HTML — Spotlight returns null for these on many systems
        let textutilExts: Set<String> = ["doc", "docx", "rtf", "rtfd", "odt", "html", "htm"]
        if textutilExts.contains(ext),
           let text = await extractWithTextUtil(from: fileURL), !text.isEmpty {
            return .text(text, isOCR: false)
        }

        // XLSX/PPTX are ZIP archives with XML inside — Spotlight and textutil both fail for these
        if ext == "xlsx" || ext == "pptx" {
            if let text = await extractOfficeOpenXML(from: fileURL, type: ext), !text.isEmpty {
                return .text(text, isOCR: false)
            }
        }

        // Spotlight handles Pages, Numbers, Keynote, XLS (old binary format), etc.
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

    private static func unzipEntry(from archive: URL, path: String) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                proc.arguments = ["-p", archive.path, path]
                let pipe = Pipe()
                proc.standardOutput = pipe; proc.standardError = Pipe()
                guard (try? proc.run()) != nil else { continuation.resume(returning: nil); return }
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data.isEmpty ? nil : data)
            }
        }
    }

    // XLSX: text lives in xl/sharedStrings.xml; PPTX: in ppt/slides/slide*.xml
    private static func extractOfficeOpenXML(from fileURL: URL, type ext: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let xmlPaths: [String]
                if ext == "xlsx" {
                    xmlPaths = ["xl/sharedStrings.xml"]
                } else {
                    // List ZIP contents first to discover slide XMLs without spawning 50 processes
                    let ls = Process()
                    ls.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    ls.arguments = ["-Z1", fileURL.path]
                    let lsPipe = Pipe()
                    ls.standardOutput = lsPipe; ls.standardError = Pipe()
                    guard (try? ls.run()) != nil else { continuation.resume(returning: nil); return }
                    ls.waitUntilExit()
                    let listing = String(data: lsPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    xmlPaths = listing.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                        .sorted()
                }

                let textTag = ext == "xlsx" ? "t" : "a:t"
                var allStrings: [String] = []

                for xmlPath in xmlPaths {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    proc.arguments = ["-p", fileURL.path, xmlPath]
                    let pipe = Pipe()
                    proc.standardOutput = pipe; proc.standardError = Pipe()
                    guard (try? proc.run()) != nil else { continue }
                    proc.waitUntilExit()
                    guard proc.terminationStatus == 0,
                          let xml = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                    else { continue }
                    allStrings.append(contentsOf: xmlTextContent(xml, tag: textTag))
                }

                continuation.resume(returning: allStrings.isEmpty ? nil : allStrings.joined(separator: "\n"))
            }
        }
    }

    // Extracts text from all <tag>…</tag> occurrences; handles attributes and skips self-closing tags.
    private static func xmlTextContent(_ xml: String, tag: String) -> [String] {
        let open = "<\(tag)"
        let close = "</\(tag)>"
        var result: [String] = []
        var pos = xml.startIndex
        while let matchRange = xml.range(of: open, range: pos..<xml.endIndex) {
            guard let angleClose = xml.range(of: ">", range: matchRange.upperBound..<xml.endIndex) else { break }
            if xml[matchRange.upperBound..<angleClose.lowerBound].hasSuffix("/") { pos = angleClose.upperBound; continue }
            guard let endTag = xml.range(of: close, range: angleClose.upperBound..<xml.endIndex) else { break }
            let text = String(xml[angleClose.upperBound..<endTag.lowerBound])
            if !text.isEmpty { result.append(text) }
            pos = endTag.upperBound
        }
        return result
    }

    private static func extractWithTextUtil(from fileURL: URL) async -> String? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")

        let succeeded: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                process.arguments = ["-convert", "txt", "-output", tmpURL.path, fileURL.path]
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }

        defer { try? FileManager.default.removeItem(at: tmpURL) }
        guard succeeded else { return nil }
        return try? String(contentsOf: tmpURL, encoding: .utf8)
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
