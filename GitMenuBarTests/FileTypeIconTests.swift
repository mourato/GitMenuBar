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

    func testHiddenConfigFilesMapToConfigKind() {
        for path in [".gitignore", ".gitattributes", ".swiftformat", ".swiftlint.yml"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .config, "Expected config kind for \(path)")
            XCTAssertEqual(descriptor.fallbackSymbolName, "doc.badge.gearshape")
        }
    }

    func testSourceCodeExtensionsMapToSourceCodeKind() {
        for path in ["src/app.ts", "src/view.tsx", "scripts/tool.py", "cmd/main.go", "Sources/App.kt"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .sourceCode, "Expected sourceCode kind for \(path)")
            XCTAssertEqual(descriptor.artwork, .system("curlybraces"))
            XCTAssertEqual(descriptor.fallbackSymbolName, "curlybraces")
        }
    }

    func testWebExtensionsMapToWebKind() {
        let descriptor = FileTypeIcon.resolve(for: "public/index.html")

        XCTAssertEqual(descriptor.kind, .web)
        XCTAssertEqual(descriptor.artwork, .system("globe"))
        XCTAssertEqual(descriptor.fallbackSymbolName, "globe")
    }

    func testStylesheetExtensionsMapToStylesheetKind() {
        for path in ["styles/app.css", "styles/theme.scss"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .stylesheet, "Expected stylesheet kind for \(path)")
            XCTAssertEqual(descriptor.artwork, .system("number"))
            XCTAssertEqual(descriptor.fallbackSymbolName, "number")
        }
    }

    func testPackageFilesMapToPackageKind() {
        for path in ["package.json", "Gemfile", "Podfile"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .package, "Expected package kind for \(path)")
            XCTAssertEqual(descriptor.artwork, .system("shippingbox"))
            XCTAssertEqual(descriptor.fallbackSymbolName, "shippingbox")
        }
    }

    func testLockfilesMapToPackageKind() {
        for path in ["Package.resolved", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Gemfile.lock"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .package, "Expected package kind for \(path)")
            XCTAssertEqual(descriptor.artwork, .system("lock"))
            XCTAssertEqual(descriptor.fallbackSymbolName, "lock")
        }
    }

    func testXcodeProjectFilesMapToXcodeProjectKind() {
        for path in ["project.pbxproj", "GitMenuBar.xcscheme", "contents.xcworkspacedata"] {
            let descriptor = FileTypeIcon.resolve(for: path)
            XCTAssertEqual(descriptor.kind, .xcodeProject, "Expected xcodeProject kind for \(path)")
            XCTAssertEqual(descriptor.artwork, .system("hammer"))
            XCTAssertEqual(descriptor.fallbackSymbolName, "hammer")
        }
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
