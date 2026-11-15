# Releasing

niffler is designed around tag-driven releases. `init` generates
`.github/workflows/niffler-release.yml`, and `generate` keeps it in sync with
the target list in `niffler.toml`. The workflow builds every target, writes the
manifest, creates the GitHub release, and can optionally publish to Hex.

## Release assets

A release publishes one tarball per configured target plus the manifest:

```text
libdemo_nif-v1.2.3-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz
libdemo_nif-v1.2.3-nif-2.15-aarch64-unknown-linux-gnu.so.tar.gz
libdemo_nif-v1.2.3-nif-2.15-x86_64-unknown-linux-musl.so.tar.gz
libdemo_nif-v1.2.3-nif-2.15-aarch64-unknown-linux-musl.so.tar.gz
libdemo_nif-v1.2.3-nif-2.15-x86_64-apple-darwin.so.tar.gz
libdemo_nif-v1.2.3-nif-2.15-aarch64-apple-darwin.so.tar.gz
demo_nif-v1.2.3-nif-2.15-x86_64-pc-windows-msvc.dll.tar.gz
niffler.json
```

The tarball names are the canonical artifact names recorded in the manifest.
`niffler.json` is the manifest built from that tag. The optional Hex job
downloads this asset into `priv/` before publishing, so the Hex package always
ships the manifest produced from the release build rather than a stale
committed copy.

## Workflow shape

The generated workflow triggers on tags matching `v*` and on
`workflow_dispatch`. It requests `contents: write`, `id-token: write`, and
`attestations: write` permissions.

### Build matrix

| Artifact target | Runner | Build |
| --- | --- | --- |
| `x86_64-unknown-linux-gnu` | `ubuntu-22.04` | native cargo |
| `aarch64-unknown-linux-gnu` | `ubuntu-22.04-arm` | native cargo |
| `x86_64-unknown-linux-musl` | `ubuntu-22.04` | `cross` 0.2.5 |
| `aarch64-unknown-linux-musl` | `ubuntu-22.04-arm` | `cross` 0.2.5 |
| `x86_64-apple-darwin` | `macos-15-intel` | native cargo |
| `aarch64-apple-darwin` | `macos-15` | native cargo |
| `x86_64-pc-windows-msvc` | `windows-2025` | native cargo |

Each matrix job runs on the matching runner, installs Gleam 1.19.2 and OTP 28
with `erlef/setup-beam@v1` and Rust stable with `dtolnay/rust-toolchain@stable`,
then:

1. installs `cross` with `cargo install cross --version 0.2.5 --locked` for
   musl targets;
2. runs `niffler build --target <triple> --dist dist` (with `--use-cross` for
   musl targets);
3. smoke-loads the built artifact for native targets with
   `niffler smoke --artifact <tarball> --module <module>` (cross-built targets
   are not loaded on the runner);
4. attests the tarball with `actions/attest-build-provenance@v2`;
5. uploads `dist/*.tar.gz` with `actions/upload-artifact@v4`.

The generated `.cargo/config.toml` in the crate disables static CRT linking
for the musl targets, which is what `cross` needs to build a loadable
`cdylib`. If a runner needs extra packages, adjust the generated workflow and
regenerate it after changing the target list.

### Release job

The release job downloads all build artifacts into one `dist/` directory and
runs:

```sh
VERSION="${GITHUB_REF_NAME#v}"
niffler manifest --dist dist --version "$VERSION" --write
niffler manifest --dist dist --version "$VERSION" --check
```

`manifest` requires an artifact for every configured target and checks that
each artifact filename carries the `gleam.toml` version, so a partial build or
a version/tag mismatch fails the job. The release job then creates the GitHub
release with `gh release create "$GITHUB_REF_NAME" dist/*.tar.gz
priv/niffler.json --generate-notes --draft` and publishes it with
`gh release edit ... --draft=false`. Publishing the release only after the
manifest and assets are attached means a failed build never leaves a
half-published release. The tag `v<version>` must equal the version in
`gleam.toml`; a mismatched tag produces a manifest version that the runtime
rejects with a version mismatch, and the Hex job's version check also fails.

