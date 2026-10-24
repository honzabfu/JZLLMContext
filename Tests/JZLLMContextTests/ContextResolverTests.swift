import AppKit
import Foundation
import Testing
@testable import JZLLMContext

@MainActor
struct ContextResolverTests {
    @MainActor
    private func image(withText text: String = "") throws -> NSImage {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 240,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 240).fill()
        (text as NSString).draw(at: NSPoint(x: 50, y: 90), withAttributes: [
            .font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black
        ])
        return NSImage(cgImage: try #require(bitmap.cgImage), size: NSSize(width: 1000, height: 240))
    }

    @Test @MainActor func thrownVisionErrorFinishesOCR() async throws {
        struct TestError: Error {}
        let result = await ContextResolver.performOCR(on: try image()) { _, requests in
            #expect(requests.count == 1)
            #expect(requests.first?.completionHandler == nil)
            throw TestError()
        }
        guard case .error(.ocrFailed) = result else {
            Issue.record("Expected ocrFailed for thrown Vision error, got \(result)")
            return
        }
    }

    @Test @MainActor func missingVisionResultsFinishOCR() async throws {
        let result = await ContextResolver.performOCR(on: try image()) { _, _ in }
        guard case .error(.ocrFailed) = result else {
            Issue.record("Expected ocrFailed without observations, got \(result)")
            return
        }
    }

