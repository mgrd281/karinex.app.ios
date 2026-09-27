# KARINEX iOS developer commands. Run `make help` for the list.
#
# Most targets need macOS with Xcode. `test-packages`, `lint`, `format`, `check` and
# `fixtures` also work on Linux with a Swift toolchain (DesignSystem then builds only the
# pure-Swift DesignTokens target).

# Recipes that pipe xcodebuild through tee/xcbeautify start with `set -eo pipefail` themselves,
# because macOS ships GNU Make 3.81, which ignores .SHELLFLAGS.
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

# MARK: - Configuration

PROJECT ?= KARINEX.xcodeproj
SCHEME ?= KARINEX
CONFIGURATION ?= Debug
DERIVED_DATA ?= build/DerivedData
RESULTS_DIR ?= build/results
PACKAGES := Packages/Core Packages/ShopifyKit Packages/DesignSystem
FIXTURES_DIR := Packages/ShopifyKit/Tests/ShopifyKitTests/Fixtures
SNAPSHOTS_DIR := Packages/DesignSystem/Tests/DesignSystemTests/__Snapshots__

# Pinned tool versions (kept in sync with scripts/install-tools.sh and CI).
SWIFTFORMAT_VERSION := 0.63.0
SWIFTLINT_VERSION := 0.65.1
XCODEGEN_VERSION := 2.46.0

# Tools resolve to `make tools` installs first, then to PATH (Homebrew).
TOOLS_BIN := $(CURDIR)/build/tools/bin
SWIFTFORMAT ?= $(firstword $(wildcard $(TOOLS_BIN)/swiftformat) swiftformat)
SWIFTLINT ?= $(firstword $(wildcard $(TOOLS_BIN)/swiftlint) swiftlint)
XCODEGEN ?= $(firstword $(wildcard $(TOOLS_BIN)/xcodegen) xcodegen)
PYTHON ?= python3

UNAME_S := $(shell uname -s)
# Pretty-prints xcodebuild output when xcbeautify is installed; plain output otherwise.
XCBEAUTIFY := $(shell command -v xcbeautify >/dev/null 2>&1 && echo "xcbeautify" || echo "cat")

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) \
	-derivedDataPath $(DERIVED_DATA)
# Tests and snapshot references run in German (the source language), exactly like CI.
TEST_LOCALE := -testLanguage de -testRegion DE

# Resolves the simulator lazily (only in recipes that need it). Override with
# `make test SIMULATOR_ID=<udid>` or `KX_SIMULATOR_NAME="iPhone 16" make test`.
SIMULATOR_ID ?=
resolve_simulator = sim="$(SIMULATOR_ID)"; if [[ -z "$$sim" ]]; then sim="$$(scripts/select-simulator.sh)"; fi

.PHONY: help bootstrap tools project build test test-packages lint format fixtures snapshots check clean

# MARK: - Setup

help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z_-]+:.*## / { printf "  \033[1m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

bootstrap: ## Install xcodegen, swiftlint, swiftformat, xcbeautify (Homebrew) and create Config/Secrets.xcconfig
	@if [[ "$(UNAME_S)" == "Darwin" ]]; then \
		if ! command -v brew >/dev/null 2>&1; then \
			echo "error: Homebrew is required (https://brew.sh), or run 'make tools' for pinned binaries." >&2; exit 1; \
		fi; \
		for tool in xcodegen swiftlint swiftformat xcbeautify; do \
			if command -v "$$tool" >/dev/null 2>&1; then echo "$$tool: installed"; \
			else echo "Installing $$tool"; brew install "$$tool"; fi; \
		done; \
	else \
		echo "Not on macOS: skipping Homebrew. Run 'make tools' to install pinned SwiftFormat and SwiftLint."; \
	fi
	@$(MAKE) --no-print-directory check-tool-versions
	@if [[ ! -f Config/Secrets.xcconfig ]]; then \
		cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig; \
		echo "Created Config/Secrets.xcconfig from the example (git-ignored). Fill in your values."; \
	else \
		echo "Config/Secrets.xcconfig exists: left unchanged."; \
	fi

tools: ## Install the pinned SwiftFormat, SwiftLint (and XcodeGen on macOS) into build/tools
	@scripts/install-tools.sh --dir build/tools

