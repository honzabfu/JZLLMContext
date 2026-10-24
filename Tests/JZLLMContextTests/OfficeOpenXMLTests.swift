import Foundation
import Testing
@testable import JZLLMContext

struct OfficeOpenXMLTests {
    @Test func workbookKeepsSheetOrderCellPositionsAndRepeatedValues() throws {
        var parts = OfficeFixtures.workbook
        parts["xl/workbook.xml"] = """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="Second &amp; sheet" sheetId="2" r:id="r2"/><sheet name="First" sheetId="1" r:id="r1"/></sheets>
        </workbook>
        """
        parts["xl/_rels/workbook.xml.rels"] = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet9.xml"/>
          <Relationship Id="r2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/custom.xml"/>
          <Relationship Id="strings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="strings.xml"/>
        </Relationships>
        """
        parts["xl/strings.xml"] = """
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <si><t>Product</t></si><si><r><t>Wid</t></r><r><t>get</t></r><rPh><t>phonetic</t></rPh></si>
        </sst>
        """
        parts["xl/worksheets/custom.xml"] = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
          <row r="1"><c r="C1" t="inlineStr"><is><t>Amount</t></is></c><c r="A1" t="s"><v>0</v></c></row>
          <row r="2"><c r="A2" t="s"><v>1</v></c><c r="C2"><v>5678</v></c></row>
          <row r="4"><c r="A4" t="s"><v>1</v></c><c r="C4"><v>-12.5</v></c></row>
        </sheetData></worksheet>
        """
        parts["xl/worksheets/sheet9.xml"] = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
          <row r="1"><c r="B1" t="inlineStr"><is><t>Only here</t></is></c></row>
        </sheetData></worksheet>
        """
        let text = try workbook(parts)
        #expect(text == "Sheet: Second & sheet\nRow\tA\tB\tC\n1\tProduct\t\tAmount\n2\tWidget\t\t5678\n3\t\t\t\n4\tWidget\t\t-12.5\n\nSheet: First\nRow\tA\tB\n1\t\tOnly here")
    }

    @Test func inlineStringsDoNotNeedSharedStringTable() throws {
        let text = try workbook(OfficeFixtures.workbook)
        #expect(text == "Sheet: Test\nRow\tA\n1\tHello")
    }

    @Test func entitiesAreDecodedOnceInBothFormats() throws {
        let escaped = "A &amp; B &lt;x&gt; &quot;q&quot; &apos;s&apos; &#65; &#x1F600; &amp;lt;"
        let expected = "A & B <x> \"q\" 's' A 😀 &lt;"
        var parts = OfficeFixtures.workbook
        parts["xl/worksheets/sheet1.xml"] = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1">
        <c r="A1" t="inlineStr"><is><t>\(escaped)</t></is></c></row></sheetData></worksheet>
        """
        #expect(try workbook(parts).contains("1\t\"" + expected.replacingOccurrences(of: "\"", with: "\"\"") + "\""))
        let slide = """
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <a:tabLst><a:tab/></a:tabLst><a:t>\(escaped)</a:t><a:t/><a:t><![CDATA[raw <text> &amp;]]></a:t></p:sld>
        """
        #expect(try OfficeOpenXML.presentationText(Data(slide.utf8)) == [expected, "raw <text> &amp;"])
    }

    @Test func sharedStringEntitiesAndWhitespaceArePreserved() throws {
        var parts = OfficeFixtures.workbook
        parts["xl/_rels/workbook.xml.rels"] = OfficeFixtures.relationshipsWithStrings
        parts["xl/sharedStrings.xml"] = "<sst><si><t xml:space=\"preserve\"> A &amp; B &amp;lt; </t></si></sst>"
        parts["xl/worksheets/sheet1.xml"] = "<worksheet><sheetData><row><c t=\"s\"><v>0</v></c><c t=\"s\"><v>0</v></c></row></sheetData></worksheet>"
        #expect(try workbook(parts) == "Sheet: Test\nRow\tA\tB\n1\t A & B &lt; \t A & B &lt; ")
    }

