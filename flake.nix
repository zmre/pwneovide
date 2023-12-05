{
  description = "PW's Neovide (pwneovide) with pwnvim";
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://zmre.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "zmre.cachix.org-1:WIE1U2a16UyaUVr+Wind0JM6pEXBe43PQezdPKoDWLE="
    ];
  };
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      # Needed along with default.nix in root to allow nixd lsp to do completions
      # See: https://github.com/nix-community/nixd/tree/main/docs/examples/flake
      url = "github:inclyc/flake-compat";
      flake = false;
    };
    pwnvim.url = "github:zmre/pwnvim";
    pwnvim.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    pwnvim,
    rust-overlay,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      dependencies = [
        # need to figure out how to handle fonts in a flake...
        # nerdfonts.override { fonts = [ "FiraCode" "Hasklig" "DroidSansMono" ]; }
      ];
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (self: super: {
            neovide = super.neovide.overrideAttrs (old: rec {
              # 2023-11-25 I am reverting to clang 11 so skia will build
              # without this change, I get:
              #   ld: symbol(s) not found for architecture arm64
              #   clang-16: error: linker command failed with exit code 1 (use -v to see invocation)
              # and this seems to be caused by things referenced here:
              # https://discourse.nixos.org/t/lua-language-server-failed-to-compile/35722
              # https://bugreports.qt.io/browse/QTBUG-112335
              # hopefully it will shake out, but for now the clang11 workaround does the trick
              stdenv = super.clang_11; # this and below
              nativeBuildInputs =
                old.nativeBuildInputs
                ++ [
                  super.gnused
                  super.clang_11
                ];
              # Need the pwnvim buildinputs here so the various binaries like rg and prettier get into the env for neovide too
              buildInputs =
                old.buildInputs
                ++ (with super;
                  [pwnvim.packages.${system}.pwnvim]
                  ++ pwnvim.packages.${system}.pwnvim.buildInputs);
              # We are deliberately allowing existing env to leak in by prefixing path
              # instead of setting it.
              postFixup =
                builtins.replaceStrings ["--prefix LD_LIBRARY_PATH"] [
                  ("--add-flags --notabs "
                    + (
                      if super.stdenv.isDarwin
                      then "--set NEOVIDE_FRAME full "
                      else ""
                    )
                    + "--set NEOVIM_BIN ${
                      pwnvim.packages.${system}.pwnvim + "/bin/nvim"
                    } --prefix PATH : ${
                      super.lib.makeBinPath buildInputs
                    } --prefix LD_LIBRARY_PATH")
                ]
                old.postFixup
                + (
                  if super.stdenv.isDarwin
                  then ''
                    cp $out/bin/.neovide-wrapped $out/Applications/Neovide.app/Contents/MacOS/neovide
                  ''
                  else ""
                );
              postInstall =
                if super.stdenv.isDarwin
                then ''
                  mkdir -p $out/Applications/Neovide.app/Contents/Resources
                  mkdir -p $out/Applications/Neovide.app/Contents/MacOS
                  substitute ${./extras/Info.plist} $out/Applications/Neovide.app/Contents/Info.plist \
                    --subst-var-by VERSION ${old.version} \
                    --subst-var-by NEOVIM_BIN ${
                    pwnvim.packages.${system}.pwnvim + "/bin/nvim"
                  } \
                    --subst-var-by PATH ${super.lib.makeBinPath buildInputs}
                  cp ${./extras/Neovide.icns} $out/Applications/Neovide.app/Contents/Resources/Neovide.icns
                ''
                else old.postInstall;
            });
          })
        ];
      };
    in rec {
      packages.pwneovide = pkgs.neovide;

      apps.pwneovide = flake-utils.lib.mkApp {
        drv = packages.pwneovide;
        name = "pwneovide";
        exePath = "/bin/neovide";
      };
      packages.default = packages.pwneovide;
      apps.default = apps.pwneovide;
      devShell = pkgs.mkShell {
        buildInputs = [packages.pwneovide] ++ dependencies;
      };
    });
}
