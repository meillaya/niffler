//// Content-addressed NIF cache and read-only artifact directories.

import gleam/bit_array
import gleam/option.{type Option, None, Some}
import gleam/string
import niffler_precompiled/ffi
import niffler_precompiled/paths

pub fn root() -> String {
  case ffi.env("NIFFLER_CACHE_DIR") {
    Some(path) if path != "" -> path
    _ -> ffi.user_cache_dir("niffler")
  }
}

pub fn artifact_store_path(sha256: String, extension: String) -> String {
  ffi.join_paths([
    root(),
    "artifacts",
    paths.artifact_filename(sha256, extension),
  ])
}

pub fn artifact_load_path(sha256: String, _extension: String) -> String {
  ffi.join_paths([root(), "artifacts", sha256])
}

pub fn ensure_directories() -> Result(Nil, String) {
  let artifacts = ffi.join_paths([root(), "artifacts"])
  let tmp = ffi.join_paths([root(), "tmp"])
  use _ <- result_try(ffi.ensure_dir(artifacts))
  use _ <- result_try(ffi.ensure_dir(tmp))
  // Best effort on Windows; permissions are a defence in depth on Unix.
  let _ = ffi.set_file_mode(root(), 448)
  let _ = ffi.set_file_mode(artifacts, 448)
  let _ = ffi.set_file_mode(tmp, 448)
  Ok(Nil)
}

pub fn is_verified(path: String, sha256: String, size: Int) -> Bool {
  case ffi.file_size(path) {
    Ok(actual_size) if actual_size == size ->
      case ffi.sha256_file_hex(path) {
        Ok(actual_sha) -> actual_sha == sha256
        Error(_) -> False
      }
    _ -> False
  }
}

/// Look up a verified artifact in `NIFFLER_ARTIFACT_DIR` entries. The file name
/// must be `<sha256>.<ext>` (flat, content-addressed, read-only friendly).
pub fn find_readonly(
  sha256: String,
  extension: String,
) -> Result(Option(String), String) {
  case ffi.env("NIFFLER_ARTIFACT_DIR") {
    None -> Ok(None)
    Some(value) if value == "" -> Ok(None)
    Some(value) -> {
      let separator = ffi.path_separator()
      let directories = paths.split_path_list(value, separator)
      find_in_directories(directories, sha256, extension)
    }
  }
}

fn find_in_directories(
  directories: List(String),
  sha256: String,
  extension: String,
) -> Result(Option(String), String) {
  case directories {
    [] -> Ok(None)
    [directory, ..rest] -> {
      let candidate =
        ffi.join_paths([directory, paths.artifact_filename(sha256, extension)])
      case ffi.file_exists(candidate) && is_verified_path(candidate, sha256) {
        True -> Ok(Some(candidate))
        False -> find_in_directories(rest, sha256, extension)
      }
    }
  }
}

fn is_verified_path(path: String, sha256: String) -> Bool {
  case ffi.sha256_file_hex(path) {
    Ok(actual) -> actual == sha256
    Error(_) -> False
  }
}

pub fn store(
  contents: BitArray,
  sha256: String,
  extension: String,
) -> Result(String, String) {
  case ffi.sha256_hex(contents) == sha256 {
    False ->
      Error(
        "refusing to cache contents whose SHA-256 does not match the manifest",
      )
    True -> store_verified(contents, sha256, extension)
  }
}

fn store_verified(
  contents: BitArray,
  sha256: String,
  extension: String,
) -> Result(String, String) {
  let final_path = artifact_store_path(sha256, extension)
  case is_verified(final_path, sha256, bit_array.byte_size(contents)) {
    True -> Ok(final_path)
    False -> {
      use _ <- result_try(ensure_directories())
      let _ = ffi.remove_file(final_path)
      let temp =
        ffi.join_paths([
          root(),
          "tmp",
          int_string(ffi.timestamp())
            <> "-"
            <> int_string(ffi.unique_id())
            <> "."
            <> extension
            <> ".tmp",
        ])
      use _ <- result_try(ffi.write_file(temp, contents))
      let _ = ffi.set_file_mode(temp, 448)
      case ffi.rename(temp, final_path) {
        Ok(_) -> Ok(final_path)
        Error(error) ->
          case is_verified(final_path, sha256, bit_array.byte_size(contents)) {
            True -> {
              let _ = ffi.remove_file(temp)
              Ok(final_path)
            }
            False -> {
              let _ = ffi.remove_file(temp)
              Error(error)
            }
          }
      }
    }
  }
}

pub fn strip_extension(path: String, extension: String) -> String {
  let suffix = "." <> extension
  case string.ends_with(path, suffix) {
    True -> string.slice(path, 0, string.length(path) - string.length(suffix))
    False -> path
  }
}

pub fn source_build_directory(
  package: String,
  version: String,
  target: String,
  fingerprint: String,
) -> String {
  ffi.join_paths([
    root(),
    "build",
    package,
    version,
    target,
    fingerprint,
  ])
}

pub fn source_build_target_directory(
  package: String,
  version: String,
  target: String,
  fingerprint: String,
) -> String {
  ffi.join_paths([
    source_build_directory(package, version, target, fingerprint),
    "target",
  ])
}

pub fn source_build_artifact_path(
  package: String,
  version: String,
  target: String,
  fingerprint: String,
  filename: String,
) -> String {
  ffi.join_paths([
    source_build_directory(package, version, target, fingerprint),
    filename,
  ])
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

fn result_try(
  result: Result(a, String),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
