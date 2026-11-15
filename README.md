# niffler

Precompiled Rust NIF distribution for Gleam packages.

niffler is the Gleam analogue of Elixir's `rustler_precompiled`. A package
author builds per-platform NIF artifacts once in CI, publishes a manifest of
SHA-256 hashes inside the Hex package, and Gleam users load the verified
artifact with no Mix, no Elixir, and no Rust toolchain. The Hex package also
carries the Rust crate source (required for source fallback); the compiled
libraries themselves are downloaded from the release host at runtime. The Hex
package is `niffler_precompiled`; the CLI and escript are called `niffler`.

## For package users

Packages that use niffler are installed normally:

```sh
gleam add my_package
```

On first load the generated loader downloads the artifact for the current
platform, validates and extracts it, verifies the extracted NIF's SHA-256
against `priv/niffler.json`, caches it, and calls `erlang:load_nif/2`. A hash
mismatch fails closed; nothing is loaded.

Production and container deploys should populate the cache ahead of time and
run offline:

```sh
gleam add --dev niffler_precompiled
gleam run -m niffler_precompiled -- prefetch
NIFFLER_OFFLINE=1
```

See [usage](docs/usage.md) for the runtime environment variables and cache
layout.

## For package authors

```sh
gleam add niffler_precompiled
gleam run -m niffler_precompiled -- init --repo owner/my_package
# Write the Rust crate under priv/native/<crate>/ and the Gleam @external
# wrappers, then edit niffler.toml if the defaults need changing.
gleam run -m niffler_precompiled -- generate
gleam run -m niffler_precompiled -- build
gleam run -m niffler_precompiled -- manifest
gleam run -m niffler_precompiled -- hex check
gleam publish
```

`init` also generates `.github/workflows/niffler-release.yml`. Pushing a
`v<version>` tag builds all configured targets, writes the manifest, publishes
the artifact assets on the GitHub release, and optionally publishes to Hex when
a `HEXPM_API_KEY` secret and `NIFFLER_PUBLISH_HEX=true` variable are set. See
[authoring](docs/authoring.md), [releasing](docs/releasing.md), and
[design](docs/design.md).

## Supported platforms

| Target triple | Platform | Extension | Verified by |
| --- | --- | --- | --- |
| `x86_64-unknown-linux-gnu` | Linux glibc, x86_64 | `.so` | local + CI |
| `aarch64-unknown-linux-gnu` | Linux glibc, aarch64 | `.so` | CI |
| `x86_64-unknown-linux-musl` | Linux musl/Alpine, x86_64 | `.so` | CI |
| `aarch64-unknown-linux-musl` | Linux musl/Alpine, aarch64 | `.so` | CI |
| `x86_64-apple-darwin` | macOS Intel | `.so` | CI |
| `aarch64-apple-darwin` | macOS Apple silicon | `.so` | CI |
| `x86_64-pc-windows-msvc` | Windows x64, MSVC | `.dll` | CI |

Only Linux x86_64 has been exercised locally in this repository. macOS,
Windows, musl, and aarch64 are CI targets. Windows ARM64, 32-bit targets, and
other operating systems are not supported.

## NIF versions

New packages default to NIF version 2.15, which is Rustler 0.39's default and
loads on OTP 22 and newer. Packages that need a newer NIF API can publish
2.17 (OTP 26+) or 2.18 (OTP 29+) artifacts, and may ship several versions at
once; the loader selects the highest compatible version at runtime. niffler's
own runtime requires Gleam 1.19+ and Erlang/OTP 28+.

## Security

- `priv/niffler.json` ships inside the immutable Hex release and pins every
  artifact by the SHA-256 of its extracted NIF library; the release host
  cannot substitute content.
- Downloads use HTTPS with the OS CA store, manual redirect handling, a size
  limit, strict single-member tar validation, and an exact hash check of the
  extracted NIF before it is cached or loaded.
- A missing or mismatched artifact fails closed. There is no unsigned fallback.
- `NIFFLER_BUILD=1` opts into a local `cargo` build instead of downloading an
  artifact; it is outside the manifest's integrity guarantees.
- 0.1.0 does not fetch or verify build provenance attestations at runtime.

See [security](docs/security.md) for the threat model and residual risks.

## Requirements

Authoring needs Gleam 1.19+, Erlang/OTP 28+, and a Rust toolchain with Rustler
0.39. Consumers need the Erlang target, Gleam 1.19+, Erlang/OTP 28+, a 64-bit
system, and network access to the release host on first load. The CLI runs on
the Erlang target (`gleam run -m niffler_precompiled -- <command>`) or as a
standalone escript (`bash scripts/build_escript.sh`, then
`./niffler.escript <command>`).

## Documentation

- [Authoring guide](docs/authoring.md)
- [CLI and runtime reference](docs/usage.md)
- [Security model](docs/security.md)
- [Design and manifest format](docs/design.md)
- [Releasing](docs/releasing.md)
- [Limits and non-goals](docs/limitations.md)
- [Development](docs/development.md)

## Licence

Apache-2.0. See [LICENCE](LICENCE).
