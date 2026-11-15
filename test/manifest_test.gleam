import gleam/list
import gleam/option
import gleeunit/should
import niffler_precompiled/manifest

fn sample_manifest() -> manifest.Manifest {
  manifest.Manifest(
    package: "demo",
    version: "1.2.3",
    nif_module: "demo_nif",
    crate: "demo_nif",
    source_path: "native/demo_nif",
    base_url: "https://github.com/owner/demo/releases/download/v1.2.3",
    artifacts: [
      manifest.Artifact(
        target: "x86_64-unknown-linux-gnu",
        nif_version: "2.15",
        file: "libdemo_nif-v1.2.3-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz",
        sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        size: 1234,
      ),
      manifest.Artifact(
        target: "x86_64-unknown-linux-gnu",
        nif_version: "2.17",
        file: "libdemo_nif-v1.2.3-nif-2.17-x86_64-unknown-linux-gnu.so.tar.gz",
        sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        size: 2345,
      ),
      manifest.Artifact(
        target: "aarch64-apple-darwin",
        nif_version: "2.15",
        file: "libdemo_nif-v1.2.3-nif-2.15-aarch64-apple-darwin.so.tar.gz",
        sha256: "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
        size: 3456,
      ),
    ],
  )
}

pub fn encode_decode_round_trip_test() {
  let original = sample_manifest()
  let text = manifest.encode(original)
  let decoded = manifest.decode(text) |> should.be_ok
  decoded.package |> should.equal("demo")
  decoded.nif_module |> should.equal("demo_nif")
  list.length(decoded.artifacts) |> should.equal(3)
  manifest.encode(decoded) |> should.equal(text)
}

pub fn validate_test() {
  manifest.validate(sample_manifest(), manifest.default_validate_options())
  |> should.equal(Ok(Nil))
}

pub fn validate_rejects_duplicate_artifact_test() {
  let original = sample_manifest()
  let duplicate =
    manifest.Artifact(
      target: "x86_64-unknown-linux-gnu",
      nif_version: "2.15",
      file: "other.so.tar.gz",
      sha256: "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      size: 1,
    )
  manifest.validate(
    manifest.with_artifacts(original, [duplicate, duplicate]),
    manifest.default_validate_options(),
  )
  |> should.be_error
}

pub fn validate_rejects_http_test() {
  let original = sample_manifest()
  let insecure =
    manifest.Manifest(
      package: original.package,
      version: original.version,
      nif_module: original.nif_module,
      crate: original.crate,
      source_path: original.source_path,
      base_url: "http://example.com",
      artifacts: original.artifacts,
    )
  manifest.validate(insecure, manifest.default_validate_options())
  |> should.be_error
  manifest.validate(
    insecure,
    manifest.ValidateOptions(
      allow_insecure_base_url: True,
      require_artifacts: True,
    ),
  )
  |> should.equal(Ok(Nil))
}

pub fn select_prefers_newest_compatible_test() {
  let selected =
    manifest.select_artifact(
      sample_manifest(),
      "x86_64-unknown-linux-gnu",
      "2.17",
    )
    |> should.be_ok
  selected.nif_version |> should.equal("2.17")
}

pub fn select_falls_back_to_older_test() {
  let selected =
    manifest.select_artifact(
      sample_manifest(),
      "x86_64-unknown-linux-gnu",
      "2.16",
    )
    |> should.be_ok
  selected.nif_version |> should.equal("2.15")
}

pub fn select_rejects_unknown_target_test() {
  manifest.select_artifact(sample_manifest(), "x86_64-pc-windows-msvc", "2.17")
  |> should.be_error
}

pub fn artifact_url_test() {
  let artifact =
    manifest.Artifact(
      target: "x86_64-unknown-linux-gnu",
      nif_version: "2.15",
      file: "demo.so.tar.gz",
      sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      size: 1,
    )
  manifest.artifact_url(sample_manifest(), artifact)
  |> should.equal(
    "https://github.com/owner/demo/releases/download/v1.2.3/demo.so.tar.gz",
  )
}

pub fn find_artifact_test() {
  case
    manifest.find_artifact(sample_manifest(), "aarch64-apple-darwin", "2.15")
  {
    option.Some(artifact) -> artifact.nif_version |> should.equal("2.15")
    option.None -> should.fail()
  }
}

pub fn rejects_invalid_manifest_test() {
  manifest.decode("not json") |> should.be_error
  manifest.decode("{\"schema_version\": 2}") |> should.be_error
}
