# Security model

niffler downloads native code and runs it inside the Erlang VM. The security
model is therefore about *provenance*: making sure the bytes loaded are the
bytes the package author published, even though they are downloaded at runtime
from a third-party host.

## Threat model

Threats niffler is designed to resist:

- A compromised or malicious release host serving different bytes for an
  artifact URL.
- A man-in-the-middle rewriting a download.
- A tampered or malformed tarball (path traversal, extra members, absolute
  paths, non-regular members, a member that is not a NIF).
- A corrupted or tampered cache entry that would otherwise be loaded.
- A manifest that does not belong to the installed package or version.
- Accidental failure: a missing artifact, HTTP error, or checksum mismatch must
  stop the load instead of silently continuing.

Threats outside the model:

- A malicious or compromised package author. The manifest is written by the
  author and whatever it pins is trusted.
- A compromised Hex account publishing a new version with a malicious
  manifest.
- An attacker with the same OS user privileges as the running BEAM, who can
  modify the application, the cache, or environment variables.
- Native code that is legitimately what the author published but does something
  harmful. A NIF runs with full VM privileges; niffler is not a sandbox.

## Trust anchors

### Hash-pinned manifest in an immutable Hex release

`priv/niffler.json` ships inside the Hex package. Hex versions are immutable:
once published, the manifest and package files inside that version cannot be
changed. The runtime:

- locates the manifest with `code:priv_dir/1`;
- validates its structure and every artifact;
- checks that `manifest.package` equals the package being loaded, and that
  `manifest.version` equals the installed application version (when the
  version can be read).

Each artifact pins the SHA-256 and byte size of the **extracted NIF shared
library**, not of the tarball. The tarball is a transport container; the inner
NIF is what the hash authenticates.

### TLS verification

Downloads use OTP's `httpc` with `ssl` and:

- `verify_peer` with hostname verification
  (`public_key:pkix_verify_hostname_match_fun(https)`);
- the OS CA store via `public_key:cacerts_get()`, or a PEM file supplied with
  `NIFFLER_CACERTS`;
- manual redirect handling, at most five redirects, each hop re-validated as
  HTTPS with a host (redirects never downgrade to plain HTTP);
- HTTP request and connect timeouts;
- a 64 MiB response body cap, checked both from `Content-Length` and on the
  actual received size.

Plain HTTP is refused. `NIFFLER_ALLOW_INSECURE_URLS=1` is a test-only switch
that permits `http://` for loopback hosts (`localhost`, `127.0.0.1`, `::1`)
only; it exists for the integration harness and is not a supported production
configuration. Downloads are retried up to three times with backoff on network
errors.

### Download and extraction validation

After a download, before anything is written to the cache or loaded:

1. The body must be a valid gzip'd tar archive.
2. The archive must contain exactly one entry.
3. The entry must be named `<crate>.<so|dll>` (matching the manifest crate and
   the target platform), must be a regular file, and must be at most 256 MiB
   uncompressed.
4. The extracted bytes must start with the executable magic for the target:
   ELF for Linux, Mach-O for macOS, PE for Windows.
5. The extracted bytes must match the manifest SHA-256 and the exact byte size.

Any failure raises an error; nothing is cached and nothing is loaded. A hash
mismatch rejects the download (the bad bytes are never cached) and suggests
`niffler cache clean` so a stale cache entry can be removed.

### Cache integrity

- Cache files are named by the manifest SHA-256 and are re-hashed (and
  size-checked) on every lookup, so a corrupted or manually replaced cache file
  is detected and discarded.
- Writes go to `tmp/` and are renamed into place, so a crashed process cannot
  leave a partial file at the final path.
- Cache directories and cached files are created with mode `0700` best-effort
  on Unix; the cache is per user by default.
- `NIFFLER_ARTIFACT_DIR` entries are also hashed on every lookup, so a
  read-only, image-baked artifact directory is verified just like the cache.

