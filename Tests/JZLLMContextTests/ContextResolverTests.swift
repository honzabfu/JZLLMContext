import Foundation
import Testing
@testable import JZLLMContext

struct ContextResolverTests {
    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
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

    @Test func inlineStringWorkbookNeverReturnsZIPBytes() async throws {
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
            // Until #43 supports inline strings, report extraction failure.
            expectFileReadFailure(await ContextResolver.extractText(from: archive))
            let disguised = directory.appendingPathComponent("archive.txt")
            try FileManager.default.copyItem(at: archive, to: disguised)
            expectFileReadFailure(await ContextResolver.extractText(from: disguised))
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