    @Test @MainActor func finderImageURLTakesPrecedenceOverFilename() async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("photo.png")
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            #expect(pasteboard.writeObjects([url as NSURL]))
            #expect(pasteboard.setString("photo.png", forType: .string))
            let result = await ContextResolver.resolve(pasteboard: pasteboard) { receivedURL in
                #expect(receivedURL == url)
                return .text("FILE EXTRACTION RESULT", isOCR: true)
            }
            guard case .text(let text, let isOCR) = result else {
                Issue.record("Expected file extraction result")
                return
            }
            #expect(text == "FILE EXTRACTION RESULT")
            #expect(isOCR)
        }
    }

    // Actual Vision inference depends on locally installed system models, and may
    // take minutes or fail to initialize on test hosts. Keep it explicitly opt-in.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VISION_TESTS"] == "1"))
    func finderImageRunsRealOCR() async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("photo.png")
            let tiff = try #require(try image(withText: "FINDER IMAGE TEST").tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            // Reproduce Finder's file URL + filename, deliberately without bitmap data.
            #expect(pasteboard.writeObjects([url as NSURL]))
            #expect(pasteboard.setString("photo.png", forType: .string))
            guard case .text(let text, let isOCR) = await ContextResolver.resolve(pasteboard: pasteboard) else {
                Issue.record("Expected OCR text from Finder image URL")
                return
            }
            #expect(isOCR)
            #expect(text.contains("FINDER IMAGE TEST"))
            #expect(text != "photo.png")
        }
    }

    @Test @MainActor func unreadableFinderImageDoesNotFallBackToFilename() async throws {
        try await withDirectory { directory in
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            #expect(pasteboard.writeObjects([directory.appendingPathComponent("missing.png") as NSURL]))
            #expect(pasteboard.setString("missing.png", forType: .string))
            expectFileReadFailure(await ContextResolver.resolve(pasteboard: pasteboard))
        }
    }

    @Test func clipboardTextStillWorks() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("Clipboard text", forType: .string))
        guard case .text(let text, let isOCR) = await ContextResolver.resolve(pasteboard: pasteboard) else {
            Issue.record("Expected plain clipboard text")
            return
        }
        #expect(text == "Clipboard text")
        #expect(!isOCR)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VISION_TESTS"] == "1"))
    func clipboardBitmapRunsRealOCR() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([try image(withText: "CLIPBOARD IMAGE TEST")]))
        guard case .text(let bitmapText, let bitmapOCR) = await ContextResolver.resolve(pasteboard: pasteboard) else {
            Issue.record("Expected OCR from clipboard bitmap")
            return
        }
        #expect(bitmapOCR)
        #expect(bitmapText.contains("CLIPBOARD IMAGE TEST"))
    }

    private func withDirectory(_ body: @MainActor (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    private func expectFileReadFailure(_ result: ContextResult) {
        guard case .error(.fileReadFailed) = result else {
            Issue.record("Expected fileReadFailed, got \(result)")
            return
        }
    }

    @Test func incompleteWorkbookNeverReturnsZIPBytes() async throws {
        try await withDirectory { directory in
            let sheet = directory.appendingPathComponent("xl/worksheets/sheet1.xml")
            try FileManager.default.createDirectory(at: sheet.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Hello</t></is></c></row></sheetData>
            </worksheet>
            """.utf8).write(to: sheet)
            let archive = directory.appendingPathComponent("inline.xlsx")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.currentDirectoryURL = directory
            zip.arguments = ["-q", archive.path, "xl/worksheets/sheet1.xml"]
            zip.standardOutput = FileHandle.nullDevice
            zip.standardError = FileHandle.nullDevice
            try zip.run()
            zip.waitUntilExit()
            #expect(zip.terminationStatus == 0)
            // A worksheet without workbook metadata is not a readable workbook.
            expectFileReadFailure(await ContextResolver.extractText(from: archive))
            let disguised = directory.appendingPathComponent("archive.txt")
            try FileManager.default.copyItem(at: archive, to: disguised)
            expectFileReadFailure(await ContextResolver.extractText(from: disguised))
        }
    }

    private func withOfficeArchive(_ parts: [String: String], extension ext: String,
                                   body: @MainActor (URL) async throws -> Void) async throws {
        try await withDirectory { directory in
            let input = directory.appendingPathComponent("parts")
            for (name, xml) in parts {
                let url = input.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(xml.utf8).write(to: url)
            }
            let archive = directory.appendingPathComponent("test.\(ext)")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.currentDirectoryURL = input
            zip.arguments = ["-q", "-r", archive.path, "."]
            zip.standardOutput = FileHandle.nullDevice
            zip.standardError = FileHandle.nullDevice
            try zip.run()
            zip.waitUntilExit()
            #expect(zip.terminationStatus == 0)
            try await body(archive)
        }
    }

    @Test func inlineWorkbookExtractsFromRealZIP() async throws {
        try await withOfficeArchive(OfficeFixtures.workbook, extension: "xlsx") { archive in
            guard case .text(let text, let isOCR) = await ContextResolver.extractText(from: archive) else {
                Issue.record("Expected inline worksheet text from complete workbook")
                return
            }
            #expect(text == "Sheet: Test\nRow\tA\n1\tHello")
            #expect(!isOCR)
            let disguised = archive.deletingPathExtension().appendingPathExtension("txt")
            try FileManager.default.copyItem(at: archive, to: disguised)
            expectFileReadFailure(await ContextResolver.extractText(from: disguised))
        }
    }

    @Test func slideEntitiesExtractFromRealZIP() async throws {
        var parts = OfficeFixtures.presentation(order: [1])
        parts["ppt/slides/slide1.xml"] = """
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <a:tabLst><a:tab/></a:tabLst><a:t>A &amp; B &#x1F600; &amp;lt;</a:t></p:sld>
        """
        try await withOfficeArchive(parts, extension: "pptx") { archive in
            guard case .text(let text, _) = await ContextResolver.extractText(from: archive) else {
                Issue.record("Expected slide text")
                return
            }
            #expect(text == "A & B 😀 &lt;")
        }
    }

    @Test(arguments: [Array(1...12), [12, 2, 1, 10, 3, 11, 4, 9, 5, 8, 6, 7]])
    func presentationOrderExtractsFromRealZIP(order: [Int]) async throws {
        try await withOfficeArchive(OfficeFixtures.presentation(order: order), extension: "pptx") { archive in
            guard case .text(let text, _) = await ContextResolver.extractText(from: archive) else {
                Issue.record("Expected ordered presentation text")
                return
            }
            #expect(text == order.map { "Slide \($0)" }.joined(separator: "\n"))
        }
    }

    @Test func missingPresentationSlideDoesNotReturnPartialText() async throws {
        var parts = OfficeFixtures.presentation(order: [1, 2])
        parts.removeValue(forKey: "ppt/slides/slide2.xml")
        try await withOfficeArchive(parts, extension: "pptx") { archive in
            expectFileReadFailure(await ContextResolver.extractText(from: archive))
        }
    }

    @Test func archiveOutputLargerThanPipeBufferDoesNotDeadlock() async throws {
        var parts = OfficeFixtures.workbook
        let text = String(repeating: "large text ", count: 10_000)
        parts["xl/worksheets/sheet1.xml"] = "<worksheet><sheetData><row><c t=\"inlineStr\"><is><t>\(text)</t></is></c></row></sheetData></worksheet>"
        try await withOfficeArchive(parts, extension: "xlsx") { archive in
            guard case .text(let extracted, _) = await ContextResolver.extractText(from: archive) else {
                Issue.record("Expected text larger than pipe buffer")
                return
            }
            #expect(extracted == "Sheet: Test\nRow\tA\n1\t" + text)
        }
    }

    @Test func oversizedExpandedArchiveEntryIsRejected() async throws {
        var parts = OfficeFixtures.workbook
        parts["xl/worksheets/sheet1.xml"] = String(repeating: "x", count: 10 * 1024 * 1024 + 1)
        try await withOfficeArchive(parts, extension: "xlsx") { archive in
            expectFileReadFailure(await ContextResolver.extractText(from: archive))
        }
    }

    @Test(arguments: ["xlsx", "pptx", "pages", "xls"])
    func failedDocumentExtractionDoesNotUseRawText(extension ext: String) async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("broken.\(ext)")
            // Even readable bytes are not the extracted content of a document container.
            try Data("Not a valid document".utf8).write(to: url)
            expectFileReadFailure(await ContextResolver.extractText(from: url))
        }
    }

    @Test func unknownBinaryFilesAreRejected() async throws {
        let samples: [[UInt8]] = [
            [0x50, 0x4B, 0x05, 0x06] + Array(repeating: 0, count: 18),
            [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
            [0x1F, 0x8B, 0x08, 0x01],
            [0x41, 0x00, 0x42, 0x00, 0x01],
            [0x41, 0x01, 0x02, 0x03, 0x42],
            Array("bplist00".utf8) + [0x01, 0x02]
        ]
        try await withDirectory { directory in
            for (index, bytes) in samples.enumerated() {
                let url = directory.appendingPathComponent("binary-\(index).unknown")
                try Data(bytes).write(to: url)
                expectFileReadFailure(await ContextResolver.extractText(from: url))
            }
        }
    }

    @Test func plainTextEncodingsRemainSupported() async throws {
        let samples: [(String, String.Encoding)] = [
            ("Příliš žluťoučký kůň\nNový řádek\t123", .utf8),
            ("Příliš žluťoučký kůň\r\nNový řádek", .windowsCP1250),
            ("café Noël\nStraße", .isoLatin1),
            ("Český text a 日本語\nDalší řádek", .utf16),
            ("Český text a 日本語", .utf32)
        ]
        try await withDirectory { directory in
            for (index, sample) in samples.enumerated() {
                let (text, encoding) = sample
                let data = try #require(text.data(using: encoding))
                let url = directory.appendingPathComponent("text-\(index).txt")
                try data.write(to: url)
                guard case .text(let extracted, let isOCR) = await ContextResolver.extractText(from: url) else {
                    Issue.record("Text rejected for encoding \(encoding)")
                    continue
                }
                #expect(extracted == text, "Encoding \(encoding)")
                #expect(!isOCR)
            }
        }
    }
}
