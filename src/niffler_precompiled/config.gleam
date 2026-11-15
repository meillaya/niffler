//// Parsed `niffler.toml` configuration.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import niffler_precompiled/checksum
import niffler_precompiled/platform
import niffler_precompiled/toml

pub type Function {
  Function(name: String, arity: Int)
}

pub type Config {
  Config(
    module: String,
    crate: String,
    path: String,
    functions: List(Function),
    nif_version: Option(String),
    repo: String,
    targets: List(String),
    base_url: Option(String),
  )
}

pub fn default_targets() -> List(String) {
  platform.supported_targets
}

pub fn decode(input: String) -> Result(Config, String) {
  case toml.parse(input) {
    Error(error) -> Error("niffler.toml: " <> error)
    Ok(document) -> {
      let unknown_tables =
        document
        |> toml.table_names()
        |> list.filter(fn(name) { name != "nif" && name != "release" })
      case unknown_tables {
        [] -> decode_tables(document)
        [table, ..] -> Error("niffler.toml: unknown table [" <> table <> "]")
      }
    }
  }
}

fn decode_tables(document: toml.Document) -> Result(Config, String) {
  use nif_entries <- result.try(toml.table(document, "nif"))
  use release_entries <- result.try(toml.table(document, "release"))
  use _ <- result.try(
    ensure_keys("nif", nif_entries, [
      "module",
      "crate",
      "path",
      "functions",
      "nif_version",
    ]),
  )
  use _ <- result.try(
    ensure_keys("release", release_entries, ["repo", "targets", "base_url"]),
  )

  use module <- result.try(toml.get_string(nif_entries, "module"))
  use crate <- result.try(toml.get_string(nif_entries, "crate"))
  use raw_path <- result.try(toml.get_optional_string(nif_entries, "path"))
  use raw_functions <- result.try(toml.get_optional_string_array(
    nif_entries,
    "functions",
  ))
  use raw_nif_version <- result.try(toml.get_optional_string(
    nif_entries,
    "nif_version",
  ))
  use repo <- result.try(toml.get_string(release_entries, "repo"))
  use raw_targets <- result.try(toml.get_optional_string_array(
    release_entries,
    "targets",
  ))
  use raw_base_url <- result.try(toml.get_optional_string(
    release_entries,
    "base_url",
  ))

  use _ <- result.try(validate_identifier("nif.module", module))
  use _ <- result.try(validate_identifier("nif.crate", crate))

  let path = case raw_path {
    Some(path) -> string.trim(path)
    None -> "priv/native/" <> crate
  }
  use _ <- result.try(validate_path(path))

  let path = case string.ends_with(path, "/") {
    True -> string.slice(path, 0, string.length(path) - 1)
    False -> path
  }

  use functions <- result.try(parse_functions(raw_functions))
  use nif_version <- result.try(validate_nif_version(raw_nif_version))
  use _ <- result.try(validate_repo(repo))
  use targets <- result.try(validate_targets(raw_targets))
  use base_url <- result.try(validate_base_url(raw_base_url))

  Ok(Config(
    module: module,
    crate: crate,
    path: path,
    functions: functions,
    nif_version: nif_version,
    repo: repo,
    targets: targets,
    base_url: base_url,
  ))
}

