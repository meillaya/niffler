# Authoring guide

This walks a package author from an empty Gleam package to a published Hex
release with precompiled NIFs for every supported platform.

## Requirements

- Gleam 1.19 or newer and Erlang/OTP 28 or newer.
- Rust stable with `cargo` and `rustc`. The generated crate uses Rustler 0.39.
- `erlc` and `erl` for the host smoke load after `niffler build`.
- A GitHub repository, because the default artifact host is GitHub Releases.
- A Gleam package that targets Erlang and has a `gleam.toml` description,
  licences, README, and repository link (the Hex packaging check requires
  them).

## 1. Add the dependency

```sh
gleam add niffler_precompiled
```

This adds `niffler_precompiled` as a runtime dependency. The generated loader
calls into it, so it must not be a dev-dependency.

## 2. Scaffold

```sh
gleam run -m niffler_precompiled -- init --repo owner/demo
```

With no other options, `init` uses `<package>_nif` for the crate, the crate
name for the NIF module, and creates an `add/2` example. Useful options:

```sh
# Different names, no worked example
gleam run -m niffler_precompiled -- init \
  --repo owner/demo --crate demo_nif --module demo_nif \
  --functions "add/2,version/0" --no-example

# Restrict the release matrix
gleam run -m niffler_precompiled -- init \
  --repo owner/demo --targets "x86_64-unknown-linux-gnu,aarch64-apple-darwin"
```

`init` writes:

```text
niffler.toml
priv/niffler.json
priv/native/<crate>/Cargo.toml
priv/native/<crate>/Cargo.lock          (when cargo is available)
priv/native/<crate>/src/lib.rs
priv/native/<crate>/README.md
priv/native/<crate>/.cargo/config.toml
src/<module>.erl
rust-toolchain.toml                       (project root)
.github/workflows/niffler-release.yml
```

It also appends `/dist/`, `priv/native/*/target`, and `niffler.escript` to
`.gitignore`, and prints next steps. Existing files are not overwritten unless
`--force` is passed. `--dry-run` lists the files that would be written.

The generated `.cargo/config.toml` disables static CRT linking for the two
musl targets, which is what a `cdylib` needs. `rust-toolchain.toml` pins the
Rust toolchain used by cargo.

## 3. Configure `niffler.toml`

```toml
[nif]
module = "demo_nif"
crate = "demo_nif"
# path = "priv/native/demo_nif"   # optional; defaults to priv/native/<crate>
functions = ["add/2", "version/0"]
# nif_version = "2.15"            # optional; fallback when detection fails

[release]
repo = "owner/demo"
# targets = [...]                 # optional; defaults to all seven targets
# base_url = "https://..."        # optional custom artifact host
```

Validation rules:

- `module` and `crate` match `[a-z][a-z0-9_]*`.
- `path` must be relative and under `priv/`, because only `priv/` is shipped
  inside the Hex tarball. Trailing slashes are removed; `..`, backslashes, and
  absolute paths are rejected.
- `functions` entries look like `name/arity` with arity 0–255. `init/0` is
  reserved for the generated loader, `module_info` is reserved by the Erlang
  compiler, and duplicates are rejected. Names match the functions registered
  by `rustler::init!`.
- `nif_version` must be a supported NIF version (2.14–2.18). It is a fallback
  for `build`, which normally reads the effective version from Cargo features,
  and the default for `package`. Unset means the Rustler default, 2.15.
- `repo` is `owner/repository`.
- `targets` must be supported target triples with no duplicates.
- `base_url` must be an `https://` URL. Leave it unset to derive
  `https://github.com/<repo>/releases/download/v<version>` from the package
  version each time; if you set it, remember that it is a fixed prefix and must
  be updated when the version path changes.

Unknown keys and nested tables are rejected by the small built-in TOML parser.
Keep the generated file simple.

## 4. Write the Rust crate

The crate lives at `priv/native/<crate>/`. Its `Cargo.toml` must build a
`cdylib`; the generated file already has the right shape:

```toml
[package]
name = "demo_nif"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
rustler = "0.39"

[profile.release]
lto = true
```

`src/lib.rs` registers the NIF module with Rustler's one-argument `init!`:

```rust
use rustler::NifResult;

#[rustler::nif]
fn add(a: i64, b: i64) -> NifResult<i64> {
    Ok(a + b)
}

#[rustler::nif]
fn version() -> NifResult<String> {
    Ok(env!("CARGO_PKG_VERSION").to_string())
}

rustler::init!("demo_nif");
```

The string passed to `init!` must equal `nif.module`, and every function in
`nif.functions` must be registered by the library. The Erlang VM rejects a NIF
library (`bad_lib`, "Function not found") when the loader does not export a
matching stub.

Commit `Cargo.lock`; `niffler build` uses `cargo build --locked` and the source
fallback also runs with `--locked`. The crate source is committed to the
repository and published inside the Hex package, which is what makes
`NIFFLER_BUILD=1` source fallback possible for users on unsupported platforms.

## 5. Write the Gleam externals

The loader is an Erlang module. Expose it to Gleam with `@external`:

```gleam
@external(erlang, "demo_nif", "add")
pub fn add(a: Int, b: Int) -> Int

@external(erlang, "demo_nif", "version")
pub fn version() -> String
```

