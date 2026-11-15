# Design

niffler separates what a package *is* from the compiled libraries it *loads*:

- The Hex tarball contains the manifest, the generated Erlang loader, the Rust
  crate source, and the package's normal files. It contains no compiled
  libraries.
- GitHub Releases contain one `.tar.gz` artifact per platform.
- The manifest inside the Hex tarball pins each artifact by the SHA-256 of the
  NIF shared library, and the runtime verifies it before loading.

## File layout in an author package

| Path | Committed | Purpose |
| --- | --- | --- |
| `niffler.toml` | yes | NIF module, crate, functions, NIF version, release settings. |
| `priv/niffler.json` | yes | Manifest shipped in the Hex package. |
| `priv/native/<crate>/` | yes | Rust crate: `Cargo.toml`, `Cargo.lock`, `src/`, toolchain config. |
| `src/<module>.erl` | yes | Generated loader module. |
| `src/<package>.gleam` | yes | Gleam `@external` wrappers written by the author. |
| `.github/workflows/niffler-release.yml` | yes | Generated release workflow. |
| `dist/` | no | Locally built artifact tarballs (gitignored). |
| `dist/hex/` | no | `hex emit` output (gitignored). |

Everything under `priv/` is shipped to Hex. That is why the manifest and the
Rust crate source must live there: the runtime finds `priv/niffler.json` with
`code:priv_dir/1`, and source fallback builds `priv/native/<crate>/`. The
`nif.path` configuration is validated to stay under `priv/` for this reason.
`niffler.toml` itself is tooling-only and stays at the project root.

## `niffler.toml`

```toml
[nif]
module = "demo_nif"
crate = "demo_nif"
path = "priv/native/demo_nif"   # optional
functions = ["add/2", "version/0"]
nif_version = "2.15"            # optional

[release]
repo = "owner/demo"
targets = ["x86_64-unknown-linux-gnu"]  # optional
base_url = "https://example.com/artifacts"  # optional
```

- `module`, `crate`: lowercase identifiers matching `[a-z][a-z0-9_]*`.
- `path`: relative path under `priv/`; defaults to `priv/native/<crate>`.
- `functions`: `name/arity` pairs (arity 0–255). `init/0` and `module_info` are
  reserved; duplicates are rejected. This list must match `rustler::init!`.
- `nif_version`: one of the supported NIF versions. Unset means the Rustler
  default used by the crate (2.15 for Rustler 0.39).
- `repo`: GitHub `owner/repository`, used for the default download URL.
- `targets`: subset of the supported target triples; defaults to all seven.
- `base_url`: optional `https://` prefix for artifact downloads. Unset derives
  `https://github.com/<repo>/releases/download/v<package version>`.

Unknown tables and keys are rejected. The parser is a small in-package TOML
reader; arrays, basic strings, literal strings, integers, and booleans are
supported, nested tables and arrays of tables are not.

## Manifest: `priv/niffler.json`

The schema version is 1. The encoded file is deterministic: JSON object keys
are sorted, artifacts are sorted by target then NIF version, and the file ends
with a newline. `manifest --check` and `generate --check` rely on this.

```json
{
  "artifacts": [
    {
      "file": "libdemo_nif-v1.2.3-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz",
      "nif_version": "2.15",
      "sha256": "5f0a6e1c8d4b2a9f7e3c1d8b6a4f2e0c9d7b5a3f1e8c6d4b2a0f9e7c5d3b1a8f",
      "size": 481232,
      "target": "x86_64-unknown-linux-gnu"
    }
  ],
  "base_url": "https://github.com/owner/demo/releases/download/v1.2.3",
  "nif": {
    "crate": "demo_nif",
    "module": "demo_nif",
    "source_path": "native/demo_nif"
  },
  "package": "demo",
  "schema_version": 1,
  "version": "1.2.3"
}
```

Fields:

| Field | Meaning |
| --- | --- |
| `schema_version` | Manifest format version. Only 1 is accepted. |
| `package` | Hex package name; must equal the installing application name. |
| `version` | Package version; must equal the installed application version. |
| `nif.module` | Erlang loader module name; must equal `rustler::init!`'s name. |
| `nif.crate` | Rust crate/library name; used for source builds and member checks. |
| `nif.source_path` | Crate path relative to `priv/`, for example `native/demo_nif`. |
| `base_url` | Download prefix; must be `https://` unless the test-only insecure flag is set. |
| `artifacts` | Non-empty list of platform artifacts. |