### Fail-closed loading

The generated loader has an `-on_load` hook. If resolution, download,
verification, extraction, or `erlang:load_nif/2` fails, the runtime raises with
a diagnostic and the module fails to load. There is no unsigned or unchecked
fallback path. The only alternate code path is an explicit opt-in source build.

## Source builds are outside the guarantees

`NIFFLER_BUILD=1` builds the bundled Rust crate locally with `cargo`. When
enabled it takes precedence over precompiled artifacts, so every load resolves
through this path. This path:

- is not covered by the manifest hash (the resulting library is loaded
  directly from the fingerprint cache);
- runs `cargo` and any build scripts in the crate as the current user;
- resolves dependencies from crates.io or the local cargo cache;
- requires a Rust toolchain and a linker on the target machine.

It is intended for unsupported platforms and local development. Enable it only
where running a compiler is acceptable, and do not enable it on production
hosts as a substitute for shipping artifacts.

## Attestations

The generated release workflow attests every artifact tarball with
`actions/attest-build-provenance@v2`, using the workflow's OIDC token and
`attestations: write` permission. Attestations are published to GitHub and can
be verified manually:

```sh
gh attestation verify <artifact>.tar.gz --repo owner/demo
```

Attestations are supplementary supply-chain evidence. niffler 0.1.0 does **not**
fetch or verify attestations, signatures, or certificates at runtime, and the
`niffler.json` manifest asset itself is not attested. The runtime trusts only
the SHA-256 pins in the manifest shipped in the Hex package. Verify
attestations out of band if your deployment needs provenance beyond that.

## Operational guidance

- Run `nifler prefetch` during build or deploy, then set `NIFFLER_OFFLINE=1` in
  production. This removes the first-load network dependency and makes a
  missing artifact a startup failure rather than a runtime surprise.
- Keep the cache per deployment, or pin it with `NIFFLER_CACHE_DIR`. Do not
  share a writable cache between users.
- Commit `priv/niffler.json` and review changes to it: it is the trust anchor.
- Pin package versions in `manifest.toml`/lockfiles so the manifest version
  matches the installed package version.
- Do not replace GitHub release assets for an already-published package
  version; publish a new version instead.
- If you configure `NIFFLER_CACERTS`, treat that file with the same care as any
  trust store. Setting environment variables for the process is already within
  the attacker's control in the same-user threat model.
- Treat `NIFFLER_ALLOW_INSECURE_URLS`, `NIFFLER_CACERTS`, and `NIFFLER_BUILD`
  as operator-only knobs, not as user-facing configuration.

## Residual risks

- **Release asset replacement is a denial of service.** An attacker with write
  access to the GitHub repository can replace an asset. New installs of the
  affected published version then fail the hash check; already-cached installs
  are unaffected. Old package versions cannot be republished with new hashes.
- **Compromised publishing credentials.** A new Hex version can ship a
  malicious manifest and artifacts. Review package updates like code.
- **No code signing.** Windows DLLs are not Authenticode-signed and macOS
  libraries are not notarized. There is no OS-level publisher identity to
  check; integrity comes from the manifest hash and TLS.
- **Tarball bytes are not hash-pinned.** The tarball is validated structurally
  and its extracted member is hash-pinned. A compromised host can serve a
  different tarball only if it produces the exact same inner NIF bytes or fails
  validation.
- **Public repositories only.** Downloads are unauthenticated; private release
  assets are not supported. Hash verification is unaffected, but the URL must
  be publicly readable, or served through a mounted read-only
  `NIFFLER_ARTIFACT_DIR`.
- **Platform floors.** Linux gnu artifacts are built on GitHub's Ubuntu runner
  image. Older glibc systems may fail to load them even with a matching triple;
  use musl artifacts or a source build.
- **Native code is trusted once loaded.** Hash verification proves the bytes
  are the ones the author published, not that they are safe. A NIF can do
  anything the OS allows the BEAM process to do.
