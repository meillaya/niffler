# Changelog

## 0.1.0

- Initial release. Hex package `niffler_precompiled`, CLI and escript
  `niffler`.
- Precompiled Rust NIF distribution for Gleam: package authors build
  per-platform artifacts in CI, commit a SHA-256 manifest, and users load the
  verified library without Mix, Elixir, or a Rust toolchain.
- Seven release targets: linux-gnu and linux-musl on x86_64 and aarch64, macOS
  on x86_64 and aarch64, and Windows x86_64 MSVC.
- `priv/niffler.json` manifest (schema version 1) pinning the SHA-256 and size
  of the extracted NIF library, with deterministic encoding and `--check`
  modes.
- Generated Erlang `-on_load` loader at `src/<module>.erl` with stubs for every
  configured NIF function.
- Runtime artifact resolution: platform detection and overrides, NIF version
  selection (2.14–2.18, 2.15 Rustler default), HTTPS download with certificate
  and hostname verification, manual redirects, size limits, strict
  single-member tar validation, exact hash verification before loading, and
  fail-closed errors.
- Content-addressed user cache with atomic writes, mode `0700` directories,
  corrupt-entry detection, and `NIFFLER_CACHE_DIR` override.
- Read-only `NIFFLER_ARTIFACT_DIR` support for air-gapped and image-baked
  deployments, and `prefetch` to populate either the cache or that layout.
- Opt-in `NIFFLER_BUILD=1` source fallback: builds the bundled crate with
  `cargo --release --locked` into a source-fingerprint cache directory.
- CLI: `init`, `generate`, `build`, `package`, `manifest`, `verify`,
  `prefetch`, `doctor`, `cache`, `smoke`, `hex check`, `hex emit`, with
  `--json`, `--check`, `--dry-run`, and `--force` where applicable.
- `init` scaffolds `niffler.toml`, the Rust crate, the loader, and a
  seven-target GitHub Actions release workflow; `generate` keeps the loader
  and workflow in sync (`generate --check` for CI).
- `build` detects the effective Rustler NIF version from `cargo tree`, packages
  deterministic `.tar.gz` artifacts, and smoke-loads host builds. `package`
  wraps externally built libraries.
- Hex packaging gate: validates `gleam.toml` metadata, manifest/config/loader
  consistency, required `priv/` contents, absence of compiled libraries, the
  `gleam export hex-tarball` structure and checksum, and Hex size limits.
  `hex emit` writes the publishable tarball without uploading.
- Generated release workflow with a seven-target build matrix, smoke tests,
  GitHub build provenance attestations, a draft-then-publish GitHub release,
  and an optional Hex job gated by `NIFFLER_PUBLISH_HEX` and `HEXPM_API_KEY`.
- Nix flake and devenv shell, packaged CLI escript, and cross-platform CI for
  OTP 28/29.
- Apache-2.0 licence.
