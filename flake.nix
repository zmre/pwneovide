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
    pwnvim.url = "github:zmre/pwnvim";
    pwnvim.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, pwnvim, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        dependencies = [
          # need to figure out how to handle fonts in a flake...
          # nerdfonts.override { fonts = [ "FiraCode" "Hasklig" "DroidSansMono" ]; }
        ];
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (self: super: {
              neovide = super.neovide.overrideAttrs (old: rec {
                nativeBuildInputs = old.nativeBuildInputs ++ [ super.gnused ];
                buildInputs = old.buildInputs ++ (with super;
                  [
                    pwnvim.packages.${system}.pwnvim
                    bat
                    fd
                    fzy
                    git
                    nixfmt
                    ripgrep
                    zsh
                    zoxide
                  ] ++ super.lib.optionals super.stdenv.isDarwin
                  (with darwin.apple_sdk.frameworks;
                    [
                      /* Security
                         ApplicationServices
                         Carbon
                         OpenGL
                         CoreGraphics
                         CoreFoundation
                         CoreVideo
                         AppKit
                         QuartzCore
                         Foundation
                      */
                    ]));
                # We are deliberately allowing existing env to leak in by prefixing path
                # instead of setting it.
                postFixup =
                  builtins.replaceStrings [ "--prefix LD_LIBRARY_PATH" ] [
                    ("--add-flags --notabs " + (if super.stdenv.isDarwin then
                      "--add-flags --novsync --set NEOVIDE_FRAME buttonless --set NEOVIDE_MULTIGRID true "
                    else
                      "") + "--set NEOVIM_BIN ${
                        pwnvim.packages.${system}.pwnvim + "/bin/nvim"
                      } --prefix PATH : ${
                        super.lib.makeBinPath buildInputs
                      } --prefix LD_LIBRARY_PATH")
                  ] old.postFixup + (if super.stdenv.isDarwin then ''
                    cp $out/bin/.neovide-wrapped $out/Applications/Neovide.app/Contents/MacOS/Neovide
                  '' else
                    "");
                postInstall = if super.stdenv.isDarwin then ''
                  mkdir -p $out/Applications/Neovide.app/Contents/Resources
                  mkdir -p $out/Applications/Neovide.app/Contents/MacOS
                  substitute ${
                    ./extras/Info.plist
                  } $out/Applications/Neovide.app/Contents/Info.plist \
                    --subst-var-by VERSION ${old.version} \
                    --subst-var-by NEOVIM_BIN ${
                      pwnvim.packages.${system}.pwnvim + "/bin/neovim"
                    } \
                    --subst-var-by PATH ${super.lib.makeBinPath buildInputs}
                  cp ${
                    ./extras/Neovide.icns
                  } $out/Applications/Neovide.app/Contents/Resources/Neovide.icns
                '' else
                  old.postInstall;
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
          buildInputs = with pkgs; [ packages.pwneovide ] ++ dependencies;
        };
      });
}
