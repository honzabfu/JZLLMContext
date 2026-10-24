import Foundation

/// Reads the XML parts of an Office ZIP without treating sharedStrings as a worksheet.
/// All state stays local to the synchronous extraction task.
enum OfficeOpenXML {
    enum ExtractionError: Error { case invalidDocument }

    static func workbook(read: (String) -> Data?) throws -> String {
        let book = try parse(read("xl/workbook.xml"))
        let relationships = try parse(read("xl/_rels/workbook.xml.rels"))
        guard book.name == "workbook", relationships.name == "Relationships",
              let sheets = book.child("sheets"), !sheets.children.isEmpty else {
            throw ExtractionError.invalidDocument
        }
        var targets: [String: (path: String, type: String)] = [:]
        for relation in relationships.children where relation.name == "Relationship" {
            guard relation.attributes["TargetMode"] != "External",
                  let id = relation.attributes["Id"], let target = relation.attributes["Target"],
                  let type = relation.attributes["Type"] else { continue }
            guard targets[id] == nil else { throw ExtractionError.invalidDocument }
            targets[id] = (try partPath(target), type)
        }
        var strings: [String] = []
        let stringParts = targets.values.filter { $0.type.hasSuffix("/sharedStrings") }
        guard stringParts.count <= 1 else { throw ExtractionError.invalidDocument }
        if let part = stringParts.first {
            let table = try parse(read(part.path))
            guard table.name == "sst" else { throw ExtractionError.invalidDocument }
            strings = table.children.filter { $0.name == "si" }.map(richText)
        }
        var sections: [String] = []
        var outputSize = 0
        for sheet in sheets.children where sheet.name == "sheet" {
            guard let name = sheet.attributes["name"],
                  let id = sheet.attributes.first(where: { $0.key.hasSuffix(":id") })?.value,
                  let target = targets[id], target.type.hasSuffix("/worksheet") else {
                // Do not silently omit an unsupported sheet (e.g. a chart sheet).
                throw ExtractionError.invalidDocument
            }
            let xml = try parse(read(target.path))
            let rows = try worksheet(xml, strings: strings)
            let section = "Sheet: \(quoted(name))\n\(rows)"
            outputSize += section.utf8.count + 2
            guard outputSize <= 10 * 1024 * 1024 else { throw ExtractionError.invalidDocument }
            sections.append(section)
        }
        guard !sections.isEmpty else { throw ExtractionError.invalidDocument }
        return sections.joined(separator: "\n\n")
    }

    static func presentationText(_ data: Data) throws -> [String] {
        let root = try parse(data)
        let namespaces = ["http://schemas.openxmlformats.org/drawingml/2006/main",
                          "http://purl.oclc.org/ooxml/drawingml/main"]
        return root.descendants(named: "t").filter { namespaces.contains($0.namespace) }
            .map(\.text).filter { !$0.isEmpty }
    }