Each artifact has:

| Field | Meaning |
| --- | --- |
| `target` | One of the seven supported target triples. |
| `nif_version` | NIF version (`2.14`–`2.18`). |
| `file` | Canonical tarball file name, a plain basename. |
| `sha256` | SHA-256 of the **extracted NIF shared library**, not of the tarball. |
| `size` | Size in bytes of the **extracted NIF shared library**. |

Validation rejects invalid identifiers, unknown targets, unsupported NIF
versions, duplicate `(target, nif_version)` pairs, non-`https` base URLs
(outside the test override), non-plain file names, malformed SHA-256 values,
non-positive sizes, and both unknown and duplicate manifest structure where
applicable. The runtime loads with `require_artifacts: false` so an empty
manifest produces a clear "no artifact for this target" error instead of a
generic schema error.

The tarball itself is not hash-pinned. Its integrity does not need to be: the
runtime extracts exactly one validated member and then verifies the extracted
bytes against `sha256`/`size`. A modified tarball either fails structural
validation or yields different NIF bytes that fail the hash. This is why
`NIFFLER_ARTIFACT_DIR` can hold bare extracted libraries named
`<sha256>.<so|dll>`.

## Artifact tarball format

Tarballs are gzip-compressed tar archives containing exactly one regular file:

- The member is named `<crate>.<ext>` (`demo_nif.so` on Linux and macOS,
  `demo_nif.dll` on Windows). The long asset name exists only for the download
  URL and release listing.
- Its mode is `0755`, uid and gid are 0, mtime is 0, and owner names are empty,
  so the tarball is reproducible.
- The uncompressed member is limited to 256 MiB at extraction time. Its first
  bytes must look like the target's executable format: ELF for Linux, Mach-O
  for macOS, PE for Windows.

The release asset file name is:

```text
[lib]<crate>-v<package version>-nif-<nif version>-<target>.<so|dll>.tar.gz
```

`lib` prefixes Unix artifacts; Windows artifacts have no prefix. For example,
`x86_64-unknown-linux-gnu` uses `libdemo_nif-v1.2.3-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz`.
The manifest's `base_url` plus this file name is the download URL.

## Platform detection

The runtime reads OTP facts: `os:type/0`, `system_architecture`, `wordsize`,
`nif_version`, and `otp_release`. It normalizes them to a Rust target triple:

- Windows: `win32` family, word size 8 means `x86_64`, and the target is
  `x86_64-pc-windows-msvc`. Windows on 32-bit or ARM is rejected.
- Unix: `system_architecture` is split into `arch-vendor-os[-abi]`; macOS kernel
  suffixes (`darwin23.6.0`) are reduced to `darwin`; `amd64` becomes `x86_64`,
  `arm64`/`arm` become `aarch64`, and Linux vendors such as `pc`, `redhat`,
  `suse`, and `alpine` are normalized to `unknown` so that
  `x86_64-alpine-linux-musl` matches `x86_64-unknown-linux-musl`.
- The resulting triple must be in the supported list, or the loader fails with
  `UnsupportedPlatform` naming the detected target.

Detection can be overridden for Nerves and cross setups: `NIFFLER_TARGET`
forces a complete supported triple, and `TARGET_ARCH`, `TARGET_VENDOR`,
`TARGET_OS`, `TARGET_ABI` override individual components. `NIFFLER_TARGET`
wins and is validated against the supported list.

## NIF version selection

A package may publish several artifacts for the same target with different NIF
versions. At load time the runtime reads the VM's `system_info(nif_version)`
(for example `2.17`) and picks the highest manifest version with the same major
version and a minor version less than or equal to the runtime's. If a target
has artifacts but none is compatible, the loader raises
`UnsupportedNifVersion` with the available and runtime versions. If the target
has no artifacts at all, it raises `UnsupportedPlatform`.

Supported NIF versions and their OTP floors:

| NIF version | Loads on |
| --- | --- |
| 2.14 | OTP 21+ |
| 2.15 | OTP 22+ |
| 2.16 | OTP 24+ |
| 2.17 | OTP 26+ |
| 2.18 | OTP 29+ |

