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
      # Upstream neovide releases land well before nixpkgs catches up, so
      # extras/neovide-pin.json records the newest upstream release together
      # with the hashes needed to build it. ./update.sh maintains that file.
      #
      # The pin is only *applied* while it is genuinely newer than the neovide
      # nixpkgs ships. Once nixpkgs catches up we go back to taking theirs, which
      # means their skia bookkeeping comes along for free and a forgotten pin can
      # never silently hold us at an older release.
      # Set "version" to null to disable pinning entirely.
      neovidePin = builtins.fromJSON (builtins.readFile ./extras/neovide-pin.json);

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          # Note the shape: the attribute is defined unconditionally and only its
          # *value* branches. Deciding whether to define `neovide` at all would
          # make the overlay's attribute names depend on a package value, which
          # is infinite recursion.
          (final: prev: {
            neovide =
              if
                neovidePin.version
                == null
                || !(prev.lib.versionOlder prev.neovide.version neovidePin.version)
              then prev.neovide
              else
                prev.neovide.overrideAttrs (old: rec {
                  version = neovidePin.version;
                  src = prev.fetchFromGitHub {
                    owner = "neovide";
                    repo = "neovide";
                    tag = version;
                    hash = neovidePin.srcHash;
                  };
                  cargoDeps = prev.rustPlatform.fetchCargoVendor {
                    inherit src;
                    hash = neovidePin.cargoHash;
                  };
                  # Rebuilt rather than inherited from nixpkgs because a newer
                  # neovide may want a newer skia than nixpkgs has wired up. The
                  # tag is whatever skia-bindings asks for; if it moves, the
                  # externals below have to be regenerated from that skia's DEPS.
                  env =
                    old.env
                    // {
                      SKIA_SOURCE_DIR = let
                        repo = prev.fetchFromGitHub {
                          owner = "rust-skia";
                          repo = "skia";
                          tag = neovidePin.skia.tag;
                          hash = neovidePin.skia.hash;
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
      # Window decorations. macOS gets the transparent titlebar, which keeps the
      # traffic lights floating over the editor surface; it is a macOS-only mode,
      # so everywhere else keeps the full frame. Defined once here and threaded
      # into both the CLI wrapper and the app bundle's LSEnvironment, so the two
      # launch paths cannot drift apart.
      neovideFrame =
        if pkgs.stdenv.isDarwin
        then "transparent"
        else "full";
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
            cp ${pkgs.neovide}/bin/neovide $out/bin/pwneovide
            wrapProgram $out/bin/pwneovide \
              --set NEOVIDE_FRAME ${neovideFrame}  \
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
                --subst-var-by NEOVIDE_FRAME ${neovideFrame} \
                --subst-var-by NEOVIM_BIN ${pwnvim.packages.${system}.pwnvim + "/bin/nvim"} \
                --subst-var-by PATH ${binPath}
              cp ${./extras/Neovide.icns} $out/Applications/PWNeovide.app/Contents/Resources/Neovide.icns

              # The real binary must *be* CFBundleExecutable. Do not reintroduce
              # a launcher stub that exec's a sibling: LaunchServices invalidates
              # the ASN->PID binding across execve, after which NSWorkspace
              # reports the app with processIdentifier -1 forever. Every
              # Accessibility-API tool resolves windows by pid, so aerospace,
              # alt-tab and Amethyst all go blind to the window while the app
              # otherwise looks and behaves normally. It is the exec itself that
              # does this, not the binary being different -- exec'ing the very
              # same path breaks it too, and doing it earlier in main() does not
              # help. Neovide implements application:openFiles: itself, so the
              # kAEOpenDocuments event the stub used to intercept is delivered
              # straight to it.
              #
              # nix links this binary ad-hoc ("linker-signed"), which is the
              # signature flavour AMFI trusts for LaunchServices launches. Do not
              # run `codesign --force --deep -s -` over it: that replaces the
              # linker signature with a plain ad-hoc one and the app stops
              # launching.
              cp ${pkgs.neovide}/bin/neovide $out/Applications/PWNeovide.app/Contents/MacOS/neovide

              # LaunchServices only rescans a few well-known directories, and
              # every rebuild lands the bundle at a fresh /nix/store path, so the
              # document type claims in Info.plist routinely need a manual nudge
              # before "Open With" picks them up. See README.
              # LSHandlerRank only governs eligibility and menu order; a default
              # already recorded for a type outranks it. This claims them.
              cc -fobjc-arc -framework Foundation -framework CoreServices \
                -o $out/bin/pwneovide-set-default ${./extras/set-default-handler.m}

              cat > $out/bin/pwneovide-register <<EOF
              #!/bin/sh
              set -eu
              exec /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
                -f -R -trusted "$out/Applications/PWNeovide.app"
              EOF
              chmod +x $out/bin/pwneovide-register
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
      devShells.default = devShell;
      # Tooling for ./update.sh, which re-execs itself into this shell so it
      # never depends on what happens to be installed globally. The text tools
      # are listed on purpose: macOS ships BSD sed/awk, and grep here is shadowed
      # by ugrep -- both differ from what the script is written against.
      devShells.update = pkgs.mkShell {
        buildInputs = [
          pkgs.cachix
          pkgs.cacert
          pkgs.coreutils
          pkgs.curl
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
        ];
      };
    });
}
