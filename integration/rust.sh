#!/usr/bin/env bash
# Rust source-fallback integration test.
#
# Builds the scaffolded rustler crate from `priv/native/...` on first load with
# NIFFLER_BUILD=1 and checks that the resulting NIF is cached and callable.
# Requires network access the first time (rustler crate download).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/integration/.work-rust"
GLEAM="${NIFFLER_GLEAM:-}"
if [ -z "$GLEAM" ]; then
  GLEAM="$(command -v gleam || true)"
fi
if [ -z "$GLEAM" ]; then
  GLEAM="$(find /nix/store -maxdepth 3 -path "*-gleam-1.19.2/bin/gleam" -type f 2>/dev/null | head -n1 || true)"
fi
[ -n "$GLEAM" ] || { echo "gleam not found" >&2; exit 1; }

export HOME="$ROOT/.home"
export XDG_CACHE_HOME="$ROOT/.cache"
export CARGO_HOME="$ROOT/.local/cargo"
export NIFFLER_GLEAM="$GLEAM"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$CARGO_HOME"

if ! command -v cargo >/dev/null 2>&1; then
  echo "rust integration: cargo not found; skipping"
  exit 0
fi

rm -rf "$WORK"
FIXTURE="$WORK/rustdemo"
mkdir -p "$FIXTURE/src"
cat > "$FIXTURE/gleam.toml" <<EOF
name = "rustdemo"
version = "0.1.0"
target = "erlang"
description = "niffler Rust source fallback fixture"
licences = ["Apache-2.0"]

[dependencies]
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
niffler_precompiled = { path = "../../.." }
EOF
(cd "$FIXTURE" && "$GLEAM" deps download >/dev/null)

(cd "$ROOT" && NIFFLER_ROOT="$FIXTURE" "$GLEAM" run -m niffler_precompiled -- \
  init --repo local/rustdemo --no-example --functions add/2 \
  --targets x86_64-unknown-linux-gnu >/dev/null)

cat > "$FIXTURE/src/rustdemo.gleam" <<'EOF'
import gleam/int
import gleam/io

@external(erlang, "rustdemo_nif", "add")
pub fn add(a: Int, b: Int) -> Int

pub fn main() {
  io.println(int.to_string(add(2, 5)))
}
EOF

CACHE="$FIXTURE/.cache"
OUT="$(cd "$FIXTURE" && NIFFLER_BUILD=1 NIFFLER_CACHE_DIR="$CACHE" "$GLEAM" run -m rustdemo 2>&1)"
case "$OUT" in
  *7*) ;;
  *) echo "rust integration: expected 7, got: $OUT" >&2; exit 1 ;;
esac

if find "$CACHE/build" -name 'rustdemo_nif.so' -o -name 'rustdemo_nif.dll' | grep -q .; then
  echo "ok   source fallback built and cached the NIF"
else
  echo "rust integration: no cached NIF found under $CACHE/build" >&2
  exit 1
fi

OUT="$(cd "$FIXTURE" && NIFFLER_BUILD=1 NIFFLER_OFFLINE=1 NIFFLER_CACHE_DIR="$CACHE" "$GLEAM" run -m rustdemo 2>&1)"
case "$OUT" in
  *7*) echo "ok   source fallback cache hit works offline" ;;
  *) echo "rust integration: cache hit failed: $OUT" >&2; exit 1 ;;
esac

echo "rust integration: all checks passed"