Rustler 0.39's default is 2.15, which is what `build` records unless the crate
activates a newer `nif_version_2_XX` feature. `niffler.toml`'s `nif_version`
is the fallback when feature detection fails, and the default for `package`.
Shipping 2.15 first keeps the package usable on the widest OTP range; newer
versions are opt-in for crates that need newer NIF APIs.

## Generated loader

`niffler generate` writes `src/<module>.erl`:

```erlang
%% Generated by niffler_precompiled. Do not edit.
%% Regenerate with: niffler generate
-module(demo_nif).
-on_load(init/0).
-export([add/2, version/0]).

init() ->
    code:purge(?MODULE),
    case niffler_precompiled:artifact_path(<<"demo">>) of
        {ok, Path} ->
            erlang:load_nif(binary_to_list(Path), []);
        {error, Reason} ->
            niffler_precompiled:raise_load_error(<<"demo">>, Reason)
    end.

add(_Arg0, _Arg1) ->
    erlang:nif_error(nif_not_loaded).

version() ->
    erlang:nif_error(nif_not_loaded).
```

The module name must equal the name passed to `rustler::init!`, and every
configured function must be exported with a stub. Otherwise ERTS rejects the
library with `bad_lib` / "Function not found". On load failure the runtime
prints an actionable message and raises, so a broken package fails loudly
instead of leaving `nif_not_loaded` stubs behind.

The workflow's build matrix is generated from the same configuration, so
`generate --check` fails when either file is stale.

## Cache layout

The cache root is `NIFFLER_CACHE_DIR` when set, otherwise the OS user cache
directory:

- Linux: `$XDG_CACHE_HOME/niffler` or `~/.cache/niffler`
- macOS: `~/Library/Caches/niffler`
- Windows: LocalAppData

```text
<cache>/
  artifacts/<sha256>.<so|dll>     verified NIF libraries, content-addressed
  tmp/                            temporary files for atomic writes
  build/<package>/<version>/<target>/<fingerprint>/
                                  source fallback builds and cargo target dirs
```

Cache lookups validate size and SHA-256 of the stored file. A corrupt or
truncated entry is removed and the artifact is downloaded again (or a clear
offline error is raised). Writes go to `tmp/` and are renamed into place, and
the cache directories are created with mode `0700` best-effort so the cache is
not world-readable or world-writable.

`artifact_path/1` returns the extensionless `<cache>/artifacts/<sha256>` path;
`erlang:load_nif/2` receives the path without the platform extension because
OTP appends `.so` or `.dll` itself.

## Read-only artifact directories

`NIFFLER_ARTIFACT_DIR` is a path list of directories containing flat
`<sha256>.<so|dll>` files. They are checked before the cache and before any
download, and every hit is hashed and compared to the manifest SHA-256, so the
directory can be read-only and can be shared or baked into an image.
`niffler prefetch --to-dir DIR` produces exactly this layout.

## Source fallback

`NIFFLER_BUILD=1` enables a local build instead of artifact resolution. The
runtime then:

1. resolves `priv/<source_path>` from the manifest and checks for `Cargo.toml`;
2. computes a fingerprint: SHA-256 over sorted relative paths and contents of
   the crate, skipping `target/` and `.git/`;
3. looks for `<cache>/build/<package>/<version>/<target>/<fingerprint>/<crate>.<ext>`;
4. otherwise runs `cargo build --release --locked --manifest-path
   <crate>/Cargo.toml --target-dir <cache>/build/.../target`, using
   `NIFFLER_CARGO` when set;
5. copies the built `lib<crate>.so`, `lib<crate>.dylib`, or `<crate>.dll` into
   the fingerprint directory atomically and returns its extensionless path.

The source build is a convenience fallback. It is not covered by the manifest
hash, requires Rust and the crate's dependencies, and runs whatever build
scripts the crate contains.

## Why GitHub Releases and `priv/`

Hex tarballs have a 16 MiB compressed limit and are platform-neutral; shipping
seven shared libraries per version would be wasteful and still would not cover
every system. Releases are a natural content host, and the manifest gives them
integrity. Putting the manifest and the Rust crate under `priv/` means both
travel with the package and can be found from the installed application without
configuration.
