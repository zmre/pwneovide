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
    #nixpkgs.url = "github:nixos/nixpkgs/staging-next"; # temp to get a fix 2024-11-12; should only be needed for another two days or so but I'm impatient
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
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            neovide = prev.neovide.overrideAttrs (old: rec {
              version = "0.16.0";
              src = prev.fetchFromGitHub {
                owner = "neovide";
                repo = "neovide";
                tag = version;
                hash = "sha256-i3HEdYZ1fTK8kHRMhGVY80kE6Sp/HhNV4vG2cVroDWo=";
              };
              cargoDeps = prev.rustPlatform.fetchCargoVendor {
                inherit src;
                hash = "sha256-ybPKRgUZ2MRbzSFyevxSDtsNyU4iQwL4b7JIqBpbwk4=";
              };
              env =
                old.env
                // {
                  SKIA_SOURCE_DIR = let
                    repo = prev.fetchFromGitHub {
                      owner = "rust-skia";
                      repo = "skia";
                      tag = "m145-0.92.0";
                      hash = "sha256-9N780AwheKBJRcZC4l/uWFNq+oOyoNp4M6dJAVVAFeo=";
                    };
                    externals = prev.linkFarm "skia-externals" (
                      prev.lib.mapAttrsToList (name: value: {
                        inherit name;
                        path = prev.fetchgit value;
                      }) (prev.lib.importJSON ./extras/skia-externals.json)
                    );
                  in
                    prev.runCommand "source" {} ''
                      cp -R ${repo} $out
                      chmod -R +w $out
                      ln -s ${externals} $out/third_party/externals
                    '';
                };
            });
          })
        ];
      };
      libPath = pkgs.lib.makeLibraryPath [
        pkgs.libglvnd
        pkgs.libxkbcommon
        pkgs.xorg.libXcursor
        pkgs.xorg.libXext
        pkgs.xorg.libXrandr
        pkgs.xorg.libXi
      ];
      binPath = pkgs.lib.makeBinPath (pwnvim.packages.${system}.pwnvim.buildInputs ++ pkgs.neovide.buildInputs);
    in rec {
      packages.pwneovide = pkgs.stdenvNoCC.mkDerivation {
        pname = "pwneovide";
        name = "pwneovide";
        version = "${pkgs.neovide.version}-${pwnvim.packages.${system}.pwnvim.version}";
        src = ./.;
        buildInputs =
          [pkgs.neovide pkgs.makeWrapper pkgs.libtool]
          ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.apple-sdk_26
          ];
        nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.stdenv.cc
        ];
        buildPhase = "";
        installPhase =
          ''
            mkdir -p $out/bin
            cp ${pkgs.neovide}/bin/.neovide-wrapped $out/bin/pwneovide
            wrapProgram $out/bin/pwneovide \
              --add-flags "--no-tabs"  \
              --set NEOVIDE_FRAME full  \
              --set NEOVIM_BIN ${pwnvim.packages.${system}.pwnvim + "/bin/nvim"} \
              --prefix PATH : ${binPath} \
              --prefix LD_LIBRARY_PATH : ${libPath}
            if [ -d ${pkgs.neovide}/share ] ; then
              cp -R ${pkgs.neovide}/share $out/
            fi
          ''
          + (
            if pkgs.stdenv.isDarwin
            then ''
              mkdir -p $out/Applications/PWNeovide.app/Contents/Resources
              mkdir -p $out/Applications/PWNeovide.app/Contents/MacOS
              substitute ${./extras/Info.plist} $out/Applications/PWNeovide.app/Contents/Info.plist \
                --subst-var-by VERSION ${pkgs.neovide.version} \
                --subst-var-by NEOVIM_BIN ${pwnvim.packages.${system}.pwnvim + "/bin/nvim"} \
                --subst-var-by PATH ${binPath}
              cp ${./extras/Neovide.icns} $out/Applications/PWNeovide.app/Contents/Resources/Neovide.icns
              # Copy neovide as neovide-bin (the actual binary)
              cp ${pkgs.neovide}/bin/.neovide-wrapped $out/Applications/PWNeovide.app/Contents/MacOS/neovide-bin
              # Compile a tiny launcher that exec's neovide-bin. When compiled
              # locally, this gets linker-signed by the compiler, which macOS
              # AMFI trusts for LaunchServices app launches without requiring
              # Developer ID signing or notarization.
              cc -framework Cocoa -o $out/Applications/PWNeovide.app/Contents/MacOS/neovide ${./extras/neovide-launcher.m}
            ''
            else ""
          );
      };

      apps.pwneovide = flake-utils.lib.mkApp {
        drv = packages.pwneovide;
        name = "pwneovide";
        exePath = "/bin/pwneovide";
      };
      packages.default = packages.pwneovide;
      apps.default = apps.pwneovide;
      devShell = pkgs.mkShell {
        buildInputs = [packages.pwneovide pwnvim.packages.${system}.pwnvim] ++ pwnvim.packages.${system}.pwnvim.buildInputs ++ pkgs.neovide.buildInputs;
      };
    });
}