### Optional Hex job

The Hex job runs after the release job, uses the `hexpm` environment, and is
enabled by setting the repository variable `NIFFLER_PUBLISH_HEX` to `true`. It:

1. downloads the `niffler.json` release asset into `priv/`,
2. runs `niffler hex check --online`,
3. runs `niffler hex emit`,
4. publishes with `gleam publish --yes` using the `HEXPM_API_KEY` secret.

Until the variable, environment, and secret are configured, the job is skipped
and the release remains a GitHub-only release.

## Choreography

1. Bump the version in `gleam.toml`. If the release changes NIF functions,
   update `niffler.toml` and regenerate the loader.
2. If the target list changed, run `generate` and commit the workflow update.
3. Build and verify locally for the host:

   ```sh
   gleam run -m niffler_precompiled -- build
   gleam run -m niffler_precompiled -- manifest
   gleam run -m niffler_precompiled -- verify
   gleam run -m niffler_precompiled -- hex check
   ```

4. Commit the manifest and generated files.
5. Tag and push:

   ```sh
   git tag v1.2.3
   git push origin v1.2.3
   ```

6. Watch the release workflow. When it finishes, the GitHub release contains
   the seven artifacts and `niffler.json`, and the artifacts have build
   provenance attestations.
7. If Hex publishing is enabled, confirm the package version on Hex after the
   job completes.

## Manual release

If CI is unavailable, the same release can be produced by hand:

```sh
# Build the platforms you can (cross for foreign targets)
gleam run -m niffler_precompiled -- build --target x86_64-unknown-linux-gnu
gleam run -m niffler_precompiled -- build --target aarch64-apple-darwin
# ... repeat for every target in niffler.toml
gleam run -m niffler_precompiled -- manifest --version 1.2.3
gleam run -m niffler_precompiled -- verify --online
gleam run -m niffler_precompiled -- hex check --online
gleam run -m niffler_precompiled -- hex emit
gh release create v1.2.3 dist/*.tar.gz priv/niffler.json \
  --title "v1.2.3" --generate-notes
gleam publish
```

Upload `priv/niffler.json` under the asset name `niffler.json`, because the
Hex job looks for that name. Prefer the automated path; the manual steps are a
fallback.

## Attestations

Each build job attests its artifact tarball with GitHub build provenance and
writes the attestation with the repository's OIDC token. The manifest asset and
the Hex tarball are not attested. Anyone with the artifacts can verify them:

```sh
gh attestation verify libdemo_nif-v1.2.3-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz \
  --repo owner/demo
```

Attestations are a supplementary supply-chain signal. The runtime does not
verify them in 0.1.0; it trusts only the SHA-256 pins in the manifest. See
[security](security.md).

## Immutability and rollback

- A published Hex version is immutable, and `priv/niffler.json` inside it is
  therefore immutable too. The manifest is the trust anchor: it pins each
  artifact by SHA-256.
- GitHub release assets are not immutable. Anyone with write access to the
  repository can replace or delete an asset. The manifest hash makes a
  replacement fail closed (checksum mismatch) instead of loading the wrong
  binary, but it breaks installs that pin the affected package version.
- Do not replace assets or move a release tag for a published package version.
  Publish a new version instead, and leave the old release assets in place.
- To roll back, revert the offending commit, bump the version, and tag again.
  Re-publishing an old version is not possible on Hex.
- The release job checks the manifest against `dist/` before creating the
  release, so a partial build or missing target fails the job instead of
  publishing an incomplete release.

## Secrets and permissions

| Name | Where | Purpose |
| --- | --- | --- |
| `GITHUB_TOKEN` | automatic | Create the GitHub release and upload assets. Requires `contents: write`. |
| `HEXPM_API_KEY` | repository secret, `hexpm` environment | Publish to Hex. Use a key with write access to the package, and protect the environment with required reviewers if the project is sensitive. |
| `NIFFLER_PUBLISH_HEX` | repository variable | Set to `true` to enable the optional Hex job. |

No other secrets are needed. Artifact downloads at runtime are unauthenticated,
so release assets must be publicly readable (public repository, or a base URL
that is publicly readable).