    private static func worksheet(_ root: Node, strings: [String]) throws -> String {
        guard root.name == "worksheet", let sheetData = root.child("sheetData") else {
            throw ExtractionError.invalidDocument
        }
        var cells: [Int: [Int: String]] = [:]
        var lastRow = 0
        var maxColumn = 0
        for row in sheetData.children where row.name == "row" {
            let rowIndex: Int
            if let reference = row.attributes["r"] {
                guard let number = Int(reference) else { throw ExtractionError.invalidDocument }
                rowIndex = number
            } else { rowIndex = lastRow + 1 }
            guard (1...1_048_576).contains(rowIndex), cells[rowIndex] == nil else {
                throw ExtractionError.invalidDocument
            }
            var values: [Int: String] = [:]
            var lastColumn = 0
            for cell in row.children where cell.name == "c" {
                let column: Int
                if let reference = cell.attributes["r"] {
                    let position = try cellPosition(reference)
                    guard position.row == rowIndex else { throw ExtractionError.invalidDocument }
                    column = position.column
                } else { column = lastColumn + 1 }
                guard (1...16_384).contains(column), values[column] == nil else {
                    throw ExtractionError.invalidDocument
                }
                values[column] = try cellValue(cell, strings: strings)
                lastColumn = column
                maxColumn = max(maxColumn, column)
            }
            cells[rowIndex] = values
            lastRow = max(lastRow, rowIndex)
        }
        // Bound the expanded grid: a single XFD1048576 reference must not allocate
        // billions of empty cells. Refuse instead of silently dropping positions.
        guard lastRow <= 100_000, maxColumn <= 100_000 / max(1, lastRow) else {
            throw ExtractionError.invalidDocument
        }
        guard lastRow > 0, maxColumn > 0 else { return "(empty sheet)" }
        var lines = [( ["Row"] + (1...maxColumn).map(columnName) ).joined(separator: "\t")]
        var outputSize = lines[0].utf8.count
        for row in 1...lastRow {
            var values: [String] = []
            for column in 1...maxColumn {
                let value = quoted(cells[row]?[column] ?? "")
                outputSize += value.utf8.count + 1
                guard outputSize <= 10 * 1024 * 1024 else { throw ExtractionError.invalidDocument }
                values.append(value)
            }
            outputSize += String(row).utf8.count + 1
            lines.append(([String(row)] + values).joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    private static func cellValue(_ cell: Node, strings: [String]) throws -> String {
        let value = cell.child("v")?.text
        switch cell.attributes["t"] ?? "n" {
        case "s":
            guard let value, let index = Int(value), strings.indices.contains(index) else {
                throw ExtractionError.invalidDocument
            }
            return strings[index]
        case "inlineStr":
            guard let inline = cell.child("is") else { throw ExtractionError.invalidDocument }
            return richText(inline)
        case "b":
            guard value == "0" || value == "1" else { throw ExtractionError.invalidDocument }
            return value == "1" ? "TRUE" : "FALSE"
        case "n", "str", "e", "d":
            // Use the cached formula value when supplied; never calculate formulas.
            if let value { return value }
            if let formula = cell.child("f") { return "=" + formula.text }
            return ""
        default: throw ExtractionError.invalidDocument
        }
    }

    private static func richText(_ node: Node) -> String {
        node.children.map { child in
            if child.name == "t" { return child.text }
            if child.name == "r" { return child.children.filter { $0.name == "t" }.map(\.text).joined() }
            return "" // Ignore phonetic annotations and formatting.
        }.joined()
    }

    private static func cellPosition(_ reference: String) throws -> (row: Int, column: Int) {
        let bytes = Array(reference.utf8)
        var column = 0
        var offset = 0
        while offset < bytes.count, (65...90).contains(bytes[offset]) {
            column = column * 26 + Int(bytes[offset] - 64)
            guard column <= 16_384 else { throw ExtractionError.invalidDocument }
            offset += 1
        }
        guard column > 0, offset < bytes.count,
              bytes[offset...].allSatisfy({ (48...57).contains($0) }),
              let row = Int(String(decoding: bytes[offset...], as: UTF8.self)),
              (1...1_048_576).contains(row) else { throw ExtractionError.invalidDocument }
        return (row, column)
    }

    private static func columnName(_ number: Int) -> String {
        var number = number
        var name = ""
        while number > 0 {
            number -= 1
            name = String(UnicodeScalar(65 + number % 26)!) + name
            number /= 26
        }
        return name
    }

    private static func quoted(_ value: String) -> String {
        guard value.contains(where: { "\t\n\r\"".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func partPath(_ target: String) throws -> String {
        guard !target.contains(":"), !target.contains("\\"), !target.contains("?"),
              !target.contains("#"), let decoded = target.removingPercentEncoding,
              !decoded.contains(":"), !decoded.contains("\\"),
              !decoded.contains(where: { "*?[]".contains($0) }) else { throw ExtractionError.invalidDocument }
        var components = decoded.hasPrefix("/") ? [] : ["xl"]
        for component in decoded.split(separator: "/").map(String.init) {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { throw ExtractionError.invalidDocument }
                components.removeLast()
            } else { components.append(component) }
        }
        guard !components.isEmpty else { throw ExtractionError.invalidDocument }
        return components.joined(separator: "/")
    }

    private static func parse(_ data: Data?) throws -> Node {
        guard let data, data.count <= 10 * 1024 * 1024 else { throw ExtractionError.invalidDocument }
        let delegate = TreeParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw ExtractionError.invalidDocument }
        return root
    }

    private final class Node {
        let name: String
        let namespace: String
        let attributes: [String: String]
        var text = ""
        var children: [Node] = []
        init(_ name: String, namespace: String, attributes: [String: String]) {
            self.name = name; self.namespace = namespace; self.attributes = attributes
        }
        func child(_ name: String) -> Node? { children.first { $0.name == name } }
        func descendants(named name: String) -> [Node] {
            (self.name == name ? [self] : []) + children.flatMap { $0.descendants(named: name) }
        }
    }

    private final class TreeParser: NSObject, XMLParserDelegate {
        var root: Node?
        private var stack: [Node] = []
        private var count = 0
        private var textSize = 0
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            count += 1
            guard count <= 200_000, stack.count < 128 else { parser.abortParsing(); return }
            let node = Node(name, namespace: namespaceURI ?? "", attributes: attributes)
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
            if !stack.isEmpty { stack.removeLast() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textSize += string.utf8.count
            guard textSize <= 10 * 1024 * 1024 else { parser.abortParsing(); return }
            stack.last?.text += string
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let string = String(data: CDATABlock, encoding: .utf8) else { parser.abortParsing(); return }
            self.parser(parser, foundCharacters: string)
        }
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName: String, value: String?) {
            parser.abortParsing()
        }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName: String, publicID: String?, systemID: String?) {
            parser.abortParsing()
        }
    }
}
