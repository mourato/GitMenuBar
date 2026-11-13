import AppKit
@testable import GitMenuBar
import SwiftUI
import XCTest

@MainActor
final class LucideIconTests: XCTestCase {
    private var lucideDirectory: URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GitMenuBar/Resources/LucideIcons", isDirectory: true)
    }

    func testEveryCaseHasAVendoredSVG() {
        XCTAssertFalse(LucideIconName.allCases.isEmpty)

        for name in LucideIconName.allCases {
            let file = lucideDirectory.appendingPathComponent("\(name.rawValue).svg")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: file.path),
                "Missing vendored SVG for \(name.rawValue); run scripts/sync-lucide-icons.sh"
            )
        }
    }

    func testEveryVendoredSVGHasACatalogCase() {
        let files = try? FileManager.default.contentsOfDirectory(
            at: lucideDirectory,
            includingPropertiesForKeys: nil
        )
        let svgNames = (files ?? []).filter { $0.pathExtension == "svg" }.map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertFalse(svgNames.isEmpty)

        let cataloged = Set(LucideIconName.allCases.map(\.rawValue))
        for svg in svgNames {
            XCTAssertTrue(cataloged.contains(svg), "Vendored \(svg).svg has no LucideIconName case")
        }
    }

    func testRawValuesAreUniqueKebabCaseFileNames() {
        let rawValues = LucideIconName.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)

        for raw in rawValues {
            XCTAssertFalse(raw.isEmpty)
            XCTAssertNil(raw.range(of: #"[^a-z0-9-]"#, options: .regularExpression), "Unexpected characters in \(raw)")
        }
    }

    func testVendoredSVGsRenderAsImages() {
        for name in LucideIconName.allCases {
            let file = lucideDirectory.appendingPathComponent("\(name.rawValue).svg")
            guard let data = try? Data(contentsOf: file),
                  let text = String(bytes: data, encoding: .utf8)
            else {
                XCTFail("Cannot read \(name.rawValue).svg as UTF-8")
                continue
            }
            XCTAssertTrue(text.contains("<svg"), "\(name.rawValue).svg is not SVG")
            XCTAssertTrue(text.contains(#"viewBox="0 0 24 24""#), "\(name.rawValue).svg is not a 24-grid Lucide icon")
            XCTAssertNotNil(NSImage(data: data), "\(name.rawValue).svg does not decode with NSImage")
        }
    }

    func testNSImageLucideLoadsTemplateImages() {
        for name in LucideIconName.allCases {
            guard let image = NSImage(lucide: name) else {
                XCTFail("NSImage(lucide:) returned nil for \(name.rawValue)")
                continue
            }
            XCTAssertTrue(image.isTemplate, "\(name.rawValue) should render as a template image")
            XCTAssertEqual(image.size, NSSize(width: LucideIconView.defaultSize, height: LucideIconView.defaultSize))
        }
    }

    func testLabelLucideHelperUsesCatalogIcon() {
        let label = Label(lucide: .search, "Search")
        let icons = lucideIcons(in: label.body)
        XCTAssertEqual(icons.map(\.name), [.search])
        XCTAssertEqual(icons.map(\.size), [LucideIconView.defaultSize])
    }

    private func lucideIcons(in value: Any, depth: Int = 0) -> [LucideIconView] {
        guard depth < 8 else {
            return []
        }
        if let icon = value as? LucideIconView {
            return [icon]
        }
        return Mirror(reflecting: value).children.flatMap { lucideIcons(in: $0.value, depth: depth + 1) }
    }
}
