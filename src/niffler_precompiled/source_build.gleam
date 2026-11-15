//// Opt-in source build fallback.

import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import niffler_precompiled/cache
import niffler_precompiled/errors.{
  type NifflerError, CacheWriteFailed, CargoFailed, CargoMissing, SourceMissing,
}
import niffler_precompiled/ffi
import niffler_precompiled/manifest.{type Manifest}
import niffler_precompiled/platform

pub fn build(
  package: String,
  manifest: Manifest,
  target: String,
) -> Result(String, NifflerError) {
  case ffi.priv_dir(package) {
    Error(_) ->
      Error(SourceMissing("the package priv directory is not available"))
    Ok(priv) -> {
      let source = ffi.join_paths([priv, manifest.source_path])
      let cargo_toml = ffi.join_paths([source, "Cargo.toml"])
      case ffi.file_exists(cargo_toml) {
        False -> Error(SourceMissing(source))
        True -> build_from_source(package, manifest, target, source)
      }
    }
  }
}

fn build_from_source(
  package: String,
  manifest: Manifest,
  target: String,
  source: String,
) -> Result(String, NifflerError) {
  case ffi.hash_tree(source) {
    Error(_) -> Error(SourceMissing(source))
    Ok(fingerprint) -> {
      let extension = platform.extension(target)
      let filename = manifest.crate <> "." <> extension
      let final_path =
        cache.source_build_artifact_path(
          package,
          manifest.version,
          target,
          fingerprint,
          filename,
        )
      case ffi.file_exists(final_path) {
        True -> Ok(cache.strip_extension(final_path, extension))
        False ->
          compile(
            package,
            manifest,
            target,
            source,
            fingerprint,
            extension,
            final_path,
          )
      }
    }
  }
}

fn compile(
  package: String,
  manifest: Manifest,
  target: String,
  source: String,
  fingerprint: String,
  extension: String,
  final_path: String,
) -> Result(String, NifflerError) {
  case cargo_executable() {
    Error(error) -> Error(error)
    Ok(cargo) -> {
      let target_directory =
        cache.source_build_target_directory(
          package,
          manifest.version,
          target,
          fingerprint,
        )
      let arguments = [
        "build",
        "--release",
        "--locked",
        "--manifest-path",
        ffi.join_paths([source, "Cargo.toml"]),
        "--target-dir",
        target_directory,
      ]
      let #(status, output) = ffi.run(cargo, arguments, source)
      case status == 0 {
        False -> Error(CargoFailed(status, output_text(output)))
        True -> {
          let release = ffi.join_paths([target_directory, "release"])
          case find_library(release, manifest.crate, extension) {
            Error(error) -> Error(error)
            Ok(built_path) -> copy_into_cache(built_path, final_path, extension)
          }
        }
      }
    }
  }
}

fn cargo_executable() -> Result(String, NifflerError) {
  case ffi.env("NIFFLER_CARGO") {
    Some(path) if path != "" -> Ok(path)
    _ ->
      case ffi.find_executable("cargo") {
        Some(path) -> Ok(path)
        None -> Error(CargoMissing)
      }
  }
}

fn find_library(
  release: String,
  crate: String,
  _extension: String,
) -> Result(String, NifflerError) {
  let candidates = [
    "lib" <> crate <> ".so",
    "lib" <> crate <> ".dylib",
    crate <> ".dll",
  ]
  case ffi.list_dir(release) {
    Error(_) ->
      Error(CargoFailed(0, "could not read cargo output directory " <> release))
    Ok(names) -> {
      let found =
        names
        |> list.filter(fn(name) { list.contains(candidates, name) })
        |> list.first
      case found {
        Ok(name) -> Ok(ffi.join_paths([release, name]))
        Error(_) ->
          Error(CargoFailed(
            0,
            "cargo succeeded but no shared library was found in "
              <> release
              <> " (expected one of: "
              <> string.join(candidates, ", ")
              <> ")",
          ))
      }
    }
  }
}

fn copy_into_cache(
  built_path: String,
  final_path: String,
  extension: String,
) -> Result(String, NifflerError) {
  case ffi.read_file(built_path) {
    Error(error) -> Error(CacheWriteFailed(error))
    Ok(contents) -> {
      let parent = ffi.dirname(final_path)
      case ffi.ensure_dir(parent) {
        Error(error) -> Error(CacheWriteFailed(error))
        Ok(_) -> {
          let temp =
            final_path
            <> ".tmp-"
            <> int_string(ffi.timestamp())
            <> "-"
            <> int_string(ffi.unique_id())
          case ffi.write_file(temp, contents) {
            Error(error) -> Error(CacheWriteFailed(error))
            Ok(_) -> {
              let _ = ffi.set_file_mode(temp, 448)
              case ffi.rename(temp, final_path) {
                Ok(_) -> Ok(cache.strip_extension(final_path, extension))
                Error(error) -> {
                  let _ = ffi.remove_file(temp)
                  case ffi.file_exists(final_path) {
                    True -> Ok(cache.strip_extension(final_path, extension))
                    False -> Error(CacheWriteFailed(error))
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

fn output_text(output: BitArray) -> String {
  case bit_array.to_string(output) {
    Ok(text) -> text
    Error(_) -> "<invalid utf-8 output>"
  }
}

fn int_string(value: Int) -> String {
  case value {
    0 -> "0"
    _ -> int_string_loop(value, "")
  }
}

fn int_string_loop(value: Int, accumulator: String) -> String {
  case value / 10, value % 10 {
    0, digit -> digit_string(digit) <> accumulator
    quotient, digit ->
      int_string_loop(quotient, digit_string(digit) <> accumulator)
  }
}

fn digit_string(digit: Int) -> String {
  case digit {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    _ -> "9"
  }
}