fn ensure_keys(
  table_name: String,
  entries: List(#(String, toml.Value)),
  allowed: List(String),
) -> Result(Nil, String) {
  case list.find(toml.keys(entries), fn(key) { !list.contains(allowed, key) }) {
    Ok(unknown) ->
      Error(
        "niffler.toml: unknown key `"
        <> unknown
        <> "` in ["
        <> table_name
        <> "]",
      )
    Error(_) -> Ok(Nil)
  }
}

fn validate_identifier(label: String, value: String) -> Result(Nil, String) {
  case checksum.is_identifier(value) {
    True -> Ok(Nil)
    False ->
      Error(
        "niffler.toml: `"
        <> label
        <> "` must match [a-z][a-z0-9_]* (got `"
        <> value
        <> "`)",
      )
  }
}

fn validate_path(path: String) -> Result(Nil, String) {
  let invalid =
    path == ""
    || string.starts_with(path, "/")
    || string.contains(path, "..")
    || string.contains(path, "\\")
    || string.contains(path, "//")
  case invalid {
    True ->
      Error(
        "niffler.toml: `nif.path` must be a relative path inside priv/ (got `"
        <> path
        <> "`)",
      )
    False ->
      case string.starts_with(path, "priv/") {
        True -> Ok(Nil)
        False ->
          Error(
            "niffler.toml: `nif.path` must live under priv/ because only priv/ is shipped to Hex (got `"
            <> path
            <> "`)",
          )
      }
  }
}

fn parse_functions(
  values: Option(List(String)),
) -> Result(List(Function), String) {
  case values {
    None -> Ok([])
    Some(values) -> {
      use functions <- result.try(
        values
        |> list.map(parse_function)
        |> result.all,
      )
      case duplicate_functions(functions) {
        Ok(Nil) -> Ok(functions)
        Error(error) -> Error(error)
      }
    }
  }
}

fn parse_function(value: String) -> Result(Function, String) {
  case string.split(string.trim(value), "/") {
    [name, arity] -> {
      case checksum.is_function_name(string.trim(name)) {
        False ->
          Error("niffler.toml: invalid NIF function name in `" <> value <> "`")
        True ->
          case int.parse(string.trim(arity)) {
            Error(_) ->
              Error("niffler.toml: invalid arity in `" <> value <> "`")
            Ok(arity) ->
              case arity >= 0 && arity <= 255 {
                False ->
                  Error(
                    "niffler.toml: arity must be between 0 and 255 in `"
                    <> value
                    <> "`",
                  )
                True ->
                  case string.trim(name) == "init" && arity == 0 {
                    True ->
                      Error(
                        "niffler.toml: `init/0` is reserved for the generated loader",
                      )
                    False ->
                      case string.trim(name) == "module_info" {
                        True ->
                          Error(
                            "niffler.toml: `module_info` is reserved by the Erlang compiler",
                          )
                        False -> Ok(Function(string.trim(name), arity))
                      }
                  }
              }
          }
      }
    }
    _ ->
      Error(
        "niffler.toml: functions must look like `name/arity` (got `"
        <> value
        <> "`)",
      )
  }
}

fn duplicate_functions(functions: List(Function)) -> Result(Nil, String) {
  case functions {
    [] -> Ok(Nil)
    [function, ..rest] -> {
      case
        list.find(rest, fn(other) {
          other.name == function.name && other.arity == function.arity
        })
      {
        Ok(_) ->
          Error(
            "niffler.toml: duplicate function "
            <> function.name
            <> "/"
            <> int.to_string(function.arity),
          )
        Error(_) -> duplicate_functions(rest)
      }
    }
  }
}

fn validate_nif_version(
  value: Option(String),
) -> Result(Option(String), String) {
  case value {
    None -> Ok(None)
    Some(version) ->
      case checksum.is_supported_nif_version(version) {
        True -> Ok(Some(version))
        False ->
          Error(
            "niffler.toml: unsupported nif_version `"
            <> version
            <> "` (supported: "
            <> string.join(platform.supported_nif_versions(), ", ")
            <> ")",
          )
      }
  }
}

fn validate_repo(value: String) -> Result(Nil, String) {
  case string.split(value, "/") {
    [owner, repository] -> {
      let valid = is_repo_component(owner) && is_repo_component(repository)
      case valid {
        True -> Ok(Nil)
        False ->
          Error(
            "niffler.toml: `release.repo` must be `owner/repository` (got `"
            <> value
            <> "`)",
          )
      }
    }
    _ ->
      Error(
        "niffler.toml: `release.repo` must be `owner/repository` (got `"
        <> value
        <> "`)",
      )
  }
}

fn is_repo_component(value: String) -> Bool {
  value != ""
  && !string.contains(value, " ")
  && list.all(string.to_graphemes(value), fn(character) {
    case character {
      "a"
      | "b"
      | "c"
      | "d"
      | "e"
      | "f"
      | "g"
      | "h"
      | "i"
      | "j"
      | "k"
      | "l"
      | "m" -> True
      "n"
      | "o"
      | "p"
      | "q"
      | "r"
      | "s"
      | "t"
      | "u"
      | "v"
      | "w"
      | "x"
      | "y"
      | "z" -> True
      "A"
      | "B"
      | "C"
      | "D"
      | "E"
      | "F"
      | "G"
      | "H"
      | "I"
      | "J"
      | "K"
      | "L"
      | "M" -> True
      "N"
      | "O"
      | "P"
      | "Q"
      | "R"
      | "S"
      | "T"
      | "U"
      | "V"
      | "W"
      | "X"
      | "Y"
      | "Z" -> True
      "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
      "_" | "-" | "." -> True
      _ -> False
    }
  })
}

fn validate_targets(raw: Option(List(String))) -> Result(List(String), String) {
  let targets = case raw {
    Some(targets) -> targets
    None -> platform.supported_targets
  }
  case targets {
    [] -> Error("niffler.toml: `release.targets` must not be empty")
    _ -> {
      let unsupported =
        list.find(targets, fn(target) {
          !list.contains(platform.supported_targets, target)
        })
      case unsupported {
        Ok(target) ->
          Error(
            "niffler.toml: unsupported target `"
            <> target
            <> "` (supported: "
            <> string.join(platform.supported_targets, ", ")
            <> ")",
          )
        Error(_) ->
          case find_duplicate(targets) {
            Ok(target) ->
              Error("niffler.toml: duplicate target `" <> target <> "`")
            Error(_) -> Ok(targets)
          }
      }
    }
  }
}

fn find_duplicate(values: List(String)) -> Result(String, Nil) {
  case values {
    [] -> Error(Nil)
    [value, ..rest] ->
      case list.contains(rest, value) {
        True -> Ok(value)
        False -> find_duplicate(rest)
      }
  }
}

fn validate_base_url(raw: Option(String)) -> Result(Option(String), String) {
  case raw {
    None -> Ok(None)
    Some(url) -> {
      case string.starts_with(url, "https://") && !string.contains(url, " ") {
        True -> Ok(Some(url))
        False ->
          Error("niffler.toml: `release.base_url` must be an https:// URL")
      }
    }
  }
}
