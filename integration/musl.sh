#!/bin/sh
# Run inside an Alpine container to prove a musl-linked NIF can be compiled
# and loaded by a musl Erlang/OTP build.
set -eu

apk add --no-cache build-base erlang >/dev/null

INC="$(erl -noshell -eval 'io:format("~s/usr/include",[code:root_dir()]),halt().')"
cc -fPIC -shared -I"$INC" -o /tmp/demo_nif.so integration/fixtures/c_adder.c

mkdir -p /tmp/smoke
cp /tmp/demo_nif.so /tmp/smoke/demo_nif.so

cat > /tmp/smoke/demo_nif.erl <<'EOF'
-module(demo_nif).
-on_load(init/0).
-export([add/2, niffler_smoke/0]).
init() -> erlang:load_nif("/tmp/smoke/demo_nif", []).
add(_, _) -> erlang:nif_error(nif_not_loaded).
niffler_smoke() -> ok.
EOF

erlc -o /tmp/smoke /tmp/smoke/demo_nif.erl
erl -noshell -pa /tmp/smoke -eval 'demo_nif:niffler_smoke(), halt(0).'
echo "musl smoke: loaded demo_nif successfully"
