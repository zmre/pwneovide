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

## "Open With" / default editor

The app bundle claims essentially every text-ish file type, so PWNeovide shows up
in Finder's right-click → "Open With" submenu. Specifics:

* **Owner** rank (i.e. it wants to be the double-click default) for plain text,
  Markdown, source code, JSON/YAML/TOML, `.journal`, `.mermaid` and friends.
* **Alternate** rank (offered, but never steals an existing default) for
  HTML/XML, folders, and a catch-all claim on `public.data` that covers
  arbitrary and extensionless files.

Markdown is claimed hardest: it gets its own document type entry listed first,
carries the Neovide icon, and its UTI is *exported* rather than imported. macOS
ships no Markdown UTI of its own — `CoreTypes.bundle` declares none and
`UTCoreTypes.h` has no constant for it — so `net.daringfireball.markdown` exists
only because apps declare it. With no system declaration to defer to, exporting
makes this bundle authoritative over the imported declarations other editors
ship.

To change how pushy it is, edit the `LSHandlerRank` values in
`extras/Info.plist` and re-register. To hand a single type back to another app,
use Finder's Get Info → "Open with" → "Change All…".

### Actually becoming the default

`LSHandlerRank` decides eligibility and "Open With" ordering, but a default
already recorded for a type — by you, or by whichever app registered first —
beats it. To overwrite those records:

```bash
pwneovide-set-default                              # every Owner-rank type
pwneovide-set-default net.daringfireball.markdown  # or just one
```

### Registering with LaunchServices

macOS only auto-scans a few directories for apps, and every rebuild puts the
bundle at a fresh `/nix/store` path, so registration usually needs a nudge:

```bash
nix run .#pwneovide -- --version   # or just install it
pwneovide-register                 # shipped in $out/bin
```

Note that home-manager's `targets.darwin.linkApps` puts a *symlink* in
`~/Applications/Home Manager Apps`, and LaunchServices does not reliably index
symlinked bundles — this is why nix-darwin switched to `mkalias` for its own app
linking. `pwneovide-register` sidesteps it by registering the real store path.

If things get stale after many rebuilds, rebuild the whole database:

```bash
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -kill -r -domain local -domain system -domain user
killall Finder
```

### How a file actually reaches neovim

Finder does not pass the path on the command line — LaunchServices launches the
bundle and then sends the paths as a `kAEOpenDocuments` Apple Event. The
`extras/neovide-launcher.m` shim runs a minimal `NSApplication`, catches that
event in `application:openFiles:`, and only then exec's `neovide-bin` with the
paths appended. Neovide itself implements the same delegate method, which covers
documents opened while it is already running.
