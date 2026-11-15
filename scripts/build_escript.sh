#!/usr/bin/env bash
# Build the self-contained niffler escript from the current checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

gleam build --target erlang
escript nix/build_escript.escript \
  niffler.escript \
  build/dev/erlang/niffler_precompiled/ebin \
  build/dev/erlang/gleam_stdlib/ebin
chmod +x niffler.escript
printf 'wrote %s/niffler.escript\n' "$ROOT"
