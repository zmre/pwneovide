#!/usr/bin/env bash
#
# Update pwneovide: refresh the flake inputs *and* the pinned neovide release,
# then build and push the result to cachix.
#
# nixpkgs regularly lags upstream neovide by months, so extras/neovide-pin.json
# records the newest upstream release plus the hashes needed to build it.
# flake.nix applies that pin only while it is newer than the neovide nixpkgs
# ships, so this script keeps the file pointed at the latest release and lets
# the flake decide whether it is needed.
set -euo pipefail

cd "$(dirname "$0")"

# Run with the tools from devShells.update rather than whatever is on PATH.
if [ -z "${PWNEOVIDE_UPDATE_SHELL:-}" ]; then
  exec nix develop --accept-flake-config .#update \
    -c env PWNEOVIDE_UPDATE_SHELL=1 "$0" "$@"
fi

PIN=extras/neovide-pin.json
EXTERNALS=extras/skia-externals.json
CACHE=zmre

note() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

# Nix's own version ordering, so 0.16.10 correctly beats 0.16.2.
version_lt() {
  [ "$(nix eval --raw --expr \
    "builtins.toString (builtins.compareVersions \"$1\" \"$2\")")" = "-1" ]
}

# fetchFromGitHub's hash for a tag is the hash of the unpacked tarball, which is
# exactly what `nix-prefetch-url --unpack` computes.
prefetch_tag() { # owner repo tag
  local base32
  base32=$(nix-prefetch-url --unpack --type sha256 \
    "https://github.com/$1/$2/archive/refs/tags/$3.tar.gz" 2>/dev/null) ||
    die "could not fetch $1/$2 tag $3"
  nix hash convert --hash-algo sha256 --to sri "$base32"
}

# The neovide version nixpkgs currently ships, read through the (just updated)
# lock file so it reflects what we are actually about to build against.
nixpkgs_neovide_version() {
  nix eval --raw --impure --expr \
    '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.neovide.version'
}

# skia-bindings hard-codes which rust-skia/skia tree it expects, and nixpkgs
# tracks it by hand. Derive it: neovide's Cargo.lock names the skia-bindings
# version, whose Cargo.toml names the skia tag.
#
# Each download is captured whole before being parsed. Piping curl straight into
# a reader that stops early (awk ... exit, head -1) hands curl an EPIPE, and
# under `pipefail` that turns a successful lookup into a failed pipeline.
skia_tag_for() { # neovide version
  local lock manifest bindings tag
  lock=$(curl -fsSL \
    "https://raw.githubusercontent.com/neovide/neovide/$1/Cargo.lock") ||
    die "could not fetch the Cargo.lock for neovide $1"
  bindings=$(printf '%s\n' "$lock" |
    grep -A1 '^name = "skia-bindings"$' |
    sed -n 's/^version = "\(.*\)"$/\1/p')
  bindings=${bindings%%$'\n'*}
  [ -n "$bindings" ] || die "no skia-bindings entry in neovide $1 Cargo.lock"

  manifest=$(curl -fsSL \
    "https://raw.githubusercontent.com/rust-skia/rust-skia/$bindings/skia-bindings/Cargo.toml") ||
    die "could not fetch the manifest for skia-bindings $bindings"
  tag=$(printf '%s\n' "$manifest" | sed -n 's/^skia = "\(.*\)"$/\1/p')
  tag=${tag%%$'\n'*}
  [ -n "$tag" ] || die "no skia tag in skia-bindings $bindings metadata"
  printf '%s\n' "$tag"
}

# Vendor the crates with a deliberately wrong hash and read the right one out of
# the mismatch. Built straight from nixpkgs rather than through the flake so it
# works even while the pin is inert.
cargo_vendor_hash() { # neovide version, src hash
  local expr out hash
  expr=$(
    cat <<EOF
let
  pkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
in
  pkgs.rustPlatform.fetchCargoVendor {
    src = pkgs.fetchFromGitHub {
      owner = "neovide";
      repo = "neovide";
      tag = "$1";
      hash = "$2";
    };
    hash = pkgs.lib.fakeHash;
  }
EOF
  )

  # --log-format raw: the default progress UI interleaves escape codes with the
  # error text, which makes the hash much harder to pick back out.
  if out=$(nix build --impure --no-link --log-format raw --expr "$expr" 2>&1); then
    die "vendoring with a fake hash unexpectedly succeeded"
  fi
  hash=$(printf '%s\n' "$out" | grep 'got:' | grep -o 'sha256-[A-Za-z0-9+/=]*')
  hash=${hash%%$'\n'*}
  [ -n "$hash" ] || die "could not read the vendor hash from:"$'\n'"$out"
  printf '%s\n' "$hash"
}

# installPhase *copies* the neovide binary into $out instead of referencing it,
# so neovide is not part of the closure and `diff-closures` below cannot see a
# version bump. Ask the built binary directly.
built_neovide_version() { # result prefix
  "$1/bin/pwneovide" --version 2>/dev/null |
    awk '/neovide/ && !seen {print $2; seen = 1}'
}

if [ -e result ]; then
  OLDRESULT=$(realpath result)
  OLDNEOVIDE=$(built_neovide_version "$OLDRESULT" || true)
fi

note "Updating flake inputs"
nix flake update

note "Checking neovide versions"
release=$(curl -fsSL https://api.github.com/repos/neovide/neovide/releases/latest) ||
  die "could not reach the GitHub releases API"
latest=$(printf '%s' "$release" | jq -r '.tag_name')
[ -n "$latest" ] && [ "$latest" != "null" ] ||
  die "could not determine the latest neovide release"
nixpkgs_version=$(nixpkgs_neovide_version)
# A null version is a deliberate "always just use nixpkgs"; leave it alone.
pinned=$(jq -r 'if .version == null then "disabled" else .version end' "$PIN")

echo "  latest release: $latest"
echo "  nixpkgs ships:  $nixpkgs_version"
echo "  pin records:    $pinned"

if [ "$pinned" != "disabled" ] && [ "$pinned" != "$latest" ]; then
  note "Recording neovide $latest in $PIN"

  src_hash=$(prefetch_tag neovide neovide "$latest")
  echo "  src:   $src_hash"

  skia_tag=$(skia_tag_for "$latest")
  skia_hash=$(jq -r '.skia.hash' "$PIN")
  if [ "$skia_tag" != "$(jq -r '.skia.tag' "$PIN")" ]; then
    skia_hash=$(prefetch_tag rust-skia skia "$skia_tag")
    warn "skia moved to $skia_tag; $EXTERNALS is still the old tree."
    warn "Regenerate it from that skia's DEPS if the build fails to find sources."
  fi
  echo "  skia:  $skia_tag"

  # Slow: fetches the whole crate graph.
  cargo_hash=$(cargo_vendor_hash "$latest" "$src_hash")
  echo "  cargo: $cargo_hash"

  jq --arg version "$latest" \
    --arg srcHash "$src_hash" \
    --arg cargoHash "$cargo_hash" \
    --arg skiaTag "$skia_tag" \
    --arg skiaHash "$skia_hash" \
    '{version: $version, srcHash: $srcHash, cargoHash: $cargoHash,
      skia: {tag: $skiaTag, hash: $skiaHash}}' \
    "$PIN" >"$PIN.new"
  mv "$PIN.new" "$PIN"

  # Flakes only read git-tracked files, so a brand-new pin has to be staged
  # before nix will see it at all.
  git ls-files --error-unmatch "$PIN" >/dev/null 2>&1 || git add "$PIN"
fi

if [ "$pinned" = "disabled" ]; then
  note "Building neovide $nixpkgs_version from nixpkgs (pinning disabled)"
elif version_lt "$nixpkgs_version" "$latest"; then
  note "Building pinned neovide $latest (nixpkgs is behind at $nixpkgs_version)"
else
  note "Building neovide $nixpkgs_version from nixpkgs (pin is inert)"
fi

nix build --json |
  jq -r '.[].outputs | to_entries[].value' |
  cachix push "$CACHE"

note "Built neovide $(built_neovide_version ./result)${OLDNEOVIDE:+ (was $OLDNEOVIDE)}"

if [ -n "${OLDRESULT:-}" ]; then
  note "Diff with $OLDRESULT"
  nix store diff-closures "$OLDRESULT" ./result | grep '→' || echo "  no changes"
else
  note "No previous result symlink; skipping closure diff"
fi
