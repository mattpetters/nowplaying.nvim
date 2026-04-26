.PHONY: test test-file deps clean coverage coverage-report coverage-clean \
        go-build go-test go-test-race go-test-cover go-lint go-vet \
        nvim-test nvim-deps test-all

NVIM ?= nvim
GO ?= go
BIN_DIR ?= bin

# ----------------------------------------------------------------------------
# Top-level
# ----------------------------------------------------------------------------

test-all: go-test nvim-test

# ----------------------------------------------------------------------------
# Go (daemon + TUI)
# ----------------------------------------------------------------------------

go-build:
	$(GO) build -o $(BIN_DIR)/nowplayingd ./cmd/nowplayingd
	$(GO) build -o $(BIN_DIR)/nowplaying ./cmd/nowplaying

go-test:
	$(GO) test ./...

go-test-race:
	$(GO) test -race ./...

go-test-cover:
	$(GO) test -coverprofile=coverage.txt -covermode=atomic ./...
	$(GO) tool cover -func=coverage.txt | tail -1

go-vet:
	$(GO) vet ./...

go-lint: go-vet
	@command -v golangci-lint >/dev/null 2>&1 && golangci-lint run ./... || \
		echo "golangci-lint not installed; ran go vet only"

# ----------------------------------------------------------------------------
# Neovim plugin (existing)
# ----------------------------------------------------------------------------

nvim-deps: deps

nvim-test: test


# Bootstrap mini.nvim dependency
deps:
	@$(NVIM) --headless -u scripts/minitest.lua -c "qa!" 2>/dev/null || true

# Run all tests
test:
	$(NVIM) --headless -u scripts/minitest.lua

# Run a single test file: make test-file FILE=tests/test_panel.lua
test-file:
	$(NVIM) --headless --noplugin -u NONE \
		-c "lua vim.opt.rtp:prepend('deps/mini.nvim')" \
		-c "lua vim.opt.rtp:prepend('.')" \
		-c "lua require('mini.test').setup({})" \
		-c "lua MiniTest.run_file('$(FILE)')"

# Run tests with code coverage collection
coverage: coverage-clean
	COVERAGE=1 $(NVIM) --headless -u scripts/minitest.lua
	@$(NVIM) --headless -u NONE -l scripts/merge_coverage.lua 2>/dev/null || true
	@bash scripts/coverage.sh

# Generate report from existing stats (no test re-run)
coverage-report:
	@bash scripts/coverage.sh

# Remove coverage artifacts
coverage-clean:
	rm -f luacov.stats.out luacov.report.out

# Remove test dependencies
clean: coverage-clean
	rm -rf deps/
