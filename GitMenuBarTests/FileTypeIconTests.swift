@testable import GitMenuBar
import XCTest

final class FileTypeIconTests: XCTestCase {
    func testSwiftExtensionMapsToSwiftKind() {
        let descriptor = FileTypeIcon.resolve(for: "Sources/App.swift")

        XCTAssertEqual(descriptor.kind, .swift)
        XCTAssertEqual(descriptor.artwork, .pierre("swift"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "swift")
    }

    func testPackageSwiftUsesSwiftKind() {
        let descriptor = FileTypeIcon.resolve(for: "Package.swift")

        XCTAssertEqual(descriptor.kind, .swift)
        XCTAssertEqual(descriptor.artwork, .pierre("swift"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "swift")
    }

    func testMarkdownExtensionMapsToMarkdownKind() {
        let descriptor = FileTypeIcon.resolve(for: "docs/README.md")

        XCTAssertEqual(descriptor.kind, .markdown)
        XCTAssertEqual(descriptor.artwork, .pierre("markdown"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "doc.richtext")
    }

    func testMarkdownVariantExtensionMapsToMarkdownKind() {
        let descriptor = FileTypeIcon.resolve(for: "Guide.markdown")

        XCTAssertEqual(descriptor.kind, .markdown)
        XCTAssertEqual(descriptor.artwork, .pierre("markdown"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "doc.richtext")
    }

    func testJSONExtensionMapsToJSONKind() {
        let descriptor = FileTypeIcon.resolve(for: "config.json")

        XCTAssertEqual(descriptor.kind, .json)
        XCTAssertEqual(descriptor.artwork, .pierre("json"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "curlybraces")
    }

    func testYAMLExtensionsMapToYAMLKind() {
        let descriptor = FileTypeIcon.resolve(for: "config.yaml")

        XCTAssertEqual(descriptor.kind, .yaml)
        XCTAssertEqual(FileTypeIcon.resolve(for: "config.yml").kind, .yaml)
        XCTAssertEqual(descriptor.artwork, .pierre("json"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "curlybraces")
    }

    func testShellExtensionsMapToShellKind() {
        for path in ["scripts/build.sh", "profile.bash", "local.zsh"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .shell, "Expected shell kind for \(path)")
            XCTAssertEqual(descriptor.artwork, .pierre("bash"))
            XCTAssertEqual(descriptor.fallbackSymbolName, "terminal")
        }
    }

    func testImageExtensionsMapToImageKind() {
        let descriptor = FileTypeIcon.resolve(for: "Assets/logo.png")

        XCTAssertEqual(descriptor.kind, .image)
        XCTAssertEqual(descriptor.artwork, .pierre("image"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "photo")
    }

    func testUnknownExtensionMapsToGenericKind() {
        let descriptor = FileTypeIcon.resolve(for: "notes.foo")

        XCTAssertEqual(descriptor.kind, .generic)
        XCTAssertEqual(descriptor.artwork, .pierre("default"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "doc")
    }

    func testMakefileMapsToConfigKind() {
        let descriptor = FileTypeIcon.resolve(for: "Makefile")

        XCTAssertEqual(descriptor.kind, .config)
        XCTAssertEqual(descriptor.artwork, .pierre("default"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "doc.badge.gearshape")
    }

    func testDockerfileMapsToConfigKind() {
        let descriptor = FileTypeIcon.resolve(for: "Dockerfile")

        XCTAssertEqual(descriptor.kind, .config)
        XCTAssertEqual(descriptor.artwork, .pierre("default"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "doc.badge.gearshape")
    }

    func testDirectoryIconNameReflectsExpansion() {
        XCTAssertEqual(FileTypeIcon.directoryIconName(isExpanded: false), "folder")
        XCTAssertEqual(FileTypeIcon.directoryIconName(isExpanded: true), "folder.fill")
    }

    func testLightAndDarkColorsDifferForSwift() {
        let descriptor = FileTypeIcon.resolve(for: "App.swift")

        XCTAssertNotEqual(descriptor.lightColor, descriptor.darkColor)
        XCTAssertEqual(descriptor.color(for: .light), descriptor.lightColor)
        XCTAssertEqual(descriptor.color(for: .dark), descriptor.darkColor)
        XCTAssertEqual(descriptor.hexColor(for: .light), "#D47628")
        XCTAssertEqual(descriptor.hexColor(for: .dark), "#FFA359")
    }
}
