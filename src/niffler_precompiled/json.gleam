//// A small, strict JSON reader/writer used for manifests and for reading
//// `gleam export package-information` output.
////
//// We deliberately avoid a JSON dependency: the runtime library must be
//// stdlib-only, and manifest parsing is on the trusted path.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const max_depth = 64

pub const max_size = 16_777_216

pub type Json {
  JNull
  JBool(Bool)
  JInt(Int)
  JFloat(Float)
  JString(String)
  JArray(List(Json))
  JObject(List(#(String, Json)))
}

pub fn parse(input: String) -> Result(Json, String) {
  case string.length(input) > max_size {
    True -> Error("JSON document is too large")
    False -> {
      let chars = string.to_graphemes(input)
      case parse_value(chars, 0, 0) {
        Error(error) -> Error(error)
        Ok(#(value, position)) -> {
          let position = skip_whitespace(chars, position)
          case position == list.length(chars) {
            True -> Ok(value)
            False -> Error("Unexpected trailing data in JSON document")
          }
        }
      }
    }
  }
}

fn parse_value(
  chars: List(String),
  position: Int,
  depth: Int,
) -> Result(#(Json, Int), String) {
  case depth > max_depth {
    True -> Error("JSON document is nested too deeply")
    False -> {
      let position = skip_whitespace(chars, position)
      case at(chars, position) {
        Error(error) -> Error(error)
        Ok("\"") -> parse_string(chars, position, [])
        Ok("{") -> parse_object(chars, position + 1, depth + 1, [])
        Ok("[") -> parse_array(chars, position + 1, depth + 1, [])
        Ok("t") -> parse_literal(chars, position, "true", JBool(True))
        Ok("f") -> parse_literal(chars, position, "false", JBool(False))
        Ok("n") -> parse_literal(chars, position, "null", JNull)
        Ok(character) ->
          case is_number_start(character) {
            True -> parse_number(chars, position)
            False ->
              Error(
                "Unexpected character at position "
                <> int.to_string(position)
                <> ": "
                <> character,
              )
          }
      }
    }
  }
}

fn parse_literal(
  chars: List(String),
  position: Int,
  literal: String,
  value: Json,
) -> Result(#(Json, Int), String) {
  let end = position + string.length(literal)
  let found = list.drop(chars, position) |> list.take(string.length(literal))
  case string.join(found, "") == literal {
    True -> Ok(#(value, end))
    False ->
      Error("Invalid JSON literal at position " <> int.to_string(position))
  }
}

fn is_number_start(character: String) -> Bool {
  character == "-" || is_digit(character)
}

fn is_digit(character: String) -> Bool {
  case character {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn parse_number(
  chars: List(String),
  position: Int,
) -> Result(#(Json, Int), String) {
  let end = number_end(chars, position)
  let body =
    list.drop(chars, position) |> list.take(end - position) |> string.join("")
  let is_float =
    string.contains(body, ".")
    || string.contains(body, "e")
    || string.contains(body, "E")
  case is_float {
    True ->
      case float.parse(body) {
        Ok(value) -> Ok(#(JFloat(value), end))
        Error(_) ->
          Error("Invalid JSON number at position " <> int.to_string(position))
      }
    False ->
      case int.parse(body) {
        Ok(value) -> Ok(#(JInt(value), end))
        Error(_) ->
          Error("Invalid JSON number at position " <> int.to_string(position))
      }
  }
}

fn number_end(chars: List(String), current: Int) -> Int {
  case at(chars, current) {
    Ok(character) ->
      case is_number_character(character) {
        True -> number_end(chars, current + 1)
        False -> current
      }
    Error(_) -> current
  }
}

fn is_number_character(character: String) -> Bool {
  is_digit(character)
  || character == "-"
  || character == "+"
  || character == "."
  || character == "e"
  || character == "E"
}

fn parse_string(
  chars: List(String),
  position: Int,
  accumulator: List(String),
) -> Result(#(Json, Int), String) {
  case at(chars, position + 1) {
    Error(_) -> Error("Unterminated JSON string")
    Ok("\"") ->
      Ok(#(JString(string.join(list.reverse(accumulator), "")), position + 2))
    Ok("\\") -> parse_escape(chars, position + 2, accumulator)
    Ok(character) ->
      case is_control_character(character) {
        True -> Error("Unescaped control character in JSON string")
        False -> parse_string(chars, position + 1, [character, ..accumulator])
      }
  }
}

fn parse_escape(
  chars: List(String),
  position: Int,
  accumulator: List(String),
) -> Result(#(Json, Int), String) {
  case at(chars, position) {
    Error(_) -> Error("Unterminated JSON escape")
    Ok("\\") -> parse_string(chars, position, ["\\", ..accumulator])
    Ok("/") -> parse_string(chars, position, ["/", ..accumulator])
    Ok("\"") -> parse_string(chars, position, ["\"", ..accumulator])
    Ok("b") ->
      parse_string(chars, position, [codepoint_string(8), ..accumulator])
    Ok("f") ->
      parse_string(chars, position, [codepoint_string(12), ..accumulator])
    Ok("n") -> parse_string(chars, position, ["\n", ..accumulator])
    Ok("r") -> parse_string(chars, position, ["\r", ..accumulator])
    Ok("t") -> parse_string(chars, position, ["\t", ..accumulator])
    Ok("u") -> parse_unicode_escape(chars, position + 1, accumulator)
    Ok(character) -> Error("Invalid JSON escape: \\" <> character)
  }
}

fn parse_unicode_escape(
  chars: List(String),
  position: Int,
  accumulator: List(String),
) -> Result(#(Json, Int), String) {
  case read_hex4(chars, position) {
    Error(error) -> Error(error)
    Ok(#(code, position_after)) ->
      case is_high_surrogate(code) {
        True ->
          case at(chars, position_after) {
            Ok("\\") ->
              case at(chars, position_after + 1) {
                Ok("u") ->
                  case read_hex4(chars, position_after + 2) {
                    Ok(#(low, position_after_low)) ->
                      case is_low_surrogate(low) {
                        True -> {
                          let combined =
                            0x10000
                            + { code - 0xD800 }
                            * 0x400
                            + { low - 0xDC00 }
                          append_codepoint(
                            chars,
                            position_after_low,
                            combined,
                            accumulator,
                          )
                        }
                        False -> Error("Invalid low surrogate in JSON string")
                      }
                    Error(error) -> Error(error)
                  }
                _ -> Error("Invalid surrogate pair in JSON string")
              }
            _ -> Error("Invalid surrogate pair in JSON string")
          }
        False ->
          case is_low_surrogate(code) {
            True -> Error("Unexpected low surrogate in JSON string")
            False -> append_codepoint(chars, position_after, code, accumulator)
          }
      }
  }
}

fn append_codepoint(
  chars: List(String),
  position: Int,
  code: Int,
  accumulator: List(String),
) -> Result(#(Json, Int), String) {
  case string.utf_codepoint(code) {
    Error(_) -> Error("Invalid Unicode code point in JSON string")
    Ok(codepoint) ->
      parse_string(chars, position - 1, [
        string.from_utf_codepoints([codepoint]),
        ..accumulator
      ])
  }
}

fn read_hex4(
  chars: List(String),
  position: Int,
) -> Result(#(Int, Int), String) {
  let digits = list.drop(chars, position) |> list.take(4)
  case list.length(digits) == 4 {
    False -> Error("Incomplete Unicode escape in JSON string")
    True ->
      case
        list.fold(digits, Ok(0), fn(acc, digit) {
          case acc, hex_value(digit) {
            Ok(value), Ok(digit_value) -> Ok(value * 16 + digit_value)
            Error(error), _ -> Error(error)
            _, Error(_) -> Error("Invalid Unicode escape in JSON string")
          }
        })
      {
        Ok(value) -> Ok(#(value, position + 4))
        Error(error) -> Error(error)
      }
  }
}

fn hex_value(character: String) -> Result(Int, Nil) {
  case character {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" | "A" -> Ok(10)
    "b" | "B" -> Ok(11)
    "c" | "C" -> Ok(12)
    "d" | "D" -> Ok(13)
    "e" | "E" -> Ok(14)
    "f" | "F" -> Ok(15)
    _ -> Error(Nil)
  }
}

fn codepoint_string(code: Int) -> String {
  case string.utf_codepoint(code) {
    Ok(codepoint) -> string.from_utf_codepoints([codepoint])
    Error(_) -> ""
  }
}

fn is_high_surrogate(code: Int) -> Bool {
  code >= 0xD800 && code <= 0xDBFF
}

fn is_low_surrogate(code: Int) -> Bool {
  code >= 0xDC00 && code <= 0xDFFF
}

fn is_control_character(character: String) -> Bool {
  case string.to_utf_codepoints(character) {
    [codepoint] -> string.utf_codepoint_to_int(codepoint) < 32
    _ -> False
  }
}

fn parse_array(
  chars: List(String),
  position: Int,
  depth: Int,
  accumulator: List(Json),
) -> Result(#(Json, Int), String) {
  let position = skip_whitespace(chars, position)
  case at(chars, position) {
    Error(_) -> Error("Unterminated JSON array")
    Ok("]") -> Ok(#(JArray(list.reverse(accumulator)), position + 1))
    _ -> {
      case parse_value(chars, position, depth) {
        Error(error) -> Error(error)
        Ok(#(value, position_after)) -> {
          let position = skip_whitespace(chars, position_after)
          case at(chars, position) {
            Ok(",") -> {
              let next = skip_whitespace(chars, position + 1)
              case at(chars, next) {
                Ok("]") -> Error("Trailing comma in JSON array")
                _ ->
                  parse_array(chars, position + 1, depth, [value, ..accumulator])
              }
            }
            Ok("]") ->
              Ok(#(JArray(list.reverse([value, ..accumulator])), position + 1))
            _ -> Error("Expected ',' or ']' in JSON array")
          }
        }
      }
    }
  }
}

fn parse_object(
  chars: List(String),
  position: Int,
  depth: Int,
  accumulator: List(#(String, Json)),
) -> Result(#(Json, Int), String) {
  let position = skip_whitespace(chars, position)
  case at(chars, position) {
    Error(_) -> Error("Unterminated JSON object")
    Ok("}") -> Ok(#(JObject(list.reverse(accumulator)), position + 1))
    Ok("\"") ->
      case parse_string(chars, position, []) {
        Error(error) -> Error(error)
        Ok(#(JString(key), position_after_key)) -> {
          let position = skip_whitespace(chars, position_after_key)
          case at(chars, position) {
            Ok(":") -> {
              case parse_value(chars, position + 1, depth) {
                Error(error) -> Error(error)
                Ok(#(value, position_after_value)) -> {
                  case has_key(accumulator, key) {
                    True -> Error("Duplicate key in JSON object: " <> key)
                    False -> {
                      let position =
                        skip_whitespace(chars, position_after_value)
                      case at(chars, position) {
                        Ok(",") -> {
                          let next = skip_whitespace(chars, position + 1)
                          case at(chars, next) {
                            Ok("}") -> Error("Trailing comma in JSON object")
                            _ ->
                              parse_object(chars, position + 1, depth, [
                                #(key, value),
                                ..accumulator
                              ])
                          }
                        }
                        Ok("}") ->
                          Ok(#(
                            JObject(
                              list.reverse([#(key, value), ..accumulator]),
                            ),
                            position + 1,
                          ))
                        _ -> Error("Expected ',' or '}' in JSON object")
                      }
                    }
                  }
                }
              }
            }
            _ -> Error("Expected ':' after JSON object key")
          }
        }
        Ok(_) -> Error("Invalid JSON object key")
      }
    Ok(_) -> Error("Expected string key in JSON object")
  }
}

fn has_key(entries: List(#(String, Json)), key: String) -> Bool {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn at(chars: List(String), position: Int) -> Result(String, String) {
  case list.drop(chars, position) {
    [character, ..] -> Ok(character)
    [] -> Error("Unexpected end of JSON document")
  }
}

fn skip_whitespace(chars: List(String), position: Int) -> Int {
  case at(chars, position) {
    Ok(character) -> {
      case character {
        " " | "\n" | "\r" | "\t" -> skip_whitespace(chars, position + 1)
        _ -> position
      }
    }
    Error(_) -> position
  }
}

// ---------------------------------------------------------------------------
// Encoding

pub fn encode(json: Json) -> String {
  encode_at(json, 0)
}

fn encode_at(json: Json, indent: Int) -> String {
  case json {
    JNull -> "null"
    JBool(True) -> "true"
    JBool(False) -> "false"
    JInt(value) -> int.to_string(value)
    JFloat(value) -> float.to_string(value)
    JString(value) -> "\"" <> escape_string(value) <> "\""
    JArray(values) ->
      case values {
        [] -> "[]"
        _ -> {
          let inner =
            values
            |> list.map(fn(value) {
              indent_string(indent + 2) <> encode_at(value, indent + 2)
            })
            |> string.join(",\n")
          "[\n" <> inner <> "\n" <> indent_string(indent) <> "]"
        }
      }
    JObject(entries) ->
      case entries {
        [] -> "{}"
        _ -> {
          let sorted = list.sort(entries, fn(a, b) { string.compare(a.0, b.0) })
          let inner =
            sorted
            |> list.map(fn(entry) {
              indent_string(indent + 2)
              <> "\""
              <> escape_string(entry.0)
              <> "\": "
              <> encode_at(entry.1, indent + 2)
            })
            |> string.join(",\n")
          "{\n" <> inner <> "\n" <> indent_string(indent) <> "}"
        }
      }
  }
}

fn indent_string(width: Int) -> String {
  string.repeat(" ", width)
}

pub fn escape_string(value: String) -> String {
  value
  |> string.to_graphemes()
  |> list.map(escape_character)
  |> string.join("")
}

fn escape_character(character: String) -> String {
  case character {
    "\"" -> "\\\""
    "\\" -> "\\\\"
    "\n" -> "\\n"
    "\r" -> "\\r"
    "\t" -> "\\t"
    _ ->
      case string.to_utf_codepoints(character) {
        [codepoint] ->
          case string.utf_codepoint_to_int(codepoint) < 32 {
            True -> {
              let code = string.utf_codepoint_to_int(codepoint)
              let hex = case int.to_base_string(code, 16) {
                Ok(value) -> value
                Error(_) -> "0"
              }
              "\\u00" <> string.pad_start(hex, 2, "0")
            }
            False -> character
          }
        _ -> character
      }
  }
}

// ---------------------------------------------------------------------------
// Convenience accessors

pub fn object_get(json: Json, key: String) -> Result(Json, String) {
  case json {
    JObject(entries) ->
      case list.find(entries, fn(entry) { entry.0 == key }) {
        Ok(entry) -> Ok(entry.1)
        Error(_) -> Error("Missing JSON key: " <> key)
      }
    _ -> Error("Expected a JSON object")
  }
}

pub fn as_string(json: Json) -> Result(String, String) {
  case json {
    JString(value) -> Ok(value)
    _ -> Error("Expected a JSON string")
  }
}

pub fn as_int(json: Json) -> Result(Int, String) {
  case json {
    JInt(value) -> Ok(value)
    _ -> Error("Expected a JSON integer")
  }
}

pub fn as_array(json: Json) -> Result(List(Json), String) {
  case json {
    JArray(values) -> Ok(values)
    _ -> Error("Expected a JSON array")
  }
}

pub fn as_object(json: Json) -> Result(List(#(String, Json)), String) {
  case json {
    JObject(entries) -> Ok(entries)
    _ -> Error("Expected a JSON object")
  }
}

pub fn field_string(json: Json, key: String) -> Result(String, String) {
  object_get(json, key) |> result.try(as_string)
}

pub fn field_int(json: Json, key: String) -> Result(Int, String) {
  object_get(json, key) |> result.try(as_int)
}

pub fn field_optional_string(
  json: Json,
  key: String,
) -> Result(Option(String), String) {
  case object_get(json, key) {
    Error(_) -> Ok(None)
    Ok(value) -> as_string(value) |> result.map(Some)
  }
}

pub fn field_array(json: Json, key: String) -> Result(List(Json), String) {
  object_get(json, key) |> result.try(as_array)
}
