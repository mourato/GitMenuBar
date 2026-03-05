.PHONY: help build build-release test lint lint-fix dmg clean setup

PROJECT_DIR := $(shell pwd)

help:
	@echo "GitMenuBar Development Commands"
	@echo "==============================="
	@echo "make build         Build Debug app"
	@echo "make build-release Build Release app"
	@echo "make test          Run XCTest suite"
	@echo "make lint          Run SwiftFormat/SwiftLint checks"
	@echo "make lint-fix      Auto-fix format/lint issues"
	@echo "make dmg           Build and package DMG"
	@echo "make clean         Remove generated artifacts"
	@echo "make setup         Install local dev dependencies"

build:
	@./scripts/run-build.sh --configuration Debug

build-release:
	@./scripts/run-build.sh --configuration Release

test:
	@./scripts/run-tests-xcode.sh

lint:
	@./scripts/lint.sh

lint-fix:
	@./scripts/lint-fix.sh

dmg:
	@./scripts/create-dmg.sh

clean:
	@rm -rf "$(PROJECT_DIR)/.xcode-build" "$(PROJECT_DIR)/.xcode-build-tests" "$(PROJECT_DIR)/dist"
	@echo "Clean complete"

setup:
	@echo "Installing SwiftLint..."
	@brew install swiftlint || true
	@echo "Installing SwiftFormat..."
	@brew install swiftformat || true
	@echo "Setup complete"
