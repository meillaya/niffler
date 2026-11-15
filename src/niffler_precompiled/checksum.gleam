//// Checksum, version, and identifier validation helpers.

import gleam/int
import gleam/list
import gleam/string

pub fn is_sha256_hex(value: String) -> Bool {
  string.length(value) == 64 && all_hex(string.to_graphemes(value))
}

fn all_hex(characters: List(String)) -> Bool {
  case characters {
    [] -> True
    [character, ..rest] ->
      case character {
        "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ->
          all_hex(rest)
        "a" | "b" | "c" | "d" | "e" | "f" -> all_hex(rest)
        _ -> False
      }
  }
}

pub fn normalize_hex(value: String) -> String {
  string.lowercase(value)
}

/// NIF versions are `major.minor`, for example "2.15" or "2.17".
pub fn parse_nif_version(value: String) -> Result(#(Int, Int), Nil) {
  case string.split(value, ".") {
    [major, minor] -> {
      case int.parse(major), int.parse(minor) {
        Ok(major), Ok(minor) if major >= 0 && minor >= 0 -> Ok(#(major, minor))
        _, _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

pub fn is_nif_version(value: String) -> Bool {
  parse_nif_version(value) |> is_ok
}

fn is_ok(result: Result(a, b)) -> Bool {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

/// A model-identifier for package, crate, and NIF module names.
pub fn is_identifier(value: String) -> Bool {
  case string.to_graphemes(value) {
    [] -> False
    [first, ..rest] -> is_lower_letter(first) && all_identifier_characters(rest)
  }
}

fn is_lower_letter(character: String) -> Bool {
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
    _ -> False
  }
}

fn all_identifier_characters(characters: List(String)) -> Bool {
  case characters {
    [] -> True
    [character, ..rest] ->
      case
        is_lower_letter(character) || is_digit(character) || character == "_"
      {
        True -> all_identifier_characters(rest)
        False -> False
      }
  }
}

fn is_digit(character: String) -> Bool {
  case character {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

pub fn is_function_name(value: String) -> Bool {
  is_identifier(value)
}

/// Artifact file names must be a plain basename: no path separators, `..`, or
/// control characters.
pub fn is_plain_filename(value: String) -> Bool {
  value != ""
  && value != "."
  && value != ".."
  && !string.contains(value, "/")
  && !string.contains(value, "\\")
  && !string.contains(value, "..")
}

pub fn is_supported_nif_version(value: String) -> Bool {
  case parse_nif_version(value) {
    Ok(#(2, minor)) -> list.contains([14, 15, 16, 17, 18], minor)
    _ -> False
  }
}

pub fn nif_compatible(runtime: String, artifact: String) -> Bool {
  case parse_nif_version(runtime), parse_nif_version(artifact) {
    Ok(#(runtime_major, runtime_minor)), Ok(#(artifact_major, artifact_minor))
    -> runtime_major == artifact_major && artifact_minor <= runtime_minor
    _, _ -> False
  }
}
