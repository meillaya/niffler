# Usage

## Install and invoke

Package authors add niffler as a normal dependency. It provides the CLI, the
runtime that resolves and verifies artifacts, and the generated loader module.

```sh
gleam add niffler_precompiled
```

Run commands from the package root on the Erlang target:

```sh
gleam run -m niffler_precompiled -- <command>
```

Add `--target erlang` when the project's default target is JavaScript. The CLI
does not run on the JavaScript target.

Commands use the current working directory as the project root and do not
search parent directories, so run them from the package root (or set
`NIFFLER_ROOT`).

A standalone escript is available for CI and machines without a project
checkout:

```sh
bash scripts/build_escript.sh
./niffler.escript <command>
```

The Nix package exposes the same CLI as `niffler`; see
[development](development.md). In the examples below
`gleam run -m niffler_precompiled --` is shortened to `niffler`.

## Options and exit codes

`--help`/`-h` prints help and `--version`/`-V` prints `niffler <version>`.
Each command documents its own flags; flags accept both `--flag value` and
`--flag=value`. There are no other global options in 0.1.0.

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Success. |
| 1 | Command failure: a check failed, a build failed, verification found a problem, a required flag is missing, or a flag has no value. |
| 2 | Usage error: unknown command or subcommand, or a subcommand missing its required options (for example `cache clean` without `--all`/`--package`). |

## `init`

```text
niffler init --repo owner/repository [options]
```

Scaffolds a package. `--repo` is a GitHub `owner/repository` slug and becomes
the release download source.

| Option | Default | Meaning |
| --- | --- | --- |
| `--repo <OWNER/REPO>` | required | GitHub repository that hosts release assets. |
| `--crate <NAME>` | `<package>_nif` | Rust crate name. |
| `--module <NAME>` | the crate name | NIF module name passed to `rustler::init!`. |
| `--functions <LIST>` | `add/2` | Comma-separated `name/arity` list, for example `add/2,version/0`. |
| `--targets <LIST>` | all seven | Comma-separated target triples to build and publish. |
| `--no-example` | off | Do not generate the worked `add/2` example function. |
| `--force` | off | Overwrite files that already exist. |
| `--dry-run` | off | Print the files that would be written without writing them. |

`init` requires `gleam.toml` with `target = "erlang"` and writes:

- `niffler.toml` with `[nif]` and `[release]` tables.
- `priv/niffler.json` with an empty artifact list and the derived base URL.
- `src/<module>.erl`, the generated loader.
- `priv/native/<crate>/Cargo.toml`, `src/lib.rs`, `README.md`, and
  `.cargo/config.toml` (which disables static CRT linking for the musl
  targets).
- `rust-toolchain.toml` at the project root.
- `.github/workflows/niffler-release.yml`, the release workflow for the
  configured targets.
- A `Cargo.lock` when `cargo` is on `PATH`; the command warns and continues
  when `cargo generate-lockfile` fails. It is skipped silently when cargo is
  not installed.
- `.gitignore` entries for `/dist/`, `priv/native/*/target`, and
  `niffler.escript`.

Existing files are not overwritten unless `--force` is passed; with `--force`
they are replaced. The command prints the files it created and next steps,
including trying `NIFFLER_BUILD=1 gleam test` for a local source build.

## `generate`

```text
niffler generate [--check]
```

Regenerates the loader `src/<module>.erl` and
`.github/workflows/niffler-release.yml` from `niffler.toml`. Run it after
changing the module name, the function list, or the targets.

`--check` writes nothing and exits 1 when either file is stale or missing. Use
it in CI to keep generated files in sync.

## `build`

```text
niffler build [--target TARGET]... [--dist DIR] [--use-cross] [--no-smoke]
```

Builds the Rust crate and packages the result as canonical artifacts.

