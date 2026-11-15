//// Manifest model: `priv/niffler.json`.
////
//// The manifest is the trust anchor shipped inside the immutable Hex package.
//// It maps (target, nif_version) pairs to release artifacts and their SHA-256
//// digests.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import niffler_precompiled/checksum
import niffler_precompiled/json.{type Json, JArray, JInt, JObject, JString}
import niffler_precompiled/platform

pub const schema_version = 1

pub type Artifact {
  Artifact(
    target: String,
    nif_version: String,
    file: String,
    sha256: String,
    size: Int,
  )
}

pub type Manifest {
  Manifest(
    package: String,
    version: String,
    nif_module: String,
    crate: String,
    source_path: String,
    base_url: String,
    artifacts: List(Artifact),
  )
}

pub fn decode(input: String) -> Result(Manifest, String) {
  case json.parse(input) {
    Error(error) -> Error("could not parse priv/niffler.json: " <> error)
    Ok(document) -> decode_document(document)
  }
}

fn decode_document(document: Json) -> Result(Manifest, String) {
  case json.field_int(document, "schema_version") {
    Error(error) -> Error(error)
    Ok(version) ->
      case version == schema_version {
        False ->
          Error(
            "unsupported manifest schema_version "
            <> int.to_string(version)
            <> " (this niffler supports "
            <> int.to_string(schema_version)
            <> ")",
          )
        True -> {
          let package = json.field_string(document, "package")
          let version = json.field_string(document, "version")
          let nif = json.object_get(document, "nif")
          let base_url = json.field_string(document, "base_url")
          let artifacts = json.field_array(document, "artifacts")
          case package, version, nif, base_url, artifacts {
            Ok(package), Ok(version), Ok(nif), Ok(base_url), Ok(artifacts) ->
              case
                json.field_string(nif, "module"),
                json.field_string(nif, "crate"),
                json.field_optional_string(nif, "source_path")
              {
                Ok(nif_module), Ok(crate), Ok(source_path) -> {
                  let source_path = case source_path {
                    Some(path) -> path
                    None -> "native/" <> crate
                  }
                  let decoded_artifacts =
                    artifacts
                    |> list.map(decode_artifact)
                    |> result.all
                  case decoded_artifacts {
                    Error(error) -> Error(error)
                    Ok(artifacts) ->
                      Ok(Manifest(
                        package: package,
                        version: version,
                        nif_module: nif_module,
                        crate: crate,
                        source_path: source_path,
                        base_url: base_url,
                        artifacts: artifacts,
                      ))
                  }
                }
                Error(error), _, _ -> Error(error)
                _, Error(error), _ -> Error(error)
                _, _, Error(error) -> Error(error)
              }
            Error(error), _, _, _, _ -> Error(error)
            _, Error(error), _, _, _ -> Error(error)
            _, _, Error(error), _, _ -> Error(error)
            _, _, _, Error(error), _ -> Error(error)
            _, _, _, _, Error(error) -> Error(error)
          }
        }
      }
  }
}

fn decode_artifact(value: Json) -> Result(Artifact, String) {
  case value {
    JObject(_) -> {
      let target = json.field_string(value, "target")
      let nif_version = json.field_string(value, "nif_version")
      let file = json.field_string(value, "file")
      let sha256 = json.field_string(value, "sha256")
      let size = json.field_int(value, "size")
      case target, nif_version, file, sha256, size {
        Ok(target), Ok(nif_version), Ok(file), Ok(sha256), Ok(size) ->
          Ok(Artifact(target, nif_version, file, sha256, size))
        Error(error), _, _, _, _ -> Error("artifact: " <> error)
        _, Error(error), _, _, _ -> Error("artifact: " <> error)
        _, _, Error(error), _, _ -> Error("artifact: " <> error)
        _, _, _, Error(error), _ -> Error("artifact: " <> error)
        _, _, _, _, Error(error) -> Error("artifact: " <> error)
      }
    }
    _ -> Error("manifest artifacts must be objects")
  }
}

pub type ValidateOptions {
  ValidateOptions(allow_insecure_base_url: Bool, require_artifacts: Bool)
}

pub fn default_validate_options() -> ValidateOptions {
  ValidateOptions(allow_insecure_base_url: False, require_artifacts: True)
}

pub fn validate(
  manifest: Manifest,
  options: ValidateOptions,
) -> Result(Nil, String) {
  case checksum.is_identifier(manifest.package) {
    False -> Error("invalid package name: " <> manifest.package)
    True ->
      case checksum.is_identifier(manifest.nif_module) {
        False -> Error("invalid NIF module name: " <> manifest.nif_module)
        True ->
          case checksum.is_identifier(manifest.crate) {
            False -> Error("invalid crate name: " <> manifest.crate)
            True ->
              case valid_source_path(manifest.source_path) {
                Error(error) -> Error(error)
                Ok(_) ->
                  case
                    valid_base_url(
                      manifest.base_url,
                      options.allow_insecure_base_url,
                    )
                  {
                    Error(error) -> Error(error)
                    Ok(_) ->
                      case unique_artifacts(manifest.artifacts) {
                        Error(error) -> Error(error)
                        Ok(_) ->
                          case options.require_artifacts {
                            True if manifest.artifacts == [] ->
                              Error("manifest has no artifacts")
                            _ -> {
                              case
                                list.all(manifest.artifacts, validate_artifact)
                              {
                                True -> Ok(Nil)
                                False ->
                                  Error("one or more artifacts are invalid")
                              }
                            }
                          }
                      }
                  }
              }
          }
      }
  }
}

