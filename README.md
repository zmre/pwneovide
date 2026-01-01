# pwneovide - my portable neovide setup

This exists for a few reasons:

1. I like Neovide as a GUI neovim
2. I want Neovide to use my portable sandboxed [pwnvim](https://github.com/zmre/pwnvim) setup
3. The default nix neovide doesn't build a MacOS app

This is only useful for users of nix with flakes enabled, but if you have those things, you can try this with: 

`nix run github:zmre/pwneovide`

See pwnvim for some guidance on how to add this version of neovide to your home-manager or nixos configs.

Note: I've hard coded `hasklug nerd font` as the font so you should install `nerdfonts` if you want this to look nice. I didn't specify them as a dependency mainly because I don't really know how to require system-wide things from inside a sandboxed app.

## Building

It seems that code signing might be needed now where it wasn't before. This is likely a "me" problem as I have been pre-building and storing in cachix.  I've updated so code signing will happen if possible and then I need to run this locally:

`nix build --no-link --print-out-paths | cachix push zmre`

## TODO

* [ ] Figure out a way to use "open with" maybe with [applescript](https://github.com/neovide/neovide/issues/1259) workarounds
