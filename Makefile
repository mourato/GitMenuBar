.PHONY: help build build-release test lint lint-changed lint-fix check-preview agent-check validate validate-lane validate-lane-command guidance-check install-app dmg clean setup

PROJECT_DIR := $(shell pwd)
AGENT_CONFIG_HOME ?= $(HOME)/.agents
VALIDATE_LANE ?= $(AGENT_CONFIG_HOME)/scripts/validate-lane
VALIDATE_BASE ?= $(shell git merge-base origin/main HEAD 2>/dev/null || git rev-parse HEAD^)
VALIDATE_ARTIFACT_ROOTS := .xcode-build/Build
VALIDATE_ARTIFACT_ARGS := $(foreach root,$(VALIDATE_ARTIFACT_ROOTS),--artifacts "$(PROJECT_DIR)/$(root)")

help:
	@echo "GitMenuBar Development Commands"
	@echo "==============================="
	@echo "make build         Build Debug app"
	@echo "make build-release Build Release app"
	@echo "make test          Run XCTest suite"
	@echo "make lint          Run SwiftFormat/SwiftLint checks"
	@echo "make lint-changed  Lint only files changed since HEAD"
	@echo "make lint-fix      Auto-fix format/lint issues"
	@echo "make check-preview Check changed UI files for SwiftUI preview coverage"
	@echo "make agent-check   Lint changed Swift files and build Debug app"
	@echo "make validate      Canonical changed-surface validation"
	@echo "make validate-lane Run validate through the global baseline/artifact gate"
	@echo "make guidance-check Validate agent guidance, plans, and skill references"
	@echo "make install-app   Build Release and replace the installed app interactively"
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

lint-changed:
	@FILES=$$(./scripts/changed-swift-files.sh); \
	if [ -z "$$FILES" ]; then \
		echo "No changed Swift files to lint"; \
	else \
		./scripts/lint.sh $$FILES; \
	fi

check-preview:
	@./scripts/check-preview.sh

agent-check: lint-changed build

validate: agent-check

validate-lane:
	@$(VALIDATE_LANE) --repo "$(PROJECT_DIR)" --base "$(VALIDATE_BASE)" $(VALIDATE_ARTIFACT_ARGS) -- $(MAKE) validate-lane-command

validate-lane-command:
	@set -eu; \
		build_existed=0; \
		if [ -e "$(PROJECT_DIR)/.xcode-build" ] || [ -L "$(PROJECT_DIR)/.xcode-build" ]; then build_existed=1; fi; \
		cleanup() { \
			if [ "$$build_existed" -eq 0 ]; then rm -rf "$(PROJECT_DIR)/.xcode-build"; fi; \
		}; \
		trap cleanup EXIT; \
		$(MAKE) validate

guidance-check:
	@./scripts/validate-agent-guidance.sh

install-app:
	@./scripts/build-and-run.sh

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
