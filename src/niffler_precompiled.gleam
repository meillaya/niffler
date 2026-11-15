//// Public runtime API used by generated Erlang loaders and by consumers.
////
//// This module is also the CLI entry point (`niffler` / `gleam run -m
//// niffler_precompiled`).

import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import niffler_precompiled/archive
import niffler_precompiled/cache
import niffler_precompiled/cli
import niffler_precompiled/errors
import niffler_precompiled/fetch
import niffler_precompiled/ffi
import niffler_precompiled/manifest.{type Artifact, type Manifest}
import niffler_precompiled/platform
import niffler_precompiled/source_build

/// The version of this package.
pub const version = "0.1.0"

pub type Info {
  Info(
    package: String,
    version: String,
    target: String,
    runtime_nif_version: String,
    manifest_path: String,
    cache_root: String,
    artifact: Option(Artifact),
    source_available: Bool,
  )
}

/// Resolve, verify, and cache the NIF for `package`, returning an absolute path
/// without the platform extension for `erlang:load_nif/2`.
pub fn artifact_path(package: String) -> Result(String, errors.NifflerError) {
  resolve(package, build_enabled())
}

/// Download and verify the artifact into the cache without loading it.
pub fn prefetch(package: String) -> Result(Nil, errors.NifflerError) {
  case resolve(package, False) {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error)
  }
}

pub fn info(package: String) -> Result(Info, errors.NifflerError) {
  case detect_target() {
    Error(error) -> Error(error)
    Ok(target) -> {
      let facts = runtime_facts()
      case load_manifest(package) {
        Error(error) -> Error(error)
        Ok(#(manifest, manifest_path)) -> {
          let artifact = case
            manifest.select_artifact(manifest, target, facts.nif_version)
          {
            Ok(artifact) -> Some(artifact)
            Error(_) -> None
          }
          let source_available = case ffi.priv_dir(package) {
            Ok(priv) ->
              ffi.file_exists(
                ffi.join_paths([priv, manifest.source_path, "Cargo.toml"]),
              )
            Error(_) -> False
          }
          Ok(Info(
            package: package,
            version: manifest.version,
            target: target,
            runtime_nif_version: facts.nif_version,
            manifest_path: manifest_path,
            cache_root: cache.root(),
            artifact: artifact,
            source_available: source_available,
          ))
        }
      }
    }
  }
}

pub fn clear_cache(package: String) -> Result(Nil, errors.NifflerError) {
  case load_manifest(package) {
    Error(_) -> Ok(Nil)
    Ok(#(manifest, _)) -> {
      list.each(manifest.artifacts, fn(artifact) {
        let extension = platform.extension(artifact.target)
        let _ =
          ffi.remove_file(cache.artifact_store_path(artifact.sha256, extension))
        let _ =
          ffi.remove_file(cache.artifact_load_path(artifact.sha256, extension))
        Nil
      })
      let build_directory = ffi.join_paths([cache.root(), "build", package])
      let _ = ffi.remove_tree(build_directory)
      Ok(Nil)
    }
  }
}

pub fn format_error(error: errors.NifflerError) -> String {
  errors.message(error)
}

/// Called by the generated loader when loading fails. Prints an actionable
/// diagnostic and raises so the module load fails rather than leaving silent
/// `nif_not_loaded` stubs behind.
pub fn raise_load_error(package: String, error: errors.NifflerError) -> Nil {
  ffi.raise(package, format_error(error))
}

fn resolve(
  package: String,
  allow_build: Bool,
) -> Result(String, errors.NifflerError) {
  case detect_target() {
    Error(error) -> Error(error)
    Ok(target) -> {
      let facts = runtime_facts()
      case load_manifest(package) {
        Error(error) -> Error(error)
        Ok(#(manifest, _manifest_path)) -> {
          case allow_build {
            True -> source_build.build(package, manifest, target)
            False -> resolve_artifact(manifest, target, facts.nif_version)
          }
        }
      }
    }
  }
}

fn resolve_artifact(
  manifest: Manifest,
  target: String,
  runtime_nif_version: String,
) -> Result(String, errors.NifflerError) {
  case manifest.select_artifact(manifest, target, runtime_nif_version) {
    Error(manifest.NoTarget(target, available)) ->
      Error(errors.UnsupportedPlatform(
        "no precompiled NIF for target "
        <> target
        <> " (manifest lists: "
        <> string.join(available, ", ")
        <> "). Set NIFFLER_BUILD=1 to build from source.",
      ))
    Error(manifest.NoCompatible(target, runtime, available)) ->
      Error(errors.UnsupportedNifVersion(
        target,
        string.join(available, ", "),
        runtime,
      ))
    Ok(artifact) -> {
      let extension = platform.extension(target)
      case cache.find_readonly(artifact.sha256, extension) {
        Error(error) -> Error(errors.CacheWriteFailed(error))
        Ok(Some(path)) -> Ok(cache.strip_extension(path, extension))
        Ok(None) -> {
          let cached = cache.artifact_store_path(artifact.sha256, extension)
          case cache.is_verified(cached, artifact.sha256, artifact.size) {
            True -> Ok(cache.artifact_load_path(artifact.sha256, extension))
            False -> {
              let _ = ffi.remove_file(cached)
              case fetch.flag("NIFFLER_OFFLINE") {
                True ->
                  Error(errors.OfflineMissing(
                    artifact.file <> " is not present in " <> cache.root(),
                  ))
                False -> download_and_store(manifest, artifact, extension)
              }
            }
          }
        }
      }
    }
  }
}

