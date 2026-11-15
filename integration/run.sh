#!/usr/bin/env bash
# End-to-end integration checks for niffler.
#
# Covers the no-Rust path with a real C NIF: scaffolding, packaging, manifest,
# download+SHA-256 verification, cache hits, offline mode, read-only artifact
# directories, tamper rejection, smoke tests, verification, and the Hex emitter.
#
# Requires: gleam, erl/erlc, cc, python3, jq, tar, cargo (only for `init`'s
# Cargo.lock generation), and network access for `gleam deps download`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/integration/.work"
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

failed=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failed=1; }
assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  case "$haystack" in
    *"$needle"*) pass "$name" ;;
    *) fail "$name (missing: $needle)" ;;
  esac
}

run_cli() {
  local fixture="$1"
  shift
  (cd "$ROOT" && NIFFLER_ROOT="$fixture" "$GLEAM" run -m niffler_precompiled -- "$@")
}

new_project() {
  local dir="$1" name="$2"
  mkdir -p "$dir/src"
  cat > "$dir/gleam.toml" <<EOF
name = "$name"
version = "0.1.0"
target = "erlang"
description = "niffler integration fixture"
licences = ["Apache-2.0"]

[dependencies]
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
niffler_precompiled = { path = "../../.." }
EOF
  (cd "$dir" && "$GLEAM" deps download >/dev/null)
}

rm -rf "$WORK"
mkdir -p "$WORK"

ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/usr/include",[code:root_dir()]),halt().')"

echo "== demo package (C NIF, no Rust) =="
DEMO="$WORK/demo"
new_project "$DEMO" "demo"

run_cli "$DEMO" init --repo local/demo --no-example --functions add/2 \
  --targets x86_64-unknown-linux-gnu >/dev/null
if [ -f "$DEMO/src/demo_nif.erl" ]; then pass "init generated loader"; else fail "init generated loader"; fi
if [ -f "$DEMO/priv/niffler.json" ]; then pass "init generated manifest"; else fail "init generated manifest"; fi
if [ -f "$DEMO/.github/workflows/niffler-release.yml" ]; then pass "init generated workflow"; else fail "init generated workflow"; fi

cat > "$DEMO/src/demo.gleam" <<'EOF'
import gleam/int
import gleam/io

@external(erlang, "demo_nif", "add")
pub fn add(a: Int, b: Int) -> Int

pub fn main() {
  io.println(int.to_string(add(2, 3)))
}
EOF

cc -fPIC -shared -I"$ERL_INCLUDE" -o "$DEMO/libdemo_c.so" "$ROOT/integration/fixtures/c_adder.c"
run_cli "$DEMO" package --target x86_64-unknown-linux-gnu --binary "$DEMO/libdemo_c.so" \
  --nif-version 2.15 --dist "$DEMO/dist" >/dev/null
ARTIFACT="$(find "$DEMO/dist" -maxdepth 1 -name '*.tar.gz' | head -n1)"
if [ -n "$ARTIFACT" ]; then pass "package produced an artifact"; else fail "package produced an artifact"; fi

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
run_cli "$DEMO" manifest --dist "$DEMO/dist" --base-url "http://127.0.0.1:$PORT" \
  --version 0.1.0 --allow-insecure >/dev/null
run_cli "$DEMO" manifest --dist "$DEMO/dist" --base-url "http://127.0.0.1:$PORT" \
  --version 0.1.0 --allow-insecure --check >/dev/null
pass "manifest write/check"

run_cli "$DEMO" smoke --artifact "$ARTIFACT" --module demo_nif >/dev/null
pass "smoke test"

python3 -m http.server "$PORT" --directory "$DEMO/dist" >"$WORK/http.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1

run_consumer() {
  local cache="$1"
  shift
  (cd "$DEMO" && NIFFLER_ALLOW_INSECURE_URLS=1 NIFFLER_CACHE_DIR="$cache" "$@" "$GLEAM" run -m demo)
}

OUT="$(run_consumer "$DEMO/.cache" env)"
assert_contains "$OUT" "5" "consumer loads a downloaded verified NIF"

OUT="$(run_consumer "$DEMO/.cache" env NIFFLER_OFFLINE=1)"
assert_contains "$OUT" "5" "cache hit works offline"

SHA="$(jq -r '.artifacts[0].sha256' "$DEMO/priv/niffler.json")"
mkdir -p "$DEMO/artifacts"
tar -xzf "$ARTIFACT" -C "$DEMO/artifacts"
INNER="$(find "$DEMO/artifacts" -maxdepth 1 -name '*.so' | head -n1)"
mv "$INNER" "$DEMO/artifacts/$SHA.so"
OUT="$(run_consumer "$DEMO/.cache-artifact" env NIFFLER_ARTIFACT_DIR="$DEMO/artifacts")"
assert_contains "$OUT" "5" "read-only artifact directory loads without network"

run_cli "$DEMO" verify --manifest "$DEMO/priv/niffler.json" --dist "$DEMO/dist" >/dev/null
pass "offline verify"

