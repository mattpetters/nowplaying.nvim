.PHONY: test test-file deps clean

NVIM ?= nvim

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

# Remove test dependencies
clean:
	rm -rf deps/
