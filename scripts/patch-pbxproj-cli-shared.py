#!/usr/bin/env python3
"""Add gitmenubar CLI with dual-membership Services/Models/Utils roots and Copy Files into .app."""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "GitMenuBar.xcodeproj/project.pbxproj"


def rep(text, old, new, label):
    if old not in text:
        raise SystemExit(f"missing {label}")
    return text.replace(old, new, 1)


def main():
    subprocess.run(
        [sys.executable, str(ROOT / "scripts/patch-pbxproj-cli-minimal.py")],
        check=True,
    )
    text = P.read_text()

    # Copy Files creates an implicit gitmenubar dependency during test builds; use Run Script instead.

    text = rep(
        text,
        "\t\t1F31AE932EE0AB780020EDD9 /* Exceptions for \"GitMenuBar\" folder in \"GitMenuBar\" target */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
        "\t\t\tmembershipExceptions = (\n"
        "\t\t\t\tInfo.plist,\n"
        "\t\t\t);\n"
        "\t\t\ttarget = 1F8681CB2EBCB5B600C300C7 /* GitMenuBar */;\n"
        "\t\t};",
        "\t\t1F31AE932EE0AB780020EDD9 /* Exceptions for \"GitMenuBar\" folder in \"GitMenuBar\" target */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
        "\t\t\tmembershipExceptions = (\n"
        "\t\t\t\tInfo.plist,\n"
        "\t\t\t\tServices,\n"
        "\t\t\t\tModels,\n"
        "\t\t\t\tUtils,\n"
        "\t\t\t);\n"
        "\t\t\ttarget = 1F8681CB2EBCB5B600C300C7 /* GitMenuBar */;\n"
        "\t\t};\n"
        "\t\tF7A8093F33333300ABC023 /* Exceptions for CoreServices in gitmenubar */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
        "\t\t\tmembershipExceptions = (\n"
        "\t\t\t\tPlatform/KeyboardShortcutsNames.swift,\n"
        "\t\t\t);\n"
        "\t\t\ttarget = D5E6F7082F33333300ABC010 /* gitmenubar */;\n"
        "\t\t};",
        "exceptions",
    )

    text = rep(
        text,
        "\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\tpath = GitMenuBarCLI;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        "\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\tpath = GitMenuBarCLI;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "\t\tF7A8093F33333300ABC016 /* CoreServices */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\texceptions = (\n"
        "\t\t\t\tF7A8093F33333300ABC023 /* Exceptions for CoreServices in gitmenubar */,\n"
        "\t\t\t);\n"
        "\t\t\tpath = GitMenuBar/Services;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "\t\tF7A8093F33333300ABC017 /* CoreModels */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\tpath = GitMenuBar/Models;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "\t\tF7A8093F33333300ABC018 /* CoreUtils */ = {\n"
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\tpath = GitMenuBar/Utils;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        "shared roots",
    )

    text = rep(
        text,
        "\t\t\tbuildPhases = (\n"
        "\t\t\t\t1F8681C82EBCB5B600C300C7 /* Sources */,\n"
        "\t\t\t\t1F8681C92EBCB5B600C300C7 /* Frameworks */,\n"
        "\t\t\t\t1F8681CA2EBCB5B600C300C7 /* Resources */,\n"
        "\t\t\t);",
        "\t\t\tbuildPhases = (\n"
        "\t\t\t\t1F8681C82EBCB5B600C300C7 /* Sources */,\n"
        "\t\t\t\t1F8681C92EBCB5B600C300C7 /* Frameworks */,\n"
        "\t\t\t\t1F8681CA2EBCB5B600C300C7 /* Resources */,\n"
        "\t\t\t\tD5E6F7082F33333300ABC012 /* Bundle gitmenubar */,\n"
        "\t\t\t);",
        "app copy phase list",
    )

    text = rep(
        text,
        "\t\t\tfileSystemSynchronizedGroups = (\n"
        "\t\t\t\t1F8681CE2EBCB5B600C300C7 /* GitMenuBar */,",
        "\t\t\tfileSystemSynchronizedGroups = (\n"
        "\t\t\t\t1F8681CE2EBCB5B600C300C7 /* GitMenuBar */,\n"
        "\t\t\t\tF7A8093F33333300ABC016 /* CoreServices */,\n"
        "\t\t\t\tF7A8093F33333300ABC017 /* CoreModels */,\n"
        "\t\t\t\tF7A8093F33333300ABC018 /* CoreUtils */,",
        "app shared groups",
        1,
    )

    text = rep(
        text,
        "\t\t\tfileSystemSynchronizedGroups = (\n"
        "\t\t\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */,\n"
        "\t\t\t);\n"
        "\t\t\tname = gitmenubar;",
        "\t\t\tfileSystemSynchronizedGroups = (\n"
        "\t\t\t\tD5E6F7082F33333300ABC015 /* GitMenuBarCLI */,\n"
        "\t\t\t\tF7A8093F33333300ABC016 /* CoreServices */,\n"
        "\t\t\t\tF7A8093F33333300ABC017 /* CoreModels */,\n"
        "\t\t\t\tF7A8093F33333300ABC018 /* CoreUtils */,\n"
        "\t\t\t);\n"
        "\t\t\tname = gitmenubar;",
        "cli groups",
    )

    text = rep(
        text,
        "/* End PBXResourcesBuildPhase section */",
        "/* End PBXResourcesBuildPhase section */\n\n"
        "/* Begin PBXShellScriptBuildPhase section */\n"
        "\t\tD5E6F7082F33333300ABC012 /* Bundle gitmenubar */ = {\n"
        "\t\t\tisa = PBXShellScriptBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t);\n"
        "\t\t\tinputPaths = (\n"
        "\t\t\t);\n"
        "\t\t\tname = \"Bundle gitmenubar\";\n"
        "\t\t\toutputPaths = (\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t\tshellPath = /bin/sh;\n"
        "\t\t\tshellScript = \"CLI=\\\"${BUILD_DIR}/${CONFIGURATION}/gitmenubar\\\"\\nDEST=\\\"${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/../MacOS/gitmenubar\\\"\\nif [ -f \\\"${CLI}\\\" ]; then\\n  /bin/cp \\\"${CLI}\\\" \\\"${DEST}\\\"\\n  /bin/chmod +x \\\"${DEST}\\\"\\nfi\\n\";\n"
        "\t\t};\n"
        "/* End PBXShellScriptBuildPhase section */",
        "bundle script",
    )

    text = rep(
        text,
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
        "\t\t};",
        "\t\tD5E6F7082F33333300ABC01D /* Debug */ = {\n"
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
        "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.5;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.mourato.GitMenuBar.gitmenubar;\n"
        "\t\t\t\tPRODUCT_NAME = gitmenubar;\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        "\t\t\t\tSWIFT_STRICT_CONCURRENCY = targeted;\n"
        "\t\t\t\tSWIFT_VERSION = 5.0;\n"
        "\t\t\t};\n"
        "\t\t\tname = Debug;\n"
        "\t\t};",
        "cli debug cfg",
    )

    text = rep(
        text,
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
        "\t\t};",
        "\t\tD5E6F7082F33333300ABC01E /* Release */ = {\n"
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tENABLE_HARDENED_RUNTIME = YES;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
        "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.5;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.mourato.GitMenuBar.gitmenubar;\n"
        "\t\t\t\tPRODUCT_NAME = gitmenubar;\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        "\t\t\t\tSWIFT_VERSION = 5.0;\n"
        "\t\t\t};\n"
        "\t\t\tname = Release;\n"
        "\t\t};",
        "cli release cfg",
    )

    P.write_text(text)
    print("shared cli patched")


if __name__ == "__main__":
    main()
