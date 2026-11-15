//// A deliberately small TOML reader for `niffler.toml`.
////
//// Supported: single-level tables, bare keys, basic/literal strings, arrays,
//// booleans, and integers. Comments and multi-line arrays are supported. This
//// is enough for niffler's own configuration and keeps the runtime dependency
//// surface at zero.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Value {
  TString(String)
  TInt(Int)
  TBool(Bool)
  TArray(List(Value))
}

pub type Table {
  Table(name: String, entries: List(#(String, Value)))
}

pub type Document {
  Document(tables: List(Table))
}

pub fn parse(input: String) -> Result(Document, String) {
  let lines =
    input
    |> string.split("\n")
    |> list.index_map(fn(line, index) {
      #(index + 1, string.replace(line, "\r", ""))
    })
  parse_lines(lines, Document([]), "")
}

fn parse_lines(
  lines: List(#(Int, String)),
  document: Document,
  current_table: String,
) -> Result(Document, String) {
  case lines {
    [] -> Ok(document)
    [#(line_number, line), ..rest] -> {
      let stripped = strip_comment(line) |> string.trim()
      case stripped {
        "" -> parse_lines(rest, document, current_table)
        _ ->
          case string.starts_with(stripped, "[[") {
            True ->
              Error(at_line(line_number, "arrays of tables are not supported"))
            False ->
              case string.starts_with(stripped, "[") {
                True -> {
                  case parse_table_header(stripped) {
                    Error(error) -> Error(at_line(line_number, error))
                    Ok(name) ->
                      case table_exists(document, name) {
                        True ->
                          Error(at_line(
                            line_number,
                            "duplicate table [" <> name <> "]",
                          ))
                        False -> {
                          let document =
                            add_table(document, Table(name: name, entries: []))
                          parse_lines(rest, document, name)
                        }
                      }
                  }
                }
                False -> {
                  case current_table {
                    "" ->
                      Error(at_line(
                        line_number,
                        "key/value pairs must appear after a table header such as [nif]",
                      ))
                    _ -> {
                      case collect_value(stripped, rest) {
                        Error(error) -> Error(at_line(line_number, error))
                        Ok(#(key, value, remaining)) -> {
                          case parse_key(key) {
                            Error(error) -> Error(at_line(line_number, error))
                            Ok(key) ->
                              case
                                add_entry(document, current_table, key, value)
                              {
                                Error(error) ->
                                  Error(at_line(line_number, error))
                                Ok(document) ->
                                  parse_lines(
                                    remaining,
                                    document,
                                    current_table,
                                  )
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
    }
  }
}

fn at_line(line_number: Int, message: String) -> String {
  "line " <> int.to_string(line_number) <> ": " <> message
}

fn table_exists(document: Document, name: String) -> Bool {
  case list.find(document.tables, fn(table) { table.name == name }) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn add_table(document: Document, table: Table) -> Document {
  Document(tables: list.append(document.tables, [table]))
}

fn add_entry(
  document: Document,
  table_name: String,
  key: String,
  value: Value,
) -> Result(Document, String) {
  let Document(tables: tables) = document
  case
    list.index_map(tables, fn(table, index) { #(table, index) })
    |> list.find(fn(entry) { entry.0.name == table_name })
  {
    Error(_) -> Error("unknown table [" <> table_name <> "]")
    Ok(#(table, index)) ->
      case list.find(table.entries, fn(entry) { entry.0 == key }) {
        Ok(_) ->
          Error("duplicate key `" <> key <> "` in [" <> table_name <> "]")
        Error(_) -> {
          let updated =
            Table(name: table.name, entries: [#(key, value), ..table.entries])
          let tables =
            list.index_map(tables, fn(current, current_index) {
              case current_index == index {
                True -> updated
                False -> current
              }
            })
          Ok(Document(tables: tables))
        }
      }
  }
}

fn parse_table_header(line: String) -> Result(String, String) {
  case string.ends_with(line, "]") {
    False -> Error("invalid table header: " <> line)
    True -> {
      let name = string.slice(line, 1, string.length(line) - 2) |> string.trim()
      case name {
        "" -> Error("empty table header")
        _ ->
          case string.contains(name, ".") {
            True -> Error("nested tables are not supported: " <> name)
            False ->
              case parse_key(name) {
                Ok(_) -> Ok(name)
                Error(error) -> Error(error)
              }
          }
      }
    }
  }
}

fn parse_key(key: String) -> Result(String, String) {
  let trimmed = string.trim(key)
  case trimmed {
    "" -> Error("empty key")
    _ -> {
      case string.to_graphemes(trimmed) |> list.all(is_key_character) {
        True -> Ok(trimmed)
        False -> Error("invalid key: " <> trimmed)
      }
    }
  }
}

fn is_key_character(character: String) -> Bool {
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
    "_" | "-" -> True
    _ -> False
  }
}

/// Collect a key/value statement, joining continuation lines when the value is
/// an array that spans multiple lines.
fn collect_value(
  line: String,
  rest: List(#(Int, String)),
) -> Result(#(String, Value, List(#(Int, String))), String) {
  case split_assignment(line) {
    Error(error) -> Error(error)
    Ok(#(key, raw_value)) -> {
      case value_complete(raw_value) {
        Ok(True) -> {
          case parse_value(raw_value) {
            Error(error) -> Error(error)
            Ok(value) -> Ok(#(key, value, rest))
          }
        }
        Ok(False) -> collect_continuation(key, rest, raw_value)
        Error(error) -> Error(error)
      }
    }
  }
}

fn collect_continuation(
  key: String,
  rest: List(#(Int, String)),
  accumulated: String,
) -> Result(#(String, Value, List(#(Int, String))), String) {
  case rest {
    [] -> Error("unterminated array value for key `" <> key <> "`")
    [#(_line_number, line), ..remaining] -> {
      let next = accumulated <> "\n" <> strip_comment(line)
      case value_complete(next) {
        Ok(True) ->
          case parse_value(next) {
            Error(error) -> Error(error)
            Ok(value) -> Ok(#(key, value, remaining))
          }
        Ok(False) -> collect_continuation(key, remaining, next)
        Error(error) -> Error(error)
      }
    }
  }
}

fn split_assignment(line: String) -> Result(#(String, String), String) {
  let characters = string.to_graphemes(line)
  split_assignment_loop(characters, [], None, False)
}

fn split_assignment_loop(
  characters: List(String),
  key_accumulator: List(String),
  quote: Option(String),
  escaped: Bool,
) -> Result(#(String, String), String) {
  case characters {
    [] -> Error("expected `key = value`")
    [character, ..rest] ->
      case quote {
        Some(_) ->
          case escaped {
            True ->
              split_assignment_loop(
                rest,
                [character, ..key_accumulator],
                quote,
                False,
              )
            False ->
              case character {
                "\\" ->
                  split_assignment_loop(
                    rest,
                    [character, ..key_accumulator],
                    quote,
                    True,
                  )
                "\"" | "'" -> {
                  let next_quote = case quote, character {
                    Some("\""), "\"" -> None
                    Some("'"), "'" -> None
                    _, _ -> quote
                  }
                  split_assignment_loop(
                    rest,
                    [character, ..key_accumulator],
                    next_quote,
                    False,
                  )
                }
                _ ->
                  split_assignment_loop(
                    rest,
                    [character, ..key_accumulator],
                    quote,
                    False,
                  )
              }
          }
        None ->
          case character {
            "\"" | "'" -> {
              let quote = case character {
                "\"" -> Some("\"")
                "'" -> Some("'")
                _ -> None
              }
              split_assignment_loop(
                rest,
                [character, ..key_accumulator],
                quote,
                False,
              )
            }
            "=" -> {
              let key =
                string.join(list.reverse(key_accumulator), "") |> string.trim()
              case key {
                "" -> Error("empty key before `=`")
                _ -> Ok(#(key, string.join(rest, "")))
              }
            }
            _ ->
              split_assignment_loop(
                rest,
                [character, ..key_accumulator],
                None,
                False,
              )
          }
      }
  }
}

fn value_complete(value: String) -> Result(Bool, String) {
  let characters = string.to_graphemes(value)
  count_brackets(characters, 0, None, False)
}

fn count_brackets(
  characters: List(String),
  balance: Int,
  quote: Option(String),
  escaped: Bool,
) -> Result(Bool, String) {
  case characters {
    [] ->
      case balance == 0 {
        True -> Ok(True)
        False -> Ok(False)
      }
    [character, ..rest] ->
      case quote {
        Some(_) ->
          case escaped {
            True -> count_brackets(rest, balance, quote, False)
            False ->
              case character {
                "\\" -> count_brackets(rest, balance, quote, True)
                "\"" | "'" -> {
                  let next_quote = case quote, character {
                    Some("\""), "\"" -> None
                    Some("'"), "'" -> None
                    _, _ -> quote
                  }
                  count_brackets(rest, balance, next_quote, False)
                }
                _ -> count_brackets(rest, balance, quote, False)
              }
          }
        None ->
          case character {
            "\"" | "'" -> {
              let quote = case character {
                "\"" -> Some("\"")
                "'" -> Some("'")
                _ -> None
              }
              count_brackets(rest, balance, quote, False)
            }
            "[" -> count_brackets(rest, balance + 1, None, False)
            "]" -> count_brackets(rest, balance - 1, None, False)
            _ -> count_brackets(rest, balance, None, False)
          }
      }
  }
}

pub fn parse_value(raw: String) -> Result(Value, String) {
  let value = string.trim(raw)
  case value {
    "" -> Error("empty value")
    _ ->
      case string.starts_with(value, "\"") {
        True -> parse_basic_string(value)
        False ->
          case string.starts_with(value, "'") {
            True -> parse_literal_string(value)
            False ->
              case string.starts_with(value, "[") {
                True -> parse_array(value)
                False -> parse_scalar(value)
              }
          }
      }
  }
}

fn parse_scalar(value: String) -> Result(Value, String) {
  case value {
    "true" -> Ok(TBool(True))
    "false" -> Ok(TBool(False))
    _ ->
      case int.parse(value) {
        Ok(number) -> Ok(TInt(number))
        Error(_) -> Error("unsupported TOML value: " <> value)
      }
  }
}

fn parse_basic_string(value: String) -> Result(Value, String) {
  let characters = string.to_graphemes(value)
  case characters {
    ["\"", ..rest] -> parse_basic_string_loop(rest, [])
    _ -> Error("invalid string value: " <> value)
  }
}

fn parse_basic_string_loop(
  characters: List(String),
  accumulator: List(String),
) -> Result(Value, String) {
  case characters {
    [] -> Error("unterminated string value")
    ["\"", ..rest] -> {
      case trailing_ignorable(rest) {
        True -> Ok(TString(string.join(list.reverse(accumulator), "")))
        False -> Error("unexpected characters after string value")
      }
    }
    ["\\", ..rest] -> {
      case rest {
        [] -> Error("unterminated escape in string value")
        [escape, ..remaining] ->
          case escape {
            "\"" -> parse_basic_string_loop(remaining, ["\"", ..accumulator])
            "\\" -> parse_basic_string_loop(remaining, ["\\", ..accumulator])
            "n" -> parse_basic_string_loop(remaining, ["\n", ..accumulator])
            "r" -> parse_basic_string_loop(remaining, ["\r", ..accumulator])
            "t" -> parse_basic_string_loop(remaining, ["\t", ..accumulator])
            "b" ->
              parse_basic_string_loop(remaining, [codepoint(8), ..accumulator])
            "f" ->
              parse_basic_string_loop(remaining, [codepoint(12), ..accumulator])
            "u" -> {
              case read_hex_escape(remaining, 4) {
                Error(error) -> Error(error)
                Ok(#(code, after_escape)) -> {
                  case codepoint_or_empty(code) {
                    "" -> Error("invalid unicode escape in string value")
                    text ->
                      parse_basic_string_loop(after_escape, [
                        text,
                        ..accumulator
                      ])
                  }
                }
              }
            }
            "U" -> {
              case read_hex_escape(remaining, 8) {
                Error(error) -> Error(error)
                Ok(#(code, after_escape)) -> {
                  case codepoint_or_empty(code) {
                    "" -> Error("invalid unicode escape in string value")
                    text ->
                      parse_basic_string_loop(after_escape, [
                        text,
                        ..accumulator
                      ])
                  }
                }
              }
            }
            other ->
              Error("unsupported escape \\" <> other <> " in string value")
          }
      }
    }
    [character, ..rest] ->
      parse_basic_string_loop(rest, [character, ..accumulator])
  }
}

fn parse_literal_string(value: String) -> Result(Value, String) {
  let characters = string.to_graphemes(value)
  case characters {
    ["'", ..rest] -> literal_string_loop(rest, [])
    _ -> Error("invalid string value: " <> value)
  }
}

fn literal_string_loop(
  characters: List(String),
  accumulator: List(String),
) -> Result(Value, String) {
  case characters {
    [] -> Error("unterminated string value")
    ["'", ..rest] -> {
      case trailing_ignorable(rest) {
        True -> Ok(TString(string.join(list.reverse(accumulator), "")))
        False -> Error("unexpected characters after string value")
      }
    }
    [character, ..rest] -> literal_string_loop(rest, [character, ..accumulator])
  }
}

fn trailing_ignorable(characters: List(String)) -> Bool {
  case
    list.drop_while(characters, fn(character) {
      character == " " || character == "\t"
    })
  {
    [] -> True
    _ -> False
  }
}

fn read_hex_escape(
  characters: List(String),
  count: Int,
) -> Result(#(Int, List(String)), String) {
  let digits = list.take(characters, count)
  case list.length(digits) == count {
    False -> Error("incomplete unicode escape")
    True ->
      case
        list.fold(digits, Ok(0), fn(acc, digit) {
          case acc, hex_value(digit) {
            Ok(value), Ok(digit_value) -> Ok(value * 16 + digit_value)
            Error(error), _ -> Error(error)
            _, Error(_) -> Error("invalid unicode escape")
          }
        })
      {
        Ok(value) -> Ok(#(value, list.drop(characters, count)))
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

fn codepoint(code: Int) -> String {
  case string.utf_codepoint(code) {
    Ok(codepoint) -> string.from_utf_codepoints([codepoint])
    Error(_) -> ""
  }
}

fn codepoint_or_empty(code: Int) -> String {
  codepoint(code)
}

fn parse_array(value: String) -> Result(Value, String) {
  let characters = string.to_graphemes(value)
  case characters {
    ["[", ..rest] -> parse_array_items(rest, [])
    _ -> Error("invalid array value")
  }
}

fn parse_array_items(
  characters: List(String),
  accumulator: List(Value),
) -> Result(Value, String) {
  let characters = skip_spaces(characters)
  case characters {
    [] -> Error("unterminated array value")
    ["]", ..rest] -> {
      case trailing_ignorable(rest) {
        True -> Ok(TArray(list.reverse(accumulator)))
        False -> Error("unexpected characters after array value")
      }
    }
    [",", ..rest] -> parse_array_items(rest, accumulator)
    _ -> {
      case take_array_item(characters) {
        Error(error) -> Error(error)
        Ok(#(raw_item, rest)) -> {
          case parse_value(raw_item) {
            Error(error) -> Error(error)
            Ok(item) -> parse_array_items(rest, [item, ..accumulator])
          }
        }
      }
    }
  }
}

fn skip_spaces(characters: List(String)) -> List(String) {
  case characters {
    [" ", ..rest] -> skip_spaces(rest)
    ["\n", ..rest] -> skip_spaces(rest)
    ["\t", ..rest] -> skip_spaces(rest)
    ["\r", ..rest] -> skip_spaces(rest)
    _ -> characters
  }
}

/// Take everything up to the next top-level comma or closing bracket.
fn take_array_item(
  characters: List(String),
) -> Result(#(String, List(String)), String) {
  take_array_item_loop(characters, [], None, False, 0)
}

fn take_array_item_loop(
  characters: List(String),
  accumulator: List(String),
  quote: Option(String),
  escaped: Bool,
  depth: Int,
) -> Result(#(String, List(String)), String) {
  case characters {
    [] -> Error("unterminated array value")
    [character, ..rest] ->
      case quote {
        Some(_) ->
          case escaped {
            True ->
              take_array_item_loop(
                rest,
                [character, ..accumulator],
                quote,
                False,
                depth,
              )
            False ->
              case character {
                "\\" ->
                  take_array_item_loop(
                    rest,
                    [character, ..accumulator],
                    quote,
                    True,
                    depth,
                  )
                "\"" | "'" -> {
                  let next_quote = case quote, character {
                    Some("\""), "\"" -> None
                    Some("'"), "'" -> None
                    _, _ -> quote
                  }
                  take_array_item_loop(
                    rest,
                    [character, ..accumulator],
                    next_quote,
                    False,
                    depth,
                  )
                }
                _ ->
                  take_array_item_loop(
                    rest,
                    [character, ..accumulator],
                    quote,
                    False,
                    depth,
                  )
              }
          }
        None ->
          case character {
            "\"" | "'" -> {
              let quote = case character {
                "\"" -> Some("\"")
                "'" -> Some("'")
                _ -> None
              }
              take_array_item_loop(
                rest,
                [character, ..accumulator],
                quote,
                False,
                depth,
              )
            }
            "[" ->
              take_array_item_loop(
                rest,
                [character, ..accumulator],
                None,
                False,
                depth + 1,
              )
            "]" if depth == 0 ->
              Ok(
                #(string.join(list.reverse(accumulator), "") |> string.trim(), [
                  character,
                  ..rest
                ]),
              )
            "]" ->
              take_array_item_loop(
                rest,
                [character, ..accumulator],
                None,
                False,
                depth - 1,
              )
            "," if depth == 0 ->
              Ok(#(
                string.join(list.reverse(accumulator), "") |> string.trim(),
                rest,
              ))
            _ ->
              take_array_item_loop(
                rest,
                [character, ..accumulator],
                None,
                False,
                depth,
              )
          }
      }
  }
}

fn strip_comment(line: String) -> String {
  strip_comment_loop(string.to_graphemes(line), [], None, False)
}

fn strip_comment_loop(
  characters: List(String),
  accumulator: List(String),
  quote: Option(String),
  escaped: Bool,
) -> String {
  case characters {
    [] -> string.join(list.reverse(accumulator), "")
    [character, ..rest] ->
      case quote {
        Some(_) ->
          case escaped {
            True ->
              strip_comment_loop(rest, [character, ..accumulator], quote, False)
            False ->
              case character {
                "\\" ->
                  strip_comment_loop(
                    rest,
                    [character, ..accumulator],
                    quote,
                    True,
                  )
                "\"" | "'" -> {
                  let next_quote = case quote, character {
                    Some("\""), "\"" -> None
                    Some("'"), "'" -> None
                    _, _ -> quote
                  }
                  strip_comment_loop(
                    rest,
                    [character, ..accumulator],
                    next_quote,
                    False,
                  )
                }
                _ ->
                  strip_comment_loop(
                    rest,
                    [character, ..accumulator],
                    quote,
                    False,
                  )
              }
          }
        None ->
          case character {
            "#" -> string.join(list.reverse(accumulator), "")
            "\"" | "'" -> {
              let quote = case character {
                "\"" -> Some("\"")
                "'" -> Some("'")
                _ -> None
              }
              strip_comment_loop(rest, [character, ..accumulator], quote, False)
            }
            _ ->
              strip_comment_loop(rest, [character, ..accumulator], None, False)
          }
      }
  }
}

// ---------------------------------------------------------------------------
// Accessors

pub fn table(
  document: Document,
  name: String,
) -> Result(List(#(String, Value)), String) {
  let Document(tables: tables) = document
  case list.find(tables, fn(table) { table.name == name }) {
    Ok(table) -> Ok(table.entries)
    Error(_) -> Error("missing [" <> name <> "] table")
  }
}

pub fn table_names(document: Document) -> List(String) {
  let Document(tables: tables) = document
  list.map(tables, fn(table) { table.name })
}

pub fn get_string(
  entries: List(#(String, Value)),
  key: String,
) -> Result(String, String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Error(_) -> Error("missing key `" <> key <> "`")
    Ok(#(_, value)) ->
      case value {
        TString(value) -> Ok(value)
        _ -> Error("key `" <> key <> "` must be a string")
      }
  }
}

pub fn get_int(
  entries: List(#(String, Value)),
  key: String,
) -> Result(Int, String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Error(_) -> Error("missing key `" <> key <> "`")
    Ok(#(_, value)) ->
      case value {
        TInt(value) -> Ok(value)
        _ -> Error("key `" <> key <> "` must be an integer")
      }
  }
}

pub fn get_bool(
  entries: List(#(String, Value)),
  key: String,
) -> Result(Bool, String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Error(_) -> Error("missing key `" <> key <> "`")
    Ok(#(_, value)) ->
      case value {
        TBool(value) -> Ok(value)
        _ -> Error("key `" <> key <> "` must be a boolean")
      }
  }
}

pub fn get_optional_string(
  entries: List(#(String, Value)),
  key: String,
) -> Result(Option(String), String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Error(_) -> Ok(None)
    Ok(#(_, value)) ->
      case value {
        TString(value) -> Ok(Some(value))
        _ -> Error("key `" <> key <> "` must be a string")
      }
  }
}

pub fn get_string_array(
  entries: List(#(String, Value)),
  key: String,
) -> Result(List(String), String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Error(_) -> Error("missing key `" <> key <> "`")
    Ok(#(_, value)) -> string_array(value, key)
  }
}

pub fn get_optional_string_array(
  entries: List(#(String, Value)),
  key: String,
) -> Result(Option(List(String)), String) {
  case list.find(entries, fn(entry) { entry.0 == key }) {
    Error(_) -> Ok(None)
    Ok(#(_, value)) -> string_array(value, key) |> result_map(Some)
  }
}

fn string_array(value: Value, key: String) -> Result(List(String), String) {
  case value {
    TArray(values) -> {
      case list.all(values, is_string_value) {
        True ->
          values
          |> list.map(fn(item) {
            case item {
              TString(value) -> value
              _ -> ""
            }
          })
          |> Ok
        False -> Error("key `" <> key <> "` must be an array of strings")
      }
    }
    _ -> Error("key `" <> key <> "` must be an array of strings")
  }
}

fn is_string_value(value: Value) -> Bool {
  case value {
    TString(_) -> True
    _ -> False
  }
}

fn result_map(result: Result(a, e), fun: fn(a) -> b) -> Result(b, e) {
  case result {
    Ok(value) -> Ok(fun(value))
    Error(error) -> Error(error)
  }
}

pub fn keys(entries: List(#(String, Value))) -> List(String) {
  list.map(entries, fn(entry) { entry.0 })
}
