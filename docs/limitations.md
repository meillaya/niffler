# Limits and non-goals

niffler targets 64-bit Erlang/Gleam systems with a Rustler-based NIF and a
GitHub Releases download source. Everything else is out of scope for 0.1.0.

## Platforms

niffler builds and loads artifacts for exactly seven targets:

- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu`
- `x86_64-unknown-linux-musl`
- `aarch64-unknown-linux-musl`
- `x86_64-apple-darwin`
- `aarch64-apple-darwin`
- `x86_64-pc-windows-msvc`

Not supported: Windows on ARM64, 32-bit x86 (`i686`) or 32-bit ARM, Linux on
RISC-V or other architectures, BSDs, and Windows MinGW targets. The runtime
detects the current target from OTP and refuses anything outside the list with
a clear error instead of attempting to load a mismatched binary.

Only Linux x86_64 has been exercised locally during development. macOS,
Windows, musl, and aarch64 results come from CI and the generated release
workflow; treat those as CI-verified, not hand-verified on real hardware.

Linux gnu artifacts are built on GitHub's Ubuntu runners. A system with an
older glibc than the runner image may fail to load the artifact even though the
target triple matches. Use the musl artifacts for fully static systems, or
build from source.

## One NIF module per package

`niffler.toml` declares exactly one `[nif]` module and one Rust crate. A
package that needs several independent NIF modules must publish them as
separate packages (or wrap several `niffler` packages). The generated loader
owns the module name, so a hand-written Erlang module with the same name
cannot coexist with it.

## Gleam only

The CLI and the generated loader are designed for Gleam projects. There are no
Mix tasks, no Elixir install helpers, and no assumptions about Elixir
tooling. The generated loader is plain Erlang and the runtime is a normal
Erlang library, but the authoring flow (`niffler.toml`, `gleam.toml`, Gleam
module externals, Hex packaging) is Gleam-specific.

## No compiled binaries in Hex

Hex packages carry the manifest (`priv/niffler.json`) and, when source
fallback is enabled, the Rust crate source under `priv/native/<crate>/`. The
compiled shared libraries are published as GitHub release assets. niffler does
not put `.so`/`.dll` files in the Hex tarball, does not run a server, and does
not provide its own artifact host.

## Downloads happen at first load

By default the runtime downloads an artifact the first time the generated
loader module is loaded. That requires network access to the release host and
a writable cache. Production deployments should run `niffler prefetch` during
the build or deploy step so the artifact is already in the cache, then set
`NIFFLER_OFFLINE=1` to make a missing artifact a hard failure. A first load
that hits a proxy, firewall, or GitHub outage fails closed with an error.

The cache is per user unless `NIFFLER_CACHE_DIR` is set. Containers that start
with an empty cache and no network will not load a precompiled NIF. Air-gapped
installs must vendor the artifacts and either populate the cache or set
`NIFFLER_ARTIFACT_DIR` to a directory of extracted libraries named
`<sha256>.<so|dll>` (the layout produced by `niffler prefetch --to-dir`).

## Source builds are a fallback

`NIFFLER_BUILD=1` builds the bundled crate with `cargo` when the package is
loaded. When enabled it takes precedence over precompiled artifacts and the
cache, so it builds from source even on a supported platform. It is intended
for unsupported platforms and local development, not as the normal
distribution path:

- Rust stable and a C toolchain must be installed on the target machine.
- `cargo` needs access to crates.io (or a vendored registry) unless all
  dependencies are cached.
- The build is not reproducible from the manifest: it is not covered by the
  release's SHA-256 pins and may compile different code if the crate source or
  dependency resolution changes.
- Builds are cached under a fingerprint of the crate source, but the cost is
  paid per machine and per cache directory.
- The crate is built locally and loaded like any other NIF, with full access
  to the VM.

## Runtime attestation verification

niffler 0.1.0 trusts the SHA-256 digest of the extracted NIF recorded in
`priv/niffler.json`. The generated release workflow attests artifact tarballs
with GitHub build provenance, and they can be checked manually with
`gh attestation verify <artifact> --repo owner/repo`, but the runtime does not
fetch or verify attestations, certificates, or signatures. The manifest stays
the only runtime trust anchor.

## Private repositories

Artifact downloads are unauthenticated. Release assets must be publicly
readable, so private GitHub repositories are not supported as an artifact host.
A private deployment can still use niffler by serving artifacts from a publicly
readable URL (`base_url`), or by mounting a read-only `NIFFLER_ARTIFACT_DIR`.

## NIF version floor

The package runtime requires Gleam 1.19+ and Erlang/OTP 28+, and the loader
requires the Erlang target. Artifacts default to NIF version 2.15 (Rustler
0.39's default, loadable on OTP 22+). A package that only ships artifacts for a
higher NIF version narrows its supported OTP range: 2.17 requires OTP 26+ and
2.18 requires OTP 29+. The runtime selects the newest compatible artifact, so
shipping 2.15 together with newer versions keeps older OTP releases working.

## Windows specifics

Only the MSVC ABI is supported. Linux and macOS libraries use the `.so`
extension and Windows uses `.dll`; OTP appends the platform extension when
loading. The generated workflow builds with the default Rust MSVC toolchain and
does not sign the DLL. Code signing and Windows Defender reputation are not
handled.

## Tooling limits in 0.1.0

- There are no global `--verbose` or `--quiet` flags. Only `manifest` has
  `--json`; `doctor` and `hex check` print plain text.
- HTTP proxy configuration is not implemented. Downloads use OTP `httpc`
  directly, so deployments behind a proxy need a transparent proxy or a
  pre-populated cache/artifact directory.
- `verify --online` downloads and hashes whole artifacts; it does not send HEAD
  requests or use partial downloads.
- `build --release` is accepted but release mode is always used. `build` has no
  `--nif-version`: it reads the effective version from the Rustler Cargo
  features and falls back to `[nif] nif_version` or 2.15. `package` does accept
  `--nif-version`.
- The generated release workflow smoke-loads native builds only. Cross-built
  musl artifacts are packaged, manifest-verified, and attested, but not loaded
  by that generated workflow.
- `hex check --online` verifies that artifact URLs serve the pinned bytes; it
  does not query Hex for name or version availability.
- `cache clean` requires `--all` or `--package <name>`; `cache list` prints
  paths only, without sizes.
- `doctor` reports problems but exits 0, and has no JSON output.

## Not a build system

niffler does not replace `cargo`, `rustler`, or `gleam`. It generates a
loader, packages artifacts, writes a manifest, and generates a release
workflow. Compiling the Rust crate, writing the Gleam externals, and publishing
to Hex remain the package author's responsibility.
