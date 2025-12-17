# Contributing to NowPlaying.nvim 🎶

Thanks for helping improve this plugin! Please follow these guidelines to keep changes easy to review and ship. 🙏

## Getting Started 🚀

- Use Neovim 0.8+ and macOS for AppleScript providers. For artwork, install ImageMagick and [image.nvim](https://github.com/3rd/image.nvim).
- Clone the repo and install dependencies for your config (e.g., Lazy.nvim installs image.nvim).
- Run basic checks locally before opening a PR.

## Development Workflow 🛠️

1. Fork/branch from `main`.
2. Keep changes focused and small; one feature or fix per PR.
3. Add/update docs when you change behavior (README, doc/nowplaying.txt).
4. Include tests where practical. If you add parsing logic, mirror `tests/provider_parsing_spec.lua` style (if reintroduced) or add a minimal reproducible check.
5. Verify formatting and linting if your environment enforces it.

## Coding Standards 📐

- Lua: favor clear, small functions; avoid global state; use `vim.tbl_*` helpers for options merging.
- Config options should have sensible defaults and be documented.
- Keep cross-platform considerations in mind; gate macOS-specific calls (AppleScript) appropriately.

## Submitting Changes 📬

- Open a PR with:
  - A short summary of what changed and why.
  - Notes on testing performed.
  - Any user-facing changes (new options, defaults, behavior).
- If your change may be breaking, call it out in the PR description.

## Reporting Issues 🐞

When filing an issue, include:

- Neovim version and OS.
- Which player(s) you’re using (Apple Music/Spotify).
- Steps to reproduce and expected/actual behavior.
- Any relevant logs or error messages.
