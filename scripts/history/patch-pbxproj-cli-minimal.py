#!/usr/bin/env python3
# DO NOT RE-RUN — one-shot migration script; archival after Companion CLI removal (2026-08-24).
# GitMenuBar.xcodeproj is the source of truth.
"""Minimal CLI target patch: GitMenuBarCLI folder only (no shared Services yet)."""
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "GitMenuBar.xcodeproj/project.pbxproj"
text = p.read_text()


def rep(old, new, label):
    global text
    if old not in text:
        raise SystemExit(f"missing {label}")
    text = text.replace(old, new, 1)


rep(
    "/* End PBXBuildFile section */",
    "\t\tD5E6F7082F33333300ABC001 /* ArgumentParser in Frameworks */ = {isa = PBXBuildFile; productRef = D5E6F7082F33333300ABC003 /* ArgumentParser */; };\n"
    "/* End PBXBuildFile section */",
    "buildfiles",
)
rep(
    "/* End PBXFileReference section */",
    "\t\tD5E6F7082F33333300ABC011 /* gitmenubar */ = {isa = PBXFileReference; explicitFileType = \"compiled.mach-o.executable\"; includeInIndex = 0; path = gitmenubar; sourceTree = BUILT_PRODUCTS_DIR; };\n"
    "/* End PBXFileReference section */",
    "fileref",
)
rep(
    "/* End PBXFileSystemSynchronizedRootGroup section */",
    "\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */ = {\n"
    "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
    "\t\t\tpath = GitMenuBarCLI;\n"
    "\t\t\tsourceTree = \"<group>\";\n"
    "\t\t};\n"
    "/* End PBXFileSystemSynchronizedRootGroup section */",
    "cliroot",
)
rep(
    "/* End PBXFrameworksBuildPhase section */",
    "\t\tD5E6F7082F33333300ABC014 /* Frameworks */ = {\n"
    "\t\t\tisa = PBXFrameworksBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t\tD5E6F7082F33333300ABC001 /* ArgumentParser in Frameworks */,\n"
    "\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t};\n"
    "/* End PBXFrameworksBuildPhase section */",
    "frameworks",
)
rep(
    "\t\t\t\t1F8681CE2EBCB5B600C300C7 /* GitMenuBar */,\n"
    "\t\t\t\t2A0000012F00000100000002 /* GitMenuBarTests */,",
    "\t\t\t\t1F8681CE2EBCB5B600C300C7 /* GitMenuBar */,\n"
    "\t\t\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */,\n"
    "\t\t\t\t2A0000012F00000100000002 /* GitMenuBarTests */,",
    "maingroup",
)
rep(
    "\t\t\t\t1F8681CC2EBCB5B600C300C7 /* GitMenuBar.app */,\n"
    "\t\t\t\t2A0000012F00000100000001 /* GitMenuBarTests.xctest */,",
    "\t\t\t\t1F8681CC2EBCB5B600C300C7 /* GitMenuBar.app */,\n"
    "\t\t\t\tD5E6F7082F33333300ABC011 /* gitmenubar */,\n"
    "\t\t\t\t2A0000012F00000100000001 /* GitMenuBarTests.xctest */,",
    "products",
)
rep(
    "/* End PBXNativeTarget section */",
    "\t\tD5E6F7082F33333300ABC010 /* gitmenubar */ = {\n"
    "\t\t\tisa = PBXNativeTarget;\n"
    "\t\t\tbuildConfigurationList = D5E6F7082F33333300ABC01C /* Build configuration list for PBXNativeTarget \"gitmenubar\" */;\n"
    "\t\t\tbuildPhases = (\n"
    "\t\t\t\tD5E6F7082F33333300ABC013 /* Sources */,\n"
    "\t\t\t\tD5E6F7082F33333300ABC014 /* Frameworks */,\n"
    "\t\t\t);\n"
    "\t\t\tbuildRules = (\n"
    "\t\t\t);\n"
    "\t\t\tdependencies = (\n"
    "\t\t\t);\n"
    "\t\t\tfileSystemSynchronizedGroups = (\n"
    "\t\t\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */,\n"
    "\t\t\t);\n"
    "\t\t\tname = gitmenubar;\n"
    "\t\t\tpackageProductDependencies = (\n"
    "\t\t\t\tD5E6F7082F33333300ABC003 /* ArgumentParser */,\n"
    "\t\t\t);\n"
    "\t\t\tproductName = gitmenubar;\n"
    "\t\t\tproductReference = D5E6F7082F33333300ABC011 /* gitmenubar */;\n"
    "\t\t\tproductType = \"com.apple.product-type.tool\";\n"
    "\t\t};\n"
    "/* End PBXNativeTarget section */",
    "cli target",
)
rep(
    "\t\t\tpackageReferences = (\n"
    "\t\t\t\tA1B2C3D42F11111100ABC002 /* XCRemoteSwiftPackageReference \"KeyboardShortcuts\" */,\n"
    "\t\t\t\tC4D5E6F72F22222200ABC002 /* XCRemoteSwiftPackageReference \"Settings\" */,\n"
    "\t\t\t);",
    "\t\t\tpackageReferences = (\n"
    "\t\t\t\tA1B2C3D42F11111100ABC002 /* XCRemoteSwiftPackageReference \"KeyboardShortcuts\" */,\n"
    "\t\t\t\tC4D5E6F72F22222200ABC002 /* XCRemoteSwiftPackageReference \"Settings\" */,\n"
    "\t\t\t\tD5E6F7082F33333300ABC002 /* XCRemoteSwiftPackageReference \"swift-argument-parser\" */,\n"
    "\t\t\t);",
    "pkgrefs",
)
rep(
    "\t\t\ttargets = (\n"
    "\t\t\t\t1F8681CB2EBCB5B600C300C7 /* GitMenuBar */,\n"
    "\t\t\t\t2A0000012F00000100000006 /* GitMenuBarTests */,\n"
    "\t\t\t);",
    "\t\t\ttargets = (\n"
    "\t\t\t\t1F8681CB2EBCB5B600C300C7 /* GitMenuBar */,\n"
    "\t\t\t\tD5E6F7082F33333300ABC010 /* gitmenubar */,\n"
    "\t\t\t\t2A0000012F00000100000006 /* GitMenuBarTests */,\n"
    "\t\t\t);",
    "targets",
)
rep(
    "\t\t\t\t\t2A0000012F00000100000006 = {\n"
    "\t\t\t\t\t\tCreatedOnToolsVersion = 16.4;\n"
    "\t\t\t\t\t};\n"
    "\t\t\t\t};",
    "\t\t\t\t\t2A0000012F00000100000006 = {\n"
    "\t\t\t\t\t\tCreatedOnToolsVersion = 16.4;\n"
    "\t\t\t\t\t};\n"
    "\t\t\t\t\tD5E6F7082F33333300ABC010 = {\n"
    "\t\t\t\t\t\tCreatedOnToolsVersion = 16.4;\n"
    "\t\t\t\t\t};\n"
    "\t\t\t\t};",
    "target attrs",
)
rep(
    "/* End PBXSourcesBuildPhase section */",
    "\t\tD5E6F7082F33333300ABC013 /* Sources */ = {\n"
    "\t\t\tisa = PBXSourcesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
    "\t\t};\n"
    "/* End PBXSourcesBuildPhase section */",
    "sources",
)
rep(
    "/* End XCBuildConfiguration section */",
    "\t\tD5E6F7082F33333300ABC01D /* Debug */ = {\n"
    "\t\t\tisa = XCBuildConfiguration;\n"
    "\t\t\tbuildSettings = {\n"
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
    "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
    "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.5;\n"
    "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.mourato.GitMenuBar.gitmenubar;\n"
    "\t\t\t\tPRODUCT_NAME = gitmenubar;\n"
    "\t\t\t\tSWIFT_VERSION = 5.0;\n"
    "\t\t\t};\n"
    "\t\t\tname = Debug;\n"
    "\t\t};\n"
    "\t\tD5E6F7082F33333300ABC01E /* Release */ = {\n"
    "\t\t\tisa = XCBuildConfiguration;\n"
    "\t\t\tbuildSettings = {\n"
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
    "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
    "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.5;\n"
    "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.mourato.GitMenuBar.gitmenubar;\n"
    "\t\t\t\tPRODUCT_NAME = gitmenubar;\n"
    "\t\t\t\tSWIFT_VERSION = 5.0;\n"
    "\t\t\t};\n"
    "\t\t\tname = Release;\n"
    "\t\t};\n"
    "/* End XCBuildConfiguration section */",
    "cfg",
)
rep(
    "/* End XCConfigurationList section */",
    "\t\tD5E6F7082F33333300ABC01C /* Build configuration list for PBXNativeTarget \"gitmenubar\" */ = {\n"
    "\t\t\tisa = XCConfigurationList;\n"
    "\t\t\tbuildConfigurations = (\n"
    "\t\t\t\tD5E6F7082F33333300ABC01D /* Debug */,\n"
    "\t\t\t\tD5E6F7082F33333300ABC01E /* Release */,\n"
    "\t\t\t);\n"
    "\t\t\tdefaultConfigurationIsVisible = 0;\n"
    "\t\t\tdefaultConfigurationName = Release;\n"
    "\t\t};\n"
    "/* End XCConfigurationList section */",
    "cfglist",
)
rep(
    "/* End XCRemoteSwiftPackageReference section */",
    "\t\tD5E6F7082F33333300ABC002 /* XCRemoteSwiftPackageReference \"swift-argument-parser\" */ = {\n"
    "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
    "\t\t\trepositoryURL = \"https://github.com/apple/swift-argument-parser\";\n"
    "\t\t\trequirement = {\n"
    "\t\t\t\tkind = upToNextMajorVersion;\n"
    "\t\t\t\tminimumVersion = 1.3.0;\n"
    "\t\t\t};\n"
    "\t\t};\n"
    "/* End XCRemoteSwiftPackageReference section */",
    "pkg",
)
rep(
    "/* End XCSwiftPackageProductDependency section */",
    "\t\tD5E6F7082F33333300ABC003 /* ArgumentParser */ = {\n"
    "\t\t\tisa = XCSwiftPackageProductDependency;\n"
    "\t\t\tpackage = D5E6F7082F33333300ABC002 /* XCRemoteSwiftPackageReference \"swift-argument-parser\" */;\n"
    "\t\t\tproductName = ArgumentParser;\n"
    "\t\t};\n"
    "/* End XCSwiftPackageProductDependency section */",
    "pkgprod",
)
p.write_text(text)
print("minimal patched")