    @Test func cachedFormulasBooleansErrorsAndQuotedText() throws {
        var parts = OfficeFixtures.workbook
        parts["xl/worksheets/sheet1.xml"] = """
        <worksheet><sheetData><row>
          <c><f>2+3</f><v>5</v></c><c><f>SUM(A1:A2)</f></c><c t="b"><v>1</v></c>
          <c t="b"><v>0</v></c><c t="e"><v>#DIV/0!</v></c><c t="d"><v>2026-10-24</v></c>
          <c t="inlineStr"><is><r><t>Line 1&#10;</t></r><r><t>tab&#9;&quot;quoted&quot;</t></r></is></c><c/>
        </row></sheetData></worksheet>
        """
        #expect(try workbook(parts) == "Sheet: Test\nRow\tA\tB\tC\tD\tE\tF\tG\tH\n1\t5\t=SUM(A1:A2)\tTRUE\tFALSE\t#DIV/0!\t2026-10-24\t\"Line 1\ntab\t\"\"quoted\"\"\"\t")
    }

    @Test(arguments: ["-1", "999", "not-an-index"])
    func invalidSharedStringReferenceFails(index: String) throws {
        var parts = OfficeFixtures.workbook
        parts["xl/worksheets/sheet1.xml"] = "<worksheet><sheetData><row><c t=\"s\"><v>\(index)</v></c></row></sheetData></worksheet>"
        #expect(throws: OfficeOpenXML.ExtractionError.self) { try workbook(parts) }
    }

    @Test func malformedOrMissingPartsFailInsteadOfReturningPartialWorkbook() throws {
        var parts = OfficeFixtures.workbook
        parts["xl/worksheets/sheet1.xml"] = "<worksheet><sheetData>"
        #expect(throws: OfficeOpenXML.ExtractionError.self) { try workbook(parts) }
        parts.removeValue(forKey: "xl/worksheets/sheet1.xml")
        #expect(throws: OfficeOpenXML.ExtractionError.self) { try workbook(parts) }
        #expect(throws: OfficeOpenXML.ExtractionError.self) {
            try OfficeOpenXML.presentationText(Data("<slide><t>broken".utf8))
        }
    }

    @Test(arguments: ["A0", "A1048577", "XFE1", "A99999999999999999999999999", "XFD1048576"])
    func invalidOrExcessivelySparseCoordinatesFail(reference: String) throws {
        var parts = OfficeFixtures.workbook
        let row = reference.drop(while: { $0.isLetter })
        parts["xl/worksheets/sheet1.xml"] = "<worksheet><sheetData><row r=\"\(row)\"><c r=\"\(reference)\"><v>1</v></c></row></sheetData></worksheet>"
        #expect(throws: OfficeOpenXML.ExtractionError.self) { try workbook(parts) }
    }

    @Test(arguments: ["https://example.test/sheet.xml", "../../outside.xml", "worksheets/*.xml"])
    func invalidRelationshipTargetsFail(target: String) throws {
        var parts = OfficeFixtures.workbook
        parts["xl/_rels/workbook.xml.rels"] = "<Relationships><Relationship Id=\"r1\" Type=\"x/worksheet\" Target=\"\(target)\"/></Relationships>"
        #expect(throws: OfficeOpenXML.ExtractionError.self) { try workbook(parts) }
    }

    @Test func externalEntitiesAreNotRead() throws {
        let xml = "<!DOCTYPE s [<!ENTITY leak SYSTEM 'file:///etc/passwd'>]><s xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main'><a:t>&leak;</a:t></s>"
        #expect(try OfficeOpenXML.presentationText(Data(xml.utf8)).isEmpty)
    }

    @Test func repeatedSharedValuesCannotExpandOutputWithoutLimit() throws {
        var parts = OfficeFixtures.workbook
        parts["xl/_rels/workbook.xml.rels"] = OfficeFixtures.relationshipsWithStrings
        parts["xl/sharedStrings.xml"] = "<sst><si><t>" + String(repeating: "x", count: 1024 * 1024) + "</t></si></sst>"
        let cells = Array(repeating: "<c t=\"s\"><v>0</v></c>", count: 11).joined()
        parts["xl/worksheets/sheet1.xml"] = "<worksheet><sheetData><row>\(cells)</row></sheetData></worksheet>"
        #expect(throws: OfficeOpenXML.ExtractionError.self) { try workbook(parts) }
    }

    private func workbook(_ parts: [String: String]) throws -> String {
        try OfficeOpenXML.workbook { parts[$0].map { Data($0.utf8) } }
    }
}

/// Synthetic package parts shared by parser tests and the actual unzip integration test.
enum OfficeFixtures {
    static let relationshipsWithStrings = """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="strings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
    </Relationships>
    """
    static let workbook: [String: String] = [
        "xl/workbook.xml": "<workbook xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Test\" sheetId=\"1\" r:id=\"r1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id=\"r1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>Hello</t></is></c></row></sheetData></worksheet>"
    ]
}
