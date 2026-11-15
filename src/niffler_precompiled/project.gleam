//// Project helpers shared by CLI commands.

import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import niffler_precompiled/config
import niffler_precompiled/ffi
import niffler_precompiled/json
import niffler_precompiled/manifest
import niffler_precompiled/platform

pub type PackageInfo {
  PackageInfo(
    name: String,
    version: String,
    description: String,
    licences: List(String),
    repository: Option(String),
    target: String,
  )
}

pub fn package_info(root: String) -> Result(PackageInfo, String) {
  use gleam <- result.try(find_gleam())
  let #(status, output) =
    ffi.run(gleam, ["export", "package-information"], root)
  case status == 0 {
    False ->
      Error(
        "could not read gleam.toml (gleam export package-information failed):\n"
        <> output_string(output),
      )
    True -> output_string(output) |> parse_package_info
  }
}

fn find_gleam() -> Result(String, String) {
  case ffi.env("NIFFLER_GLEAM") {
    Some(path) if path != "" -> Ok(path)
    _ ->
      case ffi.find_executable("gleam") {
        Some(path) -> Ok(path)
        None -> Error("could not find the `gleam` executable on PATH")
      }
  }
}

fn parse_package_info(text: String) -> Result(PackageInfo, String) {
  use document <- result.try(
    json.parse(text)
    |> result.map_error(fn(error) {
      "could not parse package information: " <> error
    }),
  )
  use config <- result.try(json.object_get(document, "gleam.toml"))
  use name <- result.try(json.field_string(config, "name"))
  use version <- result.try(json.field_string(config, "version"))
  let description = case json.field_string(config, "description") {
    Ok(value) -> value
    Error(_) -> ""
  }
  let licences = case json.field_array(config, "licences") {
    Ok(values) ->
      values
      |> list.filter_map(fn(value) {
        case value {
          json.JString(text) -> Ok(text)
          _ -> Error(Nil)
        }
      })
    Error(_) -> []
  }
  let repository = case json.object_get(config, "repository") {
    Ok(json.JString(url)) -> Some(url)
    Ok(json.JObject(entries)) -> {
      let user = field_of(entries, "user")
      let repo = field_of(entries, "repo")
      case user, repo {
        Some(user), Some(repo) ->
          Some("https://github.com/" <> user <> "/" <> repo)
        _, _ -> None
      }
    }
    _ -> None
  }
  let target = case json.field_string(config, "target") {
    Ok(value) -> value
    Error(_) -> "erlang"
  }
  Ok(PackageInfo(
    name: name,
    version: version,
    description: description,
    licences: licences,
    repository: repository,
    target: target,
  ))
}

fn field_of(
  entries: List(#(String, json.Json)),
  key: String,
) -> Option(String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Ok(#(_, json.JString(value))) -> Some(value)
    _ -> None
  }
}

pub fn read_config(root: String) -> Result(config.Config, String) {
  let path = ffi.join_paths([root, "niffler.toml"])
  use contents <- result.try(
    read_text(path)
    |> result.map_error(fn(_) {
      "missing niffler.toml. Run `niffler init --repo owner/repo` first."
    }),
  )
  config.decode(contents)
}

pub fn read_manifest_file(path: String) -> Result(manifest.Manifest, String) {
  use contents <- result.try(read_text(path))
  manifest.decode(contents)
}

pub fn write_text_file(path: String, contents: String) -> Result(Nil, String) {
  let parent = ffi.dirname(path)
  use _ <- result.try(ffi.ensure_dir(parent))
  ffi.write_file(path, <<contents:utf8>>)
  |> result.map_error(fn(error) { "could not write " <> path <> ": " <> error })
}

pub fn read_text(path: String) -> Result(String, String) {
  use contents <- result.try(ffi.read_file(path))
  bit_array.to_string(contents)
  |> result.map_error(fn(_) { path <> " is not valid UTF-8" })
}

pub fn output_string(output: BitArray) -> String {
  case bit_array.to_string(output) {
    Ok(text) -> text
    Error(_) -> "<invalid UTF-8>"
  }
}

pub fn manifest_path(root: String) -> String {
  ffi.join_paths([root, "priv", "niffler.json"])
}

pub fn base_url(
  root_config: config.Config,
  _package: PackageInfo,
  version: String,
) -> String {
  case root_config.base_url {
    Some(url) -> strip_trailing_slashes(url)
    None ->
      "https://github.com/"
      <> root_config.repo
      <> "/releases/download/v"
      <> version
  }
}

pub fn artifact_filename(
  crate: String,
  package_version: String,
  nif_version: String,
  target: String,
) -> String {
  let prefix = case string.contains(target, "windows") {
    True -> ""
    False -> "lib"
  }
  prefix
  <> crate
  <> "-v"
  <> package_version
  <> "-nif-"
  <> nif_version
  <> "-"
  <> target
  <> "."
  <> platform.extension(target)
  <> ".tar.gz"
}

pub fn parse_artifact_filename(
  crate: String,
  filename: String,
) -> Option(#(String, String, String)) {
  // Returns #(package_version, nif_version, target).
  let prefix = "lib" <> crate <> "-v"
  let windows_prefix = crate <> "-v"
  let prefix = case string.starts_with(filename, prefix) {
    True -> prefix
    False ->
      case string.starts_with(filename, windows_prefix) {
        True -> windows_prefix
        False -> ""
      }
  }
  case prefix {
    "" -> None
    _ -> {
      let rest = string.drop_start(filename, string.length(prefix))
      case string.split(rest, "-nif-") {
        [version, after_nif] -> {
          let found =
            list.find_map(platform.supported_targets, fn(target) {
              let suffix =
                "-" <> target <> "." <> platform.extension(target) <> ".tar.gz"
              case string.ends_with(after_nif, suffix) {
                True -> {
                  let nif_version =
                    string.slice(
                      after_nif,
                      0,
                      string.length(after_nif) - string.length(suffix),
                    )
                  Ok(#(version, nif_version, target))
                }
                False -> Error(Nil)
              }
            })
          case found {
            Ok(value) -> Some(value)
            Error(_) -> None
          }
        }
        _ -> None
      }
    }
  }
}

pub fn loader_path(root: String, module: String) -> String {
  ffi.join_paths([root, "src", module <> ".erl"])
}

pub fn source_directory(root: String, root_config: config.Config) -> String {
  ffi.join_paths([root, root_config.path])
}

pub fn strip_trailing_slashes(value: String) -> String {
  case string.ends_with(value, "/") {
    True ->
      strip_trailing_slashes(string.slice(value, 0, string.length(value) - 1))
    False -> value
  }
}

pub fn version_from_tag(tag: String) -> String {
  case string.starts_with(tag, "v") {
    True -> string.drop_start(tag, 1)
    False -> tag
  }
}