fn download_and_store(
  manifest: Manifest,
  artifact: Artifact,
  extension: String,
) -> Result(String, errors.NifflerError) {
  let url = download_url(manifest, artifact)
  case fetch.download(url) {
    Error(error) -> Error(error)
    Ok(body) -> {
      case archive.extract(manifest.crate, artifact, body) {
        Error(error) -> Error(error)
        Ok(contents) -> {
          let actual_sha = ffi.sha256_hex(contents)
          case
            actual_sha == artifact.sha256
            && bit_array.byte_size(contents) == artifact.size
          {
            False ->
              Error(errors.ChecksumMismatch(
                expected: artifact.sha256,
                actual: actual_sha,
              ))
            True -> {
              case cache.store(contents, artifact.sha256, extension) {
                Error(error) -> Error(errors.CacheWriteFailed(error))
                Ok(stored) -> Ok(cache.strip_extension(stored, extension))
              }
            }
          }
        }
      }
    }
  }
}

fn download_url(manifest: Manifest, artifact: Artifact) -> String {
  case ffi.env("NIFFLER_BASE_URL") {
    Some(base) if base != "" ->
      strip_trailing_slashes(base) <> "/" <> artifact.file
    _ -> manifest.artifact_url(manifest, artifact)
  }
}

fn strip_trailing_slashes(value: String) -> String {
  case string.ends_with(value, "/") {
    True ->
      strip_trailing_slashes(string.slice(value, 0, string.length(value) - 1))
    False -> value
  }
}

fn detect_target() -> Result(String, errors.NifflerError) {
  let facts = runtime_facts()
  let overrides =
    platform.EnvOverrides(
      target: ffi.env("NIFFLER_TARGET"),
      arch: ffi.env("TARGET_ARCH"),
      vendor: ffi.env("TARGET_VENDOR"),
      os: ffi.env("TARGET_OS"),
      abi: ffi.env("TARGET_ABI"),
    )
  platform.current_target(facts, overrides)
  |> result.map_error(errors.UnsupportedPlatform)
}

fn runtime_facts() -> platform.Facts {
  platform.Facts(
    system_architecture: ffi.system_architecture(),
    os_type: ffi.os_type(),
    wordsize: ffi.wordsize(),
    nif_version: ffi.nif_version(),
    otp_release: ffi.otp_release(),
  )
}

fn load_manifest(
  package: String,
) -> Result(#(Manifest, String), errors.NifflerError) {
  case ffi.priv_dir(package) {
    Error(_) -> Error(errors.ManifestMissing(package))
    Ok(priv) -> {
      let path = ffi.join_paths([priv, "niffler.json"])
      case ffi.read_file(path) {
        Error(_) -> Error(errors.ManifestMissing(package))
        Ok(contents) -> {
          case bit_array.to_string(contents) {
            Error(_) ->
              Error(errors.ManifestInvalid(
                "priv/niffler.json is not valid UTF-8",
              ))
            Ok(text) -> {
              case manifest.decode(text) {
                Error(error) -> Error(errors.ManifestInvalid(error))
                Ok(manifest) -> validate_manifest(package, manifest, path)
              }
            }
          }
        }
      }
    }
  }
}

fn validate_manifest(
  package: String,
  manifest: Manifest,
  path: String,
) -> Result(#(Manifest, String), errors.NifflerError) {
  let options =
    manifest.ValidateOptions(
      allow_insecure_base_url: fetch.flag("NIFFLER_ALLOW_INSECURE_URLS"),
      require_artifacts: False,
    )
  case manifest.validate(manifest, options) {
    Error(error) -> Error(errors.ManifestInvalid(error))
    Ok(_) -> {
      case manifest.package == package {
        False ->
          Error(errors.PackageMismatch(
            expected: package,
            actual: manifest.package,
          ))
        True -> {
          case ffi.app_version(package) {
            Ok(installed_version) ->
              case installed_version == manifest.version {
                True -> Ok(#(manifest, path))
                False ->
                  Error(errors.VersionMismatch(
                    expected: installed_version,
                    actual: manifest.version,
                  ))
              }
            Error(_) -> Ok(#(manifest, path))
          }
        }
      }
    }
  }
}

fn build_enabled() -> Bool {
  fetch.flag("NIFFLER_BUILD")
}

/// CLI entry point. Kept on the root module so the package can be invoked with
/// `gleam run -m niffler_precompiled`.
pub fn main() {
  cli.main()
}

/// Escript entry point: arguments come from the escript runtime.
pub fn main_with_args(arguments: List(String)) {
  cli.main_with_args(arguments)
}
