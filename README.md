# pwneovide - my portable neovide setup

This exists for a few reasons:

1. I like Neovide as a GUI neovim
2. I want Neovide to use my portable sandboxed [pwnvim](https://github.com/zmre/pwnvim) setup
3. The default nix neovide doesn't build a MacOS app

I've struggled to use the default neovide recipe and get it to work the way I want.  When doing this manually, I use `cargo bundle` to make it. I was building `cargo-bundle` and doing this at first, but ended up just taking the outputs as a template to simplify the build and issues.

This is only useful for users of nix with flakes enabled, but if you have those things, you can try this with: 

`nix run github:zmre/pwneovide`

See pwnvim for some guidance on how to add this version of neovide to your home-manager or nixos configs.

Note: I've hard coded `hasklug nerd font` as the font so you should install `nerdfonts` if you want this to look nice. I didn't specify them as a dependency.

## TODO

* [X] Resolve [issue](https://github.com/neovide/neovide/issues/915) with Amethyst and neovide -- figure out how to apply workarounds here
* [ ] Figure out a way to use "open with" maybe with [applescript](https://github.com/neovide/neovide/issues/1259) workarounds
* [X] The app wrapper causes the running app to show without icons and with the name ".neovide-wrapped" instead of "neovide"
* [ ] There's a lag when launching from a launcher that doesn't happen when launching from CLI -- debug this
* [ ] Research ways to make flakes modular so options can be toggled on/off
