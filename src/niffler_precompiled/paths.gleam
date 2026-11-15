//// Cache and artifact path helpers.

import gleam/list
import gleam/option.{type Option, Some}
import gleam/string

pub fn cache_root(override: Option(String), user_cache: String) -> String {
  case override {
    Some(path) if path != "" -> path
    _ -> user_cache
  }
}

pub fn artifact_filename(sha256: String, extension: String) -> String {
  sha256 <> "." <> extension
}

pub fn artifact_relative_path(sha256: String, extension: String) -> String {
  "artifacts/" <> artifact_filename(sha256, extension)
}

pub fn temp_relative_path(random: String) -> String {
  "tmp/" <> random <> ".part"
}

pub fn extract_relative_path(random: String) -> String {
  "tmp/" <> random
}

pub fn source_build_relative_path(
  package: String,
  version: String,
  target: String,
  fingerprint: String,
  filename: String,
) -> String {
  string.join(["build", package, version, target, fingerprint, filename], "/")
}

pub fn split_path_list(value: String, separator: String) -> List(String) {
  value
  |> string.split(separator)
  |> list.filter(fn(entry) { string.trim(entry) != "" })
  |> list.map(string.trim)
}

pub fn environment_overrides(
  env: fn(String) -> Option(String),
) -> #(
  Option(String),
  Option(String),
  Option(String),
  Option(String),
  Option(String),
) {
  #(
    env("NIFFLER_TARGET"),
    env("TARGET_ARCH"),
    env("TARGET_VENDOR"),
    env("TARGET_OS"),
    env("TARGET_ABI"),
  )
}
