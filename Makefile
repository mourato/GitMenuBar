.PHONY: help build build-release test test-focused lint lint-changed lint-fix check-preview agent-check validate validate-lane validate-lane-command guidance-check install-app dmg clean setup

PROJECT_DIR := $(shell pwd)
AGENT_CONFIG_HOME ?= $(HOME)/.agents
VALIDATE_LANE ?= $(AGENT_CONFIG_HOME)/scripts/validate-lane
VALIDATE_BASE ?= $(shell git merge-base origin/main HEAD 2>/dev/null || git rev-parse HEAD^)
VALIDATE_TARGET ?= validate
TEST_FILTER ?=

help:
	@echo "GitMenuBar Development Commands"
	@echo "==============================="
	@echo "make build         Build Debug app"
	@echo "make build-release Build Release app"
	@echo "make test          Run XCTest suite (TEST_FILTER=... for one target)"
	@echo "make test-focused  Run one XCTest target (TEST_FILTER=... required)"
	@echo "make lint          Run SwiftFormat/SwiftLint checks"
	@echo "make lint-changed  Lint only files changed since HEAD"
	@echo "make lint-fix      Auto-fix format/lint issues"
	@echo "make check-preview Check changed UI files for SwiftUI preview coverage"
	@echo "make agent-check   Lint changed Swift files and build Debug app"
	@echo "make validate      Canonical changed-surface validation"
	@echo "make validate-lane Run target through the global baseline/artifact gate"
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
	@TEST_FILTER="$(TEST_FILTER)" ./scripts/run-tests-xcode.sh

test-focused:
	@test -n "$(strip $(TEST_FILTER))" || { echo "TEST_FILTER is required, e.g. TEST_FILTER=GitMenuBarTests/SomeTests" >&2; exit 2; }
	@TEST_FILTER="$(TEST_FILTER)" $(MAKE) test

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
	@set -eu; \
		artifact_parent="$(PROJECT_DIR)/.xcode-build"; \
		parent_existed=0; \
		if [ -e "$$artifact_parent" ] || [ -L "$$artifact_parent" ]; then parent_existed=1; fi; \
		mkdir -p "$$artifact_parent"; \
		derived_data="$$(mktemp -d "$$artifact_parent/validate-lane.XXXXXX")"; \
		cleanup() { \
			rm -rf "$$derived_data"; \
			if [ "$$parent_existed" -eq 0 ]; then rmdir "$$artifact_parent" 2>/dev/null || true; fi; \
		}; \
		trap cleanup EXIT; \
		$(VALIDATE_LANE) --repo "$(PROJECT_DIR)" --base "$(VALIDATE_BASE)" --artifacts "$$derived_data/Build" -- $(MAKE) validate-lane-command VALIDATE_DERIVED_DATA_PATH="$$derived_data" VALIDATE_TARGET="$(VALIDATE_TARGET)" TEST_FILTER="$(TEST_FILTER)"

validate-lane-command:
	@set -eu; \
		derived_data="$(VALIDATE_DERIVED_DATA_PATH)"; \
		[ -n "$$derived_data" ] || { echo "VALIDATE_DERIVED_DATA_PATH is required" >&2; exit 2; }; \
		cleanup() { rm -rf "$$derived_data"; }; \
		trap cleanup EXIT; \
		VALIDATE_DERIVED_DATA_PATH="$$derived_data" $(MAKE) "$(VALIDATE_TARGET)" TEST_FILTER="$(TEST_FILTER)"

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