| Option | Default | Meaning |
| --- | --- | --- |
| `--target <TRIPLE>` | host target | Repeatable. Target triple to build. |
| `--dist <DIR>` | `<root>/dist` | Output directory for artifacts. |
| `--use-cross` | off | Build through [`cross`](https://github.com/cross-rs/cross) instead of `cargo`. |
| `--no-smoke` | off | Skip the host smoke load. |

The build always runs `cargo build --release --locked --target <triple>
--manifest-path priv/native/<crate>/Cargo.toml --target-dir <root>/dist/target`.
Release mode is always used; a `--release` flag is accepted but does not change
the profile. A `Cargo.lock` is required because of `--locked`; `init` generates
one. The effective NIF version is read from the Rustler version selected by
`cargo tree` (the highest `nif_version_2_XX` feature); when that cannot be
detected, the configured `nif_version` or the default 2.15 is used.

Each built library is packed into a `.tar.gz` in `dist/` and the artifact path
is printed. When the built target is the host, the artifact is smoke-loaded
unless `--no-smoke` is given. The smoke load needs `erlc` and `erl` on `PATH`.
`--use-cross` requires the `cross` executable; the command otherwise fails
before compiling.

## `package`

```text
niffler package [--target TARGET] [--binary PATH] [--nif-version VERSION] [--dist DIR]
```

Packages an existing `.so`, `.dylib`, or `.dll` into the canonical tarball. Use
it when the library was compiled outside `niffler build`, for example by a
custom cross toolchain.

| Option | Default | Meaning |
| --- | --- | --- |
| `--target <TRIPLE>` | host target | Target triple the library was built for. |
| `--binary <PATH>` | search | Library to package. |
| `--nif-version <VERSION>` | config or 2.15 | NIF version to record in the filename. |
| `--dist <DIR>` | `<root>/dist` | Output directory. |

Without `--binary`, niffler looks for `lib<crate>.so`/`lib<crate>.dylib` (or
`<crate>.dll`) in:

```text
dist/target/<target>/release/
dist/target/release/
target/<target>/release/
target/release/
```

and reports the searched directories when nothing is found.

The tarball contains exactly one member, named `<crate>.so` on Linux and macOS
and `<crate>.dll` on Windows. Its name is
`<libprefix><crate>-v<version>-nif-<nifver>-<target>.<ext>.tar.gz`, where
`libprefix` is `lib` on Unix and empty on Windows. The command prints the
tarball path, the SHA-256 of the tarball (the download asset), and the SHA-256
of the inner NIF library (the value recorded in the manifest).

## `manifest`

```text
niffler manifest [--dist DIR] [--base-url URL] [--version VERSION] [--check] [--json] [--allow-insecure]
```

Recomputes `priv/niffler.json` from the canonical tarballs in `dist/`. Package
name and version are read with `gleam export package-information`. The base URL
must normally be `https://`; `--allow-insecure` exists only for the integration
harness and local HTTP fixtures.

| Option | Default | Meaning |
| --- | --- | --- |
| `--dist <DIR>` | `<root>/dist` | Directory containing canonical artifact tarballs. |
| `--base-url <URL>` | config or GitHub | Prefix used to build artifact download URLs. |
| `--version <VERSION>` | `gleam.toml` version | Package version to record. It must match the `gleam.toml` version and the artifact filenames; the generated release workflow passes the tag value here. |
| `--check` | off | Do not write; exit 1 if the committed manifest differs or artifacts are missing. |
| `--json` | off | Print the manifest to stdout and do not write a file. |
| `--allow-insecure` | off | Permit an `http://` base URL in the manifest. Test-only; the loader still needs `NIFFLER_ALLOW_INSECURE_URLS=1` and loopback to download it. |

Every target configured in `niffler.toml` must have at least one artifact in
`dist/`, otherwise the command fails with the missing targets. Artifact files
are recognised by their canonical name; each filename's version must equal the
`gleam.toml` package version. For each artifact, niffler extracts the single
`<crate>.<ext>` member and records the SHA-256 and byte size of that inner
library, not of the tarball.

The base URL is chosen in this order:

1. `--base-url`.
2. `[release] base_url` in `niffler.toml`.
3. `https://github.com/<repo>/releases/download/v<version>`.

The written manifest is deterministic: keys are sorted, artifacts are sorted
by target and NIF version, and the file ends with a newline, so `--check` works
as a CI gate. See [design](design.md) for the schema.

## `verify`

```text
niffler verify [--dist DIR] [--manifest PATH] [--online]
```

Every artifact in the manifest must have a matching tarball in the dist
directory, the tarball must contain exactly one `<crate>.<ext>` member, and
that member's SHA-256 and size must match the manifest. Failures are printed as
`FAIL <file>: <reason>` and the command exits 1.

`--online` verifies artifacts that are missing from the local dist directory by
downloading them through the same HTTP code the runtime uses and hashing the
extracted library. Without downloaded or local tarballs, offline verification
fails for those artifacts.

`--manifest` defaults to `priv/niffler.json` and `--dist` defaults to
`<root>/dist`.

## `prefetch`

```text
niffler prefetch [--manifest PATH] [--all] [--to-dir DIR]
```

Populates the runtime artifact cache ahead of deployment so the first NIF load
does not need the network.

| Option | Default | Meaning |
| --- | --- | --- |
| `--manifest <PATH>` | `priv/niffler.json` | Manifest to read. |
| `--all` | off | Download every artifact instead of only the current platform's. |
| `--to-dir <DIR>` | off (write to cache) | Write flat `<sha256>.<so\|dll>` files to DIR instead of the cache. |

Without `--all`, the current target and runtime NIF version are used to select
one artifact. Extracted libraries are named by the manifest SHA-256, so a
`--to-dir` directory can be shipped read-only to other machines and consumed
through `NIFFLER_ARTIFACT_DIR`. Each downloaded artifact's path is printed.

Each downloaded inner library is checked against the manifest SHA-256 and
size before it is written; a mismatch fails the command. Cache entries and
artifact-directory files are hash-checked again by the runtime when used.

## `doctor`

```text
niffler doctor
```

Prints diagnostics and always exits 0:

- niffler version, current directory;
- OTP release, NIF version, architecture, wordsize;
- cache root, offline and source-build flags;
- detected host target;
- `cargo` and `gleam` availability;
- package name/version, `niffler.toml` module, source crate path and presence,
  loader presence, manifest artifact count and version, and the artifact
  selected for the current platform (if any).

It reports problems in its output rather than failing; use `verify` or
`hex check` for gates. There is no JSON output in 0.1.0.

## `cache`

```text
niffler cache path
niffler cache list
niffler cache clean --all
niffler cache clean --package PACKAGE
```

- `path` prints the cache root.
- `list` prints the cached artifact file paths, sorted. It does not print
  sizes.
- `clean --all` removes the whole cache directory.
- `clean --package <name>` removes that package's source-build directory and
  the shared cached artifact files under `artifacts/` (that directory is not
  partitioned per package).

`niffler cache` with no subcommand prints the cache path. `clean` requires
either `--all` or `--package`; anything else is a usage error (exit 2).

Corrupted cache entries are also detected and discarded by the runtime. Run
`cache clean` when a checksum error suggests a bad cached file.

## `smoke`

```text
niffler smoke [--artifact FILE] [--module NAME]
```

Loads a packaged artifact in a temporary Erlang VM:

1. extracts the single `<crate>.<ext>` member into `dist/.smoke-<id>/`;
2. writes and compiles a loader module (the configured module name by
   default) with `erlc`;
3. runs `erl -noshell -pa <dir> -eval "<module>:niffler_smoke(), halt(0)."`.

`--artifact` selects the tarball; without it, the first `.tar.gz` in `dist/` is
used, so pass `--artifact` when the directory contains several targets. The
artifact must be loadable in the local VM (build the host target or use a
matching container). `--module` overrides the loader name from `niffler.toml`.
Failure exits 1. Requires `erlc` and `erl` on `PATH`. `niffler build` runs the
same smoke load automatically for host builds.

## `hex check`

```text
niffler hex check [--manifest PATH] [--online]
```

Runs the pre-publish gate. It checks that:

- the project targets Erlang and has a `gleam.toml` description, at least one
  licence, and a README;
- `priv/niffler.json` matches `gleam.toml` on package name and version, and
  matches `niffler.toml` on module and crate;
- the manifest has artifacts and covers every configured target;
- the generated loader exists and calls
  `niffler_precompiled:artifact_path`;
- `priv/` contains neither compiled `.so`/`.dll`/`.dylib` files nor a cargo
  `target/` directory;
- the Rust crate at `priv/native/<crate>/` has both `Cargo.toml` and
  `Cargo.lock`;
- `gleam export hex-tarball` succeeds and the produced Hex tarball is under
  the 16 MiB compressed limit (with a warning above 8 MiB), stays under the
  128 MiB uncompressed limit, has at most 10,000 entries and no path longer
  than 255 bytes, has `VERSION`, `metadata.config`, `contents.tar.gz`, and
  `CHECKSUM`, names the package/version and `gleam` in its metadata, contains
  `priv/niffler.json`, `priv/native/<crate>/Cargo.toml`,
  `priv/native/<crate>/Cargo.lock`, and `src/<module>.erl`, contains no
  `.so`/`.dll`/`.dylib` files, and has a recomputed `CHECKSUM` that matches its
  parts.

`--online` additionally downloads every artifact and verifies the extracted
library hash. It does not query Hex for name or version availability.

`hex check` normalises `priv/niffler.json` before exporting: it re-encodes the
manifest it is validating (from `--manifest`, default `priv/niffler.json`) and
writes that back to `priv/niffler.json`. The write is idempotent when the file
already matches, and it guarantees the exported tarball contains exactly the
manifest that is being validated.

## `hex emit`

```text
niffler hex emit [--manifest PATH] [--output PATH]
```

Runs the `hex check` validations, writes the validated manifest into
`priv/niffler.json` (an explicit `--manifest` overrides the committed file),
exports the Hex tarball with `gleam export hex-tarball`, and copies it to
`dist/hex/<package>-<version>.tar` with a `.sha256` file next to it. The
output path can be overridden with `--output`. The command prints the tarball
path, its SHA-256, and the `gleam publish --yes` step. It never uploads.

## Environment variables

The runtime reads these variables; CLI commands use the ones marked with a
role.

| Variable | Used by | Meaning |
| --- | --- | --- |
| `NIFFLER_CACHE_DIR` | runtime, `cache` | Cache root. Defaults to the OS user cache directory for `niffler` (`$XDG_CACHE_HOME/niffler` or `~/.cache/niffler` on Linux, `~/Library/Caches/niffler` on macOS, LocalAppData on Windows). |
| `NIFFLER_ARTIFACT_DIR` | runtime | Path list (colon-separated on Unix, semicolon-separated on Windows) of directories containing flat `<sha256>.<so\|dll>` extracted libraries. Checked before the cache and downloads; may be read-only. Every hit is hashed against the manifest. |
| `NIFFLER_OFFLINE` | runtime | `1` or `true` disables all network access for the runtime loader. A missing artifact then fails instead of downloading. |
| `NIFFLER_BUILD` | runtime | `1` or `true` builds the bundled crate with `cargo` instead of resolving precompiled artifacts. |
| `NIFFLER_BASE_URL` | runtime | Replaces the manifest base URL prefix when the loader builds an artifact URL. Hashes are still verified. |
| `NIFFLER_ALLOW_INSECURE_URLS` | runtime, CLI downloads | `1` permits plain HTTP only for loopback hosts. Test-only; never use it in production. |
| `NIFFLER_CACERTS` | runtime, CLI downloads | Path to a PEM CA bundle used for HTTPS. Defaults to the OS CA store via `public_key:cacerts_get()`. |
| `NIFFLER_TARGET` | runtime | Forces the Rust target triple for artifact selection. Must be one of the supported targets. |
| `TARGET_ARCH` | runtime | Overrides the architecture component of target detection. |
| `TARGET_VENDOR` | runtime | Overrides the vendor component. |
| `TARGET_OS` | runtime | Overrides the OS component. |
| `TARGET_ABI` | runtime | Overrides the ABI component (`gnu`, `musl`, `msvc`). |
| `NIFFLER_CARGO` | runtime | `cargo` executable to use for source-fallback builds. |
| `NIFFLER_GLEAM` | CLI | `gleam` executable to use when reading package information and exporting Hex tarballs. Defaults to `gleam` on `PATH`. |
| `NIFFLER_ROOT` | CLI | Project root for CLI commands. Defaults to the current working directory; no parent-directory search is performed. |

`NIFFLER_TARGET` and the `TARGET_*` variables are read by the runtime loader,
not by CLI target detection. They exist for Nerves and cross-built systems
where OTP reports an unusual architecture string. Set `NIFFLER_TARGET` unless
you specifically need to correct one component.

## Runtime behavior

The generated loader module has an `-on_load` hook. When the module loads:

1. The runtime detects the platform and target triple.
2. It finds `priv/niffler.json` for the package, validates it, and checks the
   package name and version against the installed application.
3. It selects the artifact for the target with the highest NIF version the
   current VM can load.
4. Candidate files from `NIFFLER_ARTIFACT_DIR`, then the cache, are used when
   present; cache entries are re-hashed and size-checked. Otherwise the
   artifact is downloaded over HTTPS, the archive is validated and its single
   `<crate>.<ext>` member is extracted, and the extracted bytes are checked
   against the manifest SHA-256 and size before being cached.
5. The cached library is loaded with `erlang:load_nif/2`. With
   `NIFFLER_BUILD=1` the runtime skips artifact resolution and builds the
   bundled crate with `cargo` into the cache instead.
6. If anything fails, the module raises with an actionable message and the NIF
   is not loaded.

`niffler` logs nothing during a normal load. Set `NIFFLER_OFFLINE=1` in
production after running `prefetch`; a missing artifact then fails fast
instead of contacting the release host. Loading happens once per OS process.

## Runtime errors

A failed load raises from the generated module's `-on_load` callback and
prevents the module from loading. Messages are prefixed with `niffler:` and
name the package where relevant.

| Condition | What the user can do |
| --- | --- |
| `priv/niffler.json` is missing or invalid | Reinstall the package; the installed files are incomplete or corrupted. |
| Package name or version mismatch | Reinstall or restore the lockfile; the manifest and `.app` version disagree. |
| Target not detected or unsupported | Check the platform; set `NIFFLER_TARGET` for Nerves/cross systems, or enable `NIFFLER_BUILD=1`. |
| No artifact for the target | Check the package's target list; enable `NIFFLER_BUILD=1` on unsupported platforms. |
| No compatible NIF version | Upgrade Erlang/OTP, use a package version that ships a compatible artifact, or enable `NIFFLER_BUILD=1`. |
| Artifact missing while offline | Run `niffler prefetch` first, or provide `NIFFLER_ARTIFACT_DIR`. |
| HTTP/network/status error | Check connectivity and the release URL, then retry. There is no HTTP proxy support in 0.1.0. |
| Checksum or size mismatch | The download is rejected; run `niffler cache clean` and retry. Do not ignore it. |
| Archive invalid | The release asset is malformed or not from this package; reinstall or report it. |
| Cache write failure | Check permissions and free space, or set `NIFFLER_CACHE_DIR` to a writable directory. |
| Source crate missing, cargo missing, or build failed | Install Rust/cargo and verify the package ships `priv/native/<crate>/`; `NIFFLER_CARGO` can point at a cargo binary. |
| `erlang:load_nif/2` failure | The library loaded but the VM rejected it; check the NIF ABI version and the loader/module name. |

Set `NIFFLER_OFFLINE=1` only after prefetching; otherwise a missing artifact is
an error by design rather than a silent download attempt.
