# Development

## Environment

The repository is set up for a devenv shell:

```sh
devenv shell
```

It provides Gleam, Erlang/OTP, `cargo`/`rustc` with a C linker, Python 3 (for
the integration HTTP server), `jq`, `curl`, and `git`. `XDG_CACHE_HOME` is
pointed at the repository's `.cache/` directory so the Gleam, Hex, and cargo
caches stay inside the checkout. The shell also defines `test`, `check`, and
`integration` scripts; `devenv test` runs the format check, a
warnings-as-errors build, and the unit tests.

The same `devenv.nix` is exposed as a flake development shell:

```sh
nix develop --no-pure-eval
```

`--no-pure-eval` is required because devenv needs the working directory; the
flake falls back to a temporary root when evaluated purely (for example by
`nix flake check`).

Toolchain versions:

| Tool | Version |
| --- | --- |
| Gleam | 1.19.2 (CI pins this; the Nix shell follows nixpkgs) |
| Erlang/OTP | 28 and 29 in CI; 28 is the runtime floor |
| Rust | Stable with `cargo`, for the crate and source fallback |
| Python 3 | Integration HTTP server |
| actionlint, shellcheck | CI checks for workflows and shell scripts |

The matching versions of the flake and devenv inputs are locked in
`flake.lock` and `devenv.lock`. Update both together with `nix flake update`
and `devenv update`.

## Checks

```sh
gleam format --check src test
gleam build --warnings-as-errors
gleam test
```

These run on Linux, macOS, and Windows in CI for OTP 28 and 29. The integration
suites run on Linux only:

```sh
bash integration/run.sh   # CLI, manifest, cache, and Hex packaging fixtures
bash integration/rust.sh  # Rust build and source-fallback fixtures
```

A musl load check runs a small C NIF inside Alpine:

```sh
docker run --rm -v "$PWD:/work" -w /work alpine:3.22 \
  sh integration/musl.sh
```

The integration scripts need `gleam`, `erl`/`erlc`, and Python 3 on `PATH`, plus
`cc`, `jq`, and `tar`; `integration/run.sh` also needs `cargo` for `init`'s
`Cargo.lock` generation. `integration/rust.sh` needs `cargo` and `rustc` and
skips itself when cargo is missing. Fixtures live under `integration/fixtures/`
and are built into ignored work directories (`integration/.work/`,
`integration/.work-rust/`, fixture `dist/` and `build/`). The local HTTP server
is used for download-path tests; no external network is required after
dependencies are downloaded.

`integration/run.sh` drives a C NIF through the full flow: `init`, `package`,
`manifest`, a local HTTP download of the artifact, a consumer load, cache hits,
offline mode, a read-only `NIFFLER_ARTIFACT_DIR`, tampered-artifact rejection,
`verify`, `smoke`, `generate --check`, `doctor`, actionlint on the generated
workflow, and `hex check`/`hex emit`. `integration/rust.sh` verifies the
`NIFFLER_BUILD=1` source fallback, including its offline cache hit.
`integration/musl.sh` builds a C NIF with Alpine's toolchain and loads it with
the Alpine Erlang/OTP build, proving the musl path; CI runs it in the
`musl-smoke` job through an `alpine:3.22` container.

CI also runs `actionlint` on `.github/workflows/*.yml` and `shellcheck` on
shell scripts (through `nix shell`).

## CLI during development

Run the CLI straight from the checkout:

```sh
gleam run -m niffler_precompiled -- --help
gleam run -m niffler_precompiled -- doctor
gleam run -m niffler_precompiled -- hex check
```

The CLI runs on the Erlang target only. If the project's default target is
JavaScript, pass `--target erlang`.

Build and exercise the escript:

```sh
bash scripts/build_escript.sh
./niffler.escript --version
./niffler.escript doctor
```

`scripts/build_escript.sh` compiles the project, then bundles the application
and `gleam_stdlib` ebin directories into a self-contained escript with
`nix/build_escript.escript` (entry module `niffler_precompiled_escript`). The
escript is the artifact used by the Nix package and by CI smoke checks.

## Nix

```sh
nix build .#niffler
./result/bin/niffler --version
nix run .# -- doctor
nix flake check
nix fmt
```

The Nix package builds the escript from `src/` with a vendored `gleam_stdlib`
path dependency (v1.0.5), so the build needs no Hex cache. The wrapper puts the
pinned `gleam`, `erlang`, `git`, `cargo`, `rustc`, and `curl` on `PATH`; the CLI
shells out to those tools for `init`, `build`, `manifest`, and Hex commands.
The devShell, package, app, check, and formatter are exposed for
`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`.

## Source layout

| Path | Contents |
| --- | --- |
| `src/niffler_precompiled.gleam` | Runtime API (`artifact_path/1`, `prefetch/1`, `info/1`) and CLI entry point `main/0`. |
| `src/niffler_precompiled/` | Runtime and CLI modules: config/TOML, JSON, manifest, platform detection, archive validation, HTTP fetch, cache, source build, loader and workflow templates, errors. |
| `src/niffler_precompiled_ffi.erl` | Erlang FFI: OTP facts, files, hashes, HTTP/TLS, tar, subprocesses. Kept dependency-free beyond OTP. |
| `src/niffler_precompiled_escript.erl` | Entry module for the standalone escript. |
| `test/` | gleeunit unit tests for the parsers, validators, platform logic, manifest, and FFI helpers. |
| `integration/` | Fixture projects and shell suites. |
| `nix/`, `scripts/` | Nix derivation, escript builder, and helper script. |

Package metadata lives in `gleam.toml`. The version appears in three places and
must match: `version` in `gleam.toml`, `pub const version` in
`src/niffler_precompiled.gleam` (the runtime API value), and the literal
returned by `version()` in `src/niffler_precompiled/cli.gleam` (the
`niffler --version` output).

## Verification status

Only Linux x86_64 is exercised locally in this repository. The unit suite, the
CLI, and the Linux x86_64 integration fixture can be run on a developer
machine; the macOS, Windows, and musl targets, and the aarch64 runners, are
verified by CI and by the generated release workflow. When a change touches
platform selection, the download path, or the release matrix, say which target
was tested locally and which is CI-only.

## Release process

niffler itself is released from tags:

1. Bump `version` in `gleam.toml`, `pub const version` in
   `src/niffler_precompiled.gleam`, and the `version()` literal in
   `src/niffler_precompiled/cli.gleam`.
2. Update `CHANGELOG.md`.
3. Run the checks above, `bash integration/run.sh`, and `bash integration/rust.sh`
   locally; make sure CI is green.
4. Commit, then tag and push:

   ```sh
   git tag v1.2.3
   git push origin v1.2.3
   ```

5. The repository release workflow runs the checks, builds the escript and
   smoke-tests it, exports the Hex tarball, publishes the Hex package with
   `HEXPM_API_KEY`, and creates a GitHub release with the escript, the Hex
   tarball, and their SHA-256 files. It first verifies that the tag matches
   `gleam.toml` and `pub const version`; update the CLI `version()` literal
   before tagging, since the workflow does not check it.

Keep `gleam.toml`, the runtime version constant, the changelog, and the tag in
sync; a mismatch makes `niffler --version`, the manifest version, and the Hex
metadata disagree.