.PHONY: check-tool-versions
check-tool-versions:
	@check() { \
		local name="$$1" binary="$$2" pinned="$$3" actual; \
		if ! command -v "$$binary" >/dev/null 2>&1; then echo "warning: $$name not found (pinned $$pinned)"; return 0; fi; \
		actual="$$("$$binary" --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"; \
		if [[ "$$actual" != "$$pinned" ]]; then \
			echo "warning: $$name $$actual differs from the pinned $$pinned used by CI; run 'make tools' for exact results."; \
		fi; \
	}; \
	check SwiftFormat "$(SWIFTFORMAT)" "$(SWIFTFORMAT_VERSION)"; \
	check SwiftLint "$(SWIFTLINT)" "$(SWIFTLINT_VERSION)"; \
	if [[ "$(UNAME_S)" == "Darwin" ]]; then check XcodeGen "$(XCODEGEN)" "$(XCODEGEN_VERSION)"; fi

# MARK: - Build and test

project: ## Regenerate KARINEX.xcodeproj from project.yml (commit both)
	$(XCODEGEN) generate --spec project.yml

build: ## Build the app for the iOS Simulator
	@mkdir -p $(RESULTS_DIR)
	set -eo pipefail; $(XCODEBUILD) -destination "generic/platform=iOS Simulator" build 2>&1 \
		| tee $(RESULTS_DIR)/build.log | $(XCBEAUTIFY)
	@scripts/check-warnings.sh $(RESULTS_DIR)/build.log

test: ## Run all tests (unit, package, snapshot, UI) on an automatically chosen iPhone simulator
	@mkdir -p $(RESULTS_DIR)
	@rm -rf $(RESULTS_DIR)/test.xcresult
	@set -eo pipefail; $(resolve_simulator); \
	TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never $(XCODEBUILD) -destination "id=$$sim" $(TEST_LOCALE) \
		-enableCodeCoverage YES -resultBundlePath $(RESULTS_DIR)/test.xcresult test 2>&1 \
		| tee $(RESULTS_DIR)/test.log | $(XCBEAUTIFY)
	@scripts/check-warnings.sh $(RESULTS_DIR)/test.log

test-packages: ## swift test in Core, ShopifyKit and DesignSystem (DesignTokens; SwiftUI parts need `make test`)
	@set -eo pipefail; for package in $(PACKAGES); do \
		echo "==> $$package"; \
		if [[ "$(UNAME_S)" == "Darwin" && "$$package" == "Packages/DesignSystem" ]]; then \
			$(resolve_simulator); \
			(cd "$$package" && xcodebuild -scheme DesignSystem-Package -destination "id=$$sim" \
				-derivedDataPath ../../$(DERIVED_DATA)/DesignSystemPackage \
				-only-testing:DesignTokensTests test 2>&1 | $(XCBEAUTIFY)); \
		else \
			swift build --package-path "$$package" -Xswiftc -warnings-as-errors; \
			swift test --package-path "$$package"; \
		fi; \
	done

# MARK: - Quality

lint: ## SwiftFormat --lint and SwiftLint --strict (what CI runs)
	@$(MAKE) --no-print-directory check-tool-versions
	$(SWIFTFORMAT) --lint .
	$(SWIFTLINT) lint --strict --quiet

format: ## Apply SwiftLint autocorrections and SwiftFormat
	$(SWIFTLINT) lint --fix --quiet
	$(SWIFTFORMAT) .

check: ## Validate String Catalogs (11 languages) and the copy rules
	$(PYTHON) scripts/check_strings.py
	$(PYTHON) scripts/check_copy_rules.py

# MARK: - Data

fixtures: ## Re-record the Storefront fixtures from the live store (tokenless unless KX_STOREFRONT_TOKEN is set)
	cd Tools/FixtureRecorder && swift run fixture-recorder --output ../../$(FIXTURES_DIR)
	@echo "Fixtures written to $(FIXTURES_DIR). Run 'make test-packages' and review the diff."

snapshots: ## Record DesignSystem snapshot references locally (recording reports failures; review the PNGs)
	@mkdir -p $(RESULTS_DIR)
	@rm -rf $(RESULTS_DIR)/snapshots.xcresult
	@set -eo pipefail; $(resolve_simulator); \
	status=0; \
	TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all $(XCODEBUILD) -destination "id=$$sim" $(TEST_LOCALE) \
		-resultBundlePath $(RESULTS_DIR)/snapshots.xcresult -only-testing:DesignSystemTests test 2>&1 \
		| tee $(RESULTS_DIR)/snapshots.log | $(XCBEAUTIFY) || status=$$?; \
	echo "Recording finished (xcodebuild exit $$status; failures are expected while recording)."; \
	git status --short -- $(SNAPSHOTS_DIR)

# MARK: - Housekeeping

clean: ## Remove derived data, results and SwiftPM build directories (keeps build/tools)
	rm -rf $(DERIVED_DATA) $(RESULTS_DIR) .spm
	rm -rf $(addsuffix /.build,$(PACKAGES)) Packages/Features/.build Tools/FixtureRecorder/.build
