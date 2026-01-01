# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pwneovide is a Nix flake that packages [Neovide](https://neovide.dev/) (a GUI for Neovim) pre-configured to use [pwnvim](https://github.com/zmre/pwnvim) (a portable, sandboxed Neovim configuration). On macOS, it also builds a proper `.app` bundle that appears as "PWNeovide" in the Applications folder.

## Build Commands

```bash
# Build the package
nix build

# Run without installing
nix run

# Enter development shell with pwneovide and pwnvim available
nix develop
```

## Architecture

This is a pure Nix flake project with no traditional source code. The entire build logic is in `flake.nix`.

**Key flow:**
1. Takes upstream `neovide` binary from nixpkgs
2. Wraps it with `wrapProgram` to inject pwnvim as `NEOVIM_BIN` and configure environment
3. On macOS: Creates a `.app` bundle using template `extras/Info.plist` with variable substitution

**Important files:**
- `flake.nix` - All build logic, dependencies, and outputs
- `extras/Info.plist` - macOS app bundle template (uses `@VERSION@`, `@NEOVIM_BIN@`, `@PATH@` substitution variables)
- `extras/Neovide.icns` - macOS app icon
- `default.nix` - Enables flake-compat for nixd LSP completions

**Cachix:** Binary cache at `zmre.cachix.org` for faster builds.

## Font Requirement

The configuration hardcodes "Hasklug Nerd Font" - users need nerdfonts installed for proper display.
