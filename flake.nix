{
  description = "PW's Neovide (pwneovide) with pwnvim";
  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix/release-0.11.0";
    flake-utils.follows = "cargo2nix/flake-utils";
    nixpkgs.follows = "cargo2nix/nixpkgs";
    # nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # flake-utils.url = "github:numtide/flake-utils";
    neovide-direct.url = "github:neovide/neovide/0.10.3";
    neovide-direct.flake = false;
    skia.url = "github:rust-skia/skia/m103-0.51.1";
    skia.flake = false;
    pwnvim.url = "github:zmre/pwnvim";
    pwnvim.inputs.nixpkgs.follows = "nixpkgs";

    cargo-bundle = {
      url = "github:burtonageo/cargo-bundle";
      flake = false;
    };
  };
  outputs = inputs@{ self, nixpkgs, flake-utils, pwnvim, neovide-direct
    , rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            cargo2nix.overlays.default
            # (import rust-overlay)
            (import ./cargo-bundle.nix)
            # (self: super: {
            #   cargo-bundle = self.rustPlatform.buildRustPackage {
            #     name = "cargo-bundle";
            #     pname = "cargo-bundle";
            #     cargoLock = { lockFile = inputs.cargo-bundle + /Cargo.lock; };
            #     buildDependencies = [ self.glib ];
            #     buildInputs = [ self.pkg-config self.libiconv ]
            #       ++ self.lib.optionals self.stdenv.isDarwin
            #       (with self.darwin.apple_sdk.frameworks; [
            #         Security
            #         CoreGraphics
            #         CoreVideo
            #         AppKit
            #       ]);
            #     src = inputs.cargo-bundle;
            #   };
            # })

            # (self: super: {
            #   neovide = super.neovide.overrideAttrs (old: {
            #     postInstall = (if super.stdenv.isDarwin then ''
            #       mkdir $out/Applications
            #       cp -r bundle/osx/Neovide.app $out/Applications
            #       ln -s $out/bin $out/Applications/Neovide.app/Contents/MacOS
            #     '' else
            #       old.postInstall);
            #     nativeBuildInputs = old.nativeBuildInputs
            #       ++ [ super.cargo-bundle ];
            #     postBuild = "cargo bundle --release";
            #   });
            # })
          ];
        };
        rusttoolchain = pkgs.rust-bin.fromRustupToolchainFile neovide-direct
          + /rust-toolchain.toml;
        cargoToml = (builtins.fromTOML (builtins.readFile
          (builtins.trace neovide-direct (neovide-direct + /Cargo.toml))));
        rustPkgs = pkgs.rustBuilder.makePackageSet {
          rustVersion = "1.65.0";
          packageFun = import ./Cargo.nix;
        };

      in rec {
        packages.pwneovide = (rustPkgs.workspace.neovide { }).bin;
        packages.pwneovide2 = pkgs.rustPlatform.buildRustPackage rec {
          pname = "pwneovide";
          version = cargoToml.package.version;
          # SKIA_NINJA_COMMAND = "${ninja}/bin/ninja";
          # SKIA_GN_COMMAND = "${gn}/bin/gn";
          # LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

          src = builtins.trace neovide-direct (neovide-direct + /.);
          cargoLock = {
            lockFile = (neovide-direct + /Cargo.lock);
            outputHashes = {
              "glutin-0.26.0" =
                "sha256-Ie4Jb3wCMZSmF1MUzkLG2TqsLrXXzzi6ATjzCjevZBc=";
              "nvim-rs-0.5.0" =
                "sha256-3U0/OSDkJYCihFN7UbxnoIgsHKUQB4FAdYTqBZPT2us=";
              "winit-0.24.0" =
                "sha256-p/eAaDVmTHzfZ+0DiBA/9v06Z5o1dXVNoCgWRqC1ed0=";
              "xkbcommon-dl-0.1.0" =
                "sha256-ojokJF7ivN8JpXo+JAfX3kUOeXneNek7pzIy8D1n4oU=";
            };
          };

          preConfigure = ''
            unset CC CXX
          '';

          # test needs a valid fontconfig file
          # FONTCONFIG_FILE = makeFontsConf { fontDirectories = [ ]; };

          nativeBuildInputs = with pkgs;
            [
              cargo-bundle
              cmake
              pkg-config
              makeWrapper
              python2 # skia-bindings
              python3 # rust-xcb
              llvmPackages.clang # skia
              removeReferencesTo
            ] ++ lib.optionals stdenv.isDarwin [ xcbuild ];

          doCheck = false;

          buildInputs = with pkgs;
            [
              pwnvim.packages.${system}.pwnvim
              openssl
              SDL2
              (fontconfig.overrideAttrs (old: {
                propagatedBuildInputs = [
                  #   # skia is not compatible with freetype 2.11.0
                  (freetype.overrideAttrs (old: rec {
                    version = "2.10.4";
                    src = fetchurl {
                      url =
                        "mirror://savannah/${old.pname}/${old.pname}-${version}.tar.xz";
                      sha256 =
                        "112pyy215chg7f7fmp2l9374chhhpihbh8wgpj5nj6avj3c59a46";
                    };
                  }))
                ];
              }))
            ] ++ lib.optionals stdenv.isDarwin
            (with pkgs.darwin.apple_sdk.frameworks; [
              Security
              ApplicationServices
              Carbon
              AppKit
              CoreGraphics
              CoreFoundation
              Foundation
              OpenGL
              CoreVideo
              QuartzCore
            ]);

          postFixup = let
            libPath = pkgs.lib.makeLibraryPath (with pkgs;
              [ ] ++ lib.optionals stdenv.isLinux [
                libglvnd
                libxkbcommon
                xorg.libXcursor
                xorg.libXext
                xorg.libXrandr
                xorg.libXi
              ]); # ++ lib.optionals enableWayland [ wayland ]);
          in ''
            # library skia embeds the path to its sources
            # remove-references-to -t "$SKIA_SOURCE_DIR" \
              # $out/bin/neovide

            wrapProgram $out/bin/neovide \
              --prefix LD_LIBRARY_PATH : ${libPath}
          '';

          postBuild = ''
            cargo bundle --release
          '';

          postInstall = pkgs.lib.optionals pkgs.stdenv.isLinux ''
            for n in 16x16 32x32 48x48 256x256; do
              install -m444 -D "assets/neovide-$n.png" \
                "$out/share/icons/hicolor/$n/apps/neovide.png"
            done
            install -m444 -Dt $out/share/icons/hicolor/scalable/apps assets/neovide.svg
            install -m444 -Dt $out/share/applications assets/neovide.desktop
          '';

          # disallowedReferences = [ SKIA_SOURCE_DIR ];

        };

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