The `@external` module name must equal `nif.module`, and the function names
must exist in the generated loader. Typed wrappers with validation or error
handling are the author's responsibility; niffler only generates the Erlang
bridge.

## 6. Regenerate and build locally

```sh
gleam run -m niffler_precompiled -- generate
gleam run -m niffler_precompiled -- build
```

`generate` rewrites `src/<module>.erl` and the release workflow from
`niffler.toml`. Run `generate --check` in CI to fail when the generated files
are stale.

`build` compiles the host target into `<root>/dist/target/<target>/release/`,
wraps it into a canonical tarball under `<root>/dist/`, prints the artifact
path, and smoke-loads it unless `--no-smoke`. To produce more platforms on a
capable machine:

```sh
gleam run -m niffler_precompiled -- build \
  --target x86_64-unknown-linux-gnu \
  --target aarch64-unknown-linux-gnu
```

For a cross toolchain, pass `--use-cross` to build through `cross`. On macOS
install the matching Rust target; on Windows use the MSVC toolchain. If you
built the library yourself, `niffler package --target <triple> --binary <path>`
wraps an existing `.so`/`.dylib`/`.dll`.

## 7. Write the manifest

```sh
gleam run -m niffler_precompiled -- manifest --dist dist
```

This reads package name and version with `gleam export package-information`,
scans `dist/` for canonical artifacts, and writes `priv/niffler.json` sorted
and deterministic. For every artifact it records the SHA-256 and size of the
inner NIF library, not of the tarball.

Every target configured in `niffler.toml` must have at least one artifact in
`dist/`, and each artifact filename's version must equal the `gleam.toml`
package version. If you only built the host locally, either pass a `--dist`
directory that contains the other tarballs, or temporarily restrict
`[release] targets` and regenerate when the full set is available.

```sh
# Verify the committed manifest matches dist/ without writing
gleam run -m niffler_precompiled -- manifest --check

# Inspect the JSON that would be written
gleam run -m niffler_precompiled -- manifest --json

# Custom hosting: override the download prefix
gleam run -m niffler_precompiled -- manifest \
  --base-url https://cdn.example.com/demo-nif/v1.2.3
```

Commit `priv/niffler.json`, the loader, `niffler.toml`, and the Rust crate.

## 8. Verify

```sh
# Manifest vs local dist/ artifacts
gleam run -m niffler_precompiled -- verify --dist dist

# Also download every artifact URL and check the inner NIF hash
gleam run -m niffler_precompiled -- verify --dist dist --online

# Runtime facts for the current machine
gleam run -m niffler_precompiled -- doctor
```

## 9. Check the Hex package

```sh
gleam run -m niffler_precompiled -- hex check
```

The check builds the real Hex tarball with `gleam export hex-tarball` and
inspects it: metadata, licences, README, the required `priv/` and `src/` files,
absence of compiled libraries, the 16 MiB compressed limit, and the recomputed
Hex checksum. It also checks that `niffler.toml`, `priv/niffler.json`,
`gleam.toml`, the loader, and the Rust crate agree. It first re-encodes the
manifest it is validating into `priv/niffler.json` (idempotent when already in
sync), so the tarball contains exactly the validated manifest.
`hex check --online` also downloads every artifact and verifies the inner NIF
hash.

To produce the publishable tarball explicitly:

```sh
gleam run -m niffler_precompiled -- hex emit
```

`hex emit` runs the same validations, writes the validated manifest into
`priv/niffler.json`, exports the tarball, and writes
`dist/hex/<package>-<version>.tar` plus a `.sha256` file. It prints the publish
command and never uploads. `--manifest <path>` lets CI emit using the manifest
downloaded from the GitHub release instead of the committed copy; the emitted
tarball always contains the manifest that was validated.

## 10. Publish

```sh
gleam publish
```

The Hex package contains the manifest, the loader, the Rust crate source, and
the package's normal files. It does not contain compiled libraries or `dist/`.

Tag-driven releases are the recommended path: `init` generated
`.github/workflows/niffler-release.yml`, and pushing a `v<version>` tag builds
all configured targets, writes the manifest, attaches the artifacts and
`niffler.json` to the GitHub release, and can publish to Hex through the
optional `hexpm` environment job. Regenerate the workflow after changing the
target list. See [releasing](releasing.md).

## Author checklist

- [ ] `niffler.toml` module, crate, and functions match `src/lib.rs`.
- [ ] `src/<module>.erl` regenerated after every function or target change
      (`generate --check` passes).
- [ ] Every configured target has exactly one artifact in `dist/`.
- [ ] `priv/niffler.json` committed and in sync with `dist/`
      (`manifest --check` passes).
- [ ] `Cargo.lock` committed; `niffler build` succeeds and the host smoke load
      passes.
- [ ] `verify --dist dist` and `hex check` pass locally.
- [ ] `gleam.toml` version bumped; the `v<version>` tag matches it.
- [ ] `.github/workflows/niffler-release.yml` committed, with secrets
      `HEXPM_API_KEY` and repository variable `NIFFLER_PUBLISH_HEX=true` when
      Hex publishing is enabled.
