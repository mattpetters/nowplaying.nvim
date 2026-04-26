.PHONY: test test-file deps clean coverage coverage-report coverage-clean \
        go-build go-test go-test-race go-test-cover go-lint go-vet \
        tui-iterate tui-iterate-clean \
        hermes-install hermes-uninstall \
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
# TUI visual iteration loop
# ----------------------------------------------------------------------------
# `make tui-iterate` boots a stub-provider daemon on a temp socket, runs the
# smoke tape through vhs, and writes default/matrix PNGs into tests/tui/out.
# An assistant (or human) can `Read` those PNGs to validate visual output
# without round-tripping screenshots through the user.
#
# Requires: vhs + ttyd on $PATH. `brew install vhs ttyd` if missing.

TUI_TAPE ?= tests/tui/smoke.tape
TUI_OUT  ?= tests/tui/out
TUI_SOCK ?= /tmp/nowplaying-tui-iter.sock

tui-iterate: go-build
	@command -v vhs >/dev/null 2>&1 || { echo "vhs not on PATH — brew install vhs ttyd"; exit 1; }
	@mkdir -p $(TUI_OUT)
	@rm -f $(TUI_SOCK)
	@./bin/nowplayingd -socket $(TUI_SOCK) > $(TUI_OUT)/daemon.log 2>&1 & echo $$! > $(TUI_OUT)/daemon.pid
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do \
		[ -S $(TUI_SOCK) ] && break; sleep 0.1; \
	done; \
	if [ ! -S $(TUI_SOCK) ]; then \
		echo "daemon never opened $(TUI_SOCK)"; \
		kill $$(cat $(TUI_OUT)/daemon.pid) 2>/dev/null; \
		cat $(TUI_OUT)/daemon.log; \
		exit 1; \
	fi
	@NP_SOCKET=$(TUI_SOCK) vhs $(TUI_TAPE); rc=$$?; \
	kill $$(cat $(TUI_OUT)/daemon.pid) 2>/dev/null; \
	rm -f $(TUI_OUT)/daemon.pid $(TUI_SOCK); \
	if [ $$rc -ne 0 ]; then exit $$rc; fi
	@echo "wrote $(TUI_OUT)/default.png + $(TUI_OUT)/matrix.png"

tui-iterate-clean:
	rm -rf $(TUI_OUT)

# ----------------------------------------------------------------------------
# Hermes integration (slash commands, custom skills)
# ----------------------------------------------------------------------------
# `make hermes-install` symlinks our packaged skills into ~/.hermes/skills/ so
# Hermes auto-discovers them as `/<skill-name>` slash commands. Source of
# truth lives in this repo under hermes/skills/<name>/SKILL.md — edits flow
# through this repo's normal git workflow.

HERMES_SKILLS_DIR ?= $(HOME)/.hermes/skills
HERMES_PKG_SKILLS := $(CURDIR)/hermes/skills

hermes-install:
	@mkdir -p $(HERMES_SKILLS_DIR)
	@for skill in $(HERMES_PKG_SKILLS)/*/; do \
		name=$$(basename $$skill); \
		target=$(HERMES_SKILLS_DIR)/$$name; \
		if [ -L "$$target" ]; then \
			rm "$$target"; \
		elif [ -e "$$target" ]; then \
			echo "skip $$name — $$target exists and is not a symlink"; \
			continue; \
		fi; \
		ln -s "$$skill" "$$target" && echo "linked $$name -> $$target"; \
	done

hermes-uninstall:
	@for skill in $(HERMES_PKG_SKILLS)/*/; do \
		name=$$(basename $$skill); \
		target=$(HERMES_SKILLS_DIR)/$$name; \
		if [ -L "$$target" ]; then \
			rm "$$target" && echo "unlinked $$name"; \
		fi; \
	done

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
