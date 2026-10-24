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
    @MainActor
    static func resolve(
        pasteboard: NSPasteboard = .general,
        extractFile: @escaping @Sendable (URL) async -> ContextResult = { await extractText(from: $0) }
    ) async -> ContextResult {
        // File copied from Finder (Cmd+C) — check before plain text because Finder also puts
        // the file path string on the pasteboard, which would be returned as raw text otherwise.
        // Include image URLs: Finder may provide only a URL and filename, without image data.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = urls.first {
            return await extractFile(fileURL)
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

        // A failed document extractor must not fall through to single-byte decoding:
        // Latin-1 can turn an entire ZIP/OLE container into apparent text.
        let documentExts = iworkExts.union(["doc", "docx", "odt", "rtfd", "xls", "xlsx", "ppt", "pptx"])
        guard !documentExts.contains(ext) else { return .error(.fileReadFailed) }

        // Plain text fallback for .txt, .md, .csv, .json, source code, etc. (off main thread)
        // Auto-detect encoding via BOM/heuristics; fall back to common legacy encodings.
        let plainText: String? = await Task.detached {
            guard let data = try? Data(contentsOf: fileURL), !looksLikeBinary(data) else { return nil }
            var enc: String.Encoding = .utf8
            if let text = try? String(contentsOf: fileURL, usedEncoding: &enc), isPlainText(text) { return text }
            for fallback: String.Encoding in [.windowsCP1250, .isoLatin2, .isoLatin1] {
                if let text = String(data: data, encoding: fallback), isPlainText(text) { return text }
            }
            return nil
        }.value
        if let text = plainText, !text.isEmpty {
            return .text(text, isOCR: false)
        }

        return .error(.fileReadFailed)
    }

    private static func looksLikeBinary(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0x50, 0x4B, 0x07, 0x08], // ZIP
            [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], // OLE (DOC/XLS/PPT)
            [0x1F, 0x8B], // gzip
            Array("%PDF-".utf8), Array("bplist00".utf8),
            [0x89, 0x50, 0x4E, 0x47], [0xFF, 0xD8, 0xFF], // PNG, JPEG
            Array("GIF87a".utf8), Array("GIF89a".utf8)
        ]
        if signatures.contains(where: { data.starts(with: $0) }) { return true }
        // UTF-16/32 legitimately contain NUL bytes; a BOM identifies those encodings.
        let unicodeBOMs: [[UInt8]] = [[0xFF, 0xFE], [0xFE, 0xFF], [0x00, 0x00, 0xFE, 0xFF]]
        return data.contains(0) && !unicodeBOMs.contains(where: { data.starts(with: $0) })
    }

    private static func isPlainText(_ text: String) -> Bool {
        // Keep newlines, tabs and page breaks, but reject embedded binary controls.
        !text.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && ![9, 10, 12, 13].contains($0.value)
        }
    }

    private static func unzipEntry(from archive: URL, path: String) async -> Data? {
        await Task.detached { readArchiveEntry(from: archive, path: path) }.value
    }

    private static func readArchiveEntry(from archive: URL, path: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Drain output before waiting, and bound expanded ZIP entries independently
        // of the 5 MB compressed-file limit.
        var data = Data()
        var failed = false
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                guard data.count + chunk.count <= 10 * 1024 * 1024 else {
                    failed = true
                    process.terminate()
                    break
                }
                data.append(chunk)
            }
        } catch {
            failed = true
            process.terminate()
        }
        // Closing also prevents a child from blocking on a full pipe on failure.
        pipe.fileHandleForReading.closeFile()
        process.waitUntilExit()
        guard !failed, process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    private static func extractOfficeOpenXML(from fileURL: URL, type ext: String) async -> String? {
        await Task.detached {
            if ext == "xlsx" {
                return try? OfficeOpenXML.workbook { readArchiveEntry(from: fileURL, path: $0) }
            }
            guard let text = try? OfficeOpenXML.presentation(read: { readArchiveEntry(from: fileURL, path: $0) }),
                  !text.isEmpty else { return nil }
            return text
        }.value
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

    static func performOCR(
        on image: NSImage,
        perform: @escaping @Sendable (VNImageRequestHandler, [VNRequest]) throws -> Void = { try $0.perform($1) }
    ) async -> ContextResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .error(.ocrFailed)
        }

        // Vision's perform is synchronous. Read results after it returns instead of
        // bridging its optional callback with a continuation that may never resume
        // on a thrown error. Keep image analysis off the caller's (often main) thread.
        return await Task.detached {
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try perform(handler, [request])
                let text = (request.results ?? [])
                    .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                return text.isEmpty ? ContextResult.error(.ocrFailed) : .text(text, isOCR: true)
            } catch {
                return .error(.ocrFailed)
            }
        }.value
    }
}