# Tampered artifact: same asset name, different bytes, manifest hash unchanged.
mkdir -p "$DEMO/dist-tampered"
sed 's/a + b/a - b/' "$ROOT/integration/fixtures/c_adder.c" > "$DEMO/c_adder_tampered.c"
cc -fPIC -shared -I"$ERL_INCLUDE" -o "$DEMO/libtampered.so" "$DEMO/c_adder_tampered.c"
run_cli "$DEMO" package --target x86_64-unknown-linux-gnu --binary "$DEMO/libtampered.so" \
  --nif-version 2.15 --dist "$DEMO/dist-tampered" >/dev/null
kill "$SERVER" 2>/dev/null || true
wait "$SERVER" 2>/dev/null || true
python3 -m http.server "$PORT" --directory "$DEMO/dist-tampered" >"$WORK/http-tampered.log" 2>&1 &
SERVER=$!
sleep 1
set +e
OUT="$(run_consumer "$DEMO/.cache-tampered" env 2>&1)"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] && printf '%s' "$OUT" | grep -qi 'checksum mismatch'; then
  pass "tampered artifact is rejected with a checksum error"
else
  fail "tampered artifact rejection (status=$STATUS)"
fi
if [ -z "$(find "$DEMO/.cache-tampered/artifacts" -type f 2>/dev/null | head -n1)" ]; then
  pass "tampered artifact is not cached"
else
  fail "tampered artifact was cached"
fi
set +e
run_cli "$DEMO" verify --manifest "$DEMO/priv/niffler.json" --dist "$DEMO/dist-tampered" >/dev/null 2>&1
VERIFY_STATUS=$?
set -e
if [ "$VERIFY_STATUS" -ne 0 ]; then pass "verify detects a tampered dist"; else fail "verify misses a tampered dist"; fi

if run_cli "$DEMO" generate --check >/dev/null; then pass "generate --check"; else fail "generate --check"; fi
run_cli "$DEMO" doctor >"$WORK/doctor.txt"
if grep -q "selected:" "$WORK/doctor.txt"; then pass "doctor prints the selected artifact"; else fail "doctor output"; fi

if command -v actionlint >/dev/null 2>&1; then
  if (cd "$DEMO" && actionlint .github/workflows/niffler-release.yml >/dev/null); then
    pass "generated workflow passes actionlint"
  else
    fail "generated workflow actionlint"
  fi
fi

echo "== hex emitter =="
HEX="$WORK/hexdemo"
new_project "$HEX" "hexdemo"
# Hex publishing requires all dependencies to come from Hex, so drop the path
# dependency used by the runtime fixtures.
python3 - "$HEX/gleam.toml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('niffler_precompiled = { path = "../../.." }\n', '')
open(path, 'w').write(text)
PY
(cd "$HEX" && "$GLEAM" deps download >/dev/null)
printf '# hexdemo\n\nHex emitter integration fixture.\n' > "$HEX/README.md"
printf 'pub fn placeholder() -> Int { 1 }\n' > "$HEX/src/hexdemo.gleam"
run_cli "$HEX" init --repo local/hexdemo --no-example --functions add/2 \
  --targets x86_64-unknown-linux-gnu >/dev/null
sed 's/demo_nif/hexdemo_nif/g' "$ROOT/integration/fixtures/c_adder.c" > "$HEX/hexdemo_adder.c"
cc -fPIC -shared -I"$ERL_INCLUDE" -o "$HEX/libhexdemo.so" "$HEX/hexdemo_adder.c"
run_cli "$HEX" package --target x86_64-unknown-linux-gnu --binary "$HEX/libhexdemo.so" \
  --nif-version 2.15 --dist "$HEX/dist" >/dev/null
run_cli "$HEX" manifest --dist "$HEX/dist" --write >/dev/null
run_cli "$HEX" hex check >"$WORK/hex-check.txt"
if grep -q "package is valid" "$WORK/hex-check.txt"; then pass "hex check"; else fail "hex check"; fi
run_cli "$HEX" hex emit >"$WORK/hex-emit.txt"
HEX_TAR="$HEX/dist/hex/hexdemo-0.1.0.tar"
if [ -f "$HEX_TAR" ] && [ -f "$HEX_TAR.sha256" ]; then pass "hex emit wrote tarball + checksum"; else fail "hex emit output"; fi
rm -rf "$WORK/hex-unpacked"
mkdir -p "$WORK/hex-unpacked"
tar -xf "$HEX_TAR" -C "$WORK/hex-unpacked"
tar -xzf "$WORK/hex-unpacked/contents.tar.gz" -C "$WORK/hex-unpacked"
for required in priv/niffler.json priv/native/hexdemo_nif/Cargo.toml \
  priv/native/hexdemo_nif/Cargo.lock src/hexdemo_nif.erl; do
  if [ -f "$WORK/hex-unpacked/$required" ]; then pass "hex tarball contains $required"; else fail "hex tarball missing $required"; fi
done
if find "$WORK/hex-unpacked" -name '*.so' -o -name '*.dll' -o -name '*.dylib' | grep -q .; then
  fail "hex tarball contains native binaries"
else
  pass "hex tarball contains no native binaries"
fi

kill "$SERVER" 2>/dev/null || true
trap - EXIT

echo
if [ "$failed" -eq 0 ]; then
  echo "integration: all checks passed"
else
  echo "integration: failures detected" >&2
  exit 1
fi