fn valid_source_path(path: String) -> Result(Nil, String) {
  let invalid =
    path == ""
    || string.starts_with(path, "/")
    || string.contains(path, "..")
    || string.contains(path, "\\")
    || !string.starts_with(path, "native/")
  case invalid {
    True ->
      Error(
        "source_path must be a relative path under priv/native/ (got "
        <> path
        <> ")",
      )
    False -> Ok(Nil)
  }
}

fn valid_base_url(url: String, allow_insecure: Bool) -> Result(Nil, String) {
  let secure = string.starts_with(url, "https://")
  let insecure = string.starts_with(url, "http://")
  case secure || { allow_insecure && insecure } {
    True ->
      case string.contains(url, " ") {
        True -> Error("base_url must not contain spaces")
        False -> Ok(Nil)
      }
    False -> Error("base_url must use https:// (got " <> url <> ")")
  }
}

fn unique_artifacts(artifacts: List(Artifact)) -> Result(Nil, String) {
  case artifacts {
    [] -> Ok(Nil)
    [artifact, ..rest] -> {
      let duplicate =
        list.find(rest, fn(other) {
          other.target == artifact.target
          && other.nif_version == artifact.nif_version
        })
      case duplicate {
        Ok(other) ->
          Error(
            "duplicate artifact for target "
            <> other.target
            <> " and NIF version "
            <> other.nif_version,
          )
        Error(_) -> unique_artifacts(rest)
      }
    }
  }
}

fn validate_artifact(artifact: Artifact) -> Bool {
  checksum.is_supported_nif_version(artifact.nif_version)
  && checksum.is_plain_filename(artifact.file)
  && checksum.is_sha256_hex(artifact.sha256)
  && artifact.size > 0
  && list.contains(platform.supported_targets, artifact.target)
}

pub type SelectError {
  NoTarget(target: String, available: List(String))
  NoCompatible(
    target: String,
    runtime_nif_version: String,
    available: List(String),
  )
}

/// Select the best artifact for `target`, preferring the newest compatible NIF
/// version.
pub fn select_artifact(
  manifest: Manifest,
  target: String,
  runtime_nif_version: String,
) -> Result(Artifact, SelectError) {
  let candidates =
    manifest.artifacts
    |> list.filter(fn(artifact) { artifact.target == target })
  case candidates {
    [] ->
      Error(NoTarget(
        target: target,
        available: manifest.artifacts
          |> list.map(fn(artifact) { artifact.target })
          |> list.unique,
      ))
    _ -> {
      let versions = list.map(candidates, fn(artifact) { artifact.nif_version })
      case platform.select_nif_version(runtime_nif_version, versions) {
        Error(_) ->
          Error(NoCompatible(
            target: target,
            runtime_nif_version: runtime_nif_version,
            available: versions,
          ))
        Ok(version) ->
          case
            list.find(candidates, fn(artifact) {
              artifact.nif_version == version
            })
          {
            Ok(artifact) -> Ok(artifact)
            Error(_) ->
              Error(NoCompatible(
                target: target,
                runtime_nif_version: runtime_nif_version,
                available: versions,
              ))
          }
      }
    }
  }
}

pub fn artifact_url(manifest: Manifest, artifact: Artifact) -> String {
  strip_trailing_slashes(string.trim(manifest.base_url)) <> "/" <> artifact.file
}

fn strip_trailing_slashes(value: String) -> String {
  case string.ends_with(value, "/") {
    True ->
      strip_trailing_slashes(string.slice(value, 0, string.length(value) - 1))
    False -> value
  }
}

pub fn encode(manifest: Manifest) -> String {
  let artifacts =
    manifest.artifacts
    |> list.sort(fn(a, b) {
      case string.compare(a.target, b.target) {
        order.Eq -> string.compare(a.nif_version, b.nif_version)
        other -> other
      }
    })
    |> list.map(fn(artifact) {
      JObject([
        #("target", JString(artifact.target)),
        #("nif_version", JString(artifact.nif_version)),
        #("file", JString(artifact.file)),
        #("sha256", JString(artifact.sha256)),
        #("size", JInt(artifact.size)),
      ])
    })

  let document =
    JObject([
      #("schema_version", JInt(schema_version)),
      #("package", JString(manifest.package)),
      #("version", JString(manifest.version)),
      #(
        "nif",
        JObject([
          #("module", JString(manifest.nif_module)),
          #("crate", JString(manifest.crate)),
          #("source_path", JString(manifest.source_path)),
        ]),
      ),
      #("base_url", JString(manifest.base_url)),
      #("artifacts", JArray(artifacts)),
    ])
  json.encode(document) <> "\n"
}

/// Replace artifacts with a new list, preserving metadata.
pub fn with_artifacts(
  manifest: Manifest,
  artifacts: List(Artifact),
) -> Manifest {
  Manifest(
    package: manifest.package,
    version: manifest.version,
    nif_module: manifest.nif_module,
    crate: manifest.crate,
    source_path: manifest.source_path,
    base_url: manifest.base_url,
    artifacts: artifacts,
  )
}

pub fn empty(
  package: String,
  version: String,
  nif_module: String,
  crate: String,
  base_url: String,
) -> Manifest {
  Manifest(
    package: package,
    version: version,
    nif_module: nif_module,
    crate: crate,
    source_path: "native/" <> crate,
    base_url: base_url,
    artifacts: [],
  )
}

pub fn find_artifact(
  manifest: Manifest,
  target: String,
  nif_version: String,
) -> Option(Artifact) {
  case
    list.find(manifest.artifacts, fn(artifact) {
      artifact.target == target && artifact.nif_version == nif_version
    })
  {
    Ok(artifact) -> Some(artifact)
    Error(_) -> None
  }
}
