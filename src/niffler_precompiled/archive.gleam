//// Safe extraction of NIF artifacts.

import gleam/list
import gleam/string
import niffler_precompiled/errors.{type NifflerError, ExtractInvalid}
import niffler_precompiled/ffi
import niffler_precompiled/manifest.{type Artifact}
import niffler_precompiled/platform

const max_uncompressed_size = 268_435_456

pub fn expected_member(crate: String, target: String) -> String {
  crate <> "." <> platform.extension(target)
}

pub fn extract(
  crate: String,
  artifact: Artifact,
  tarball: BitArray,
) -> Result(BitArray, NifflerError) {
  let expected = expected_member(crate, artifact.target)
  case ffi.tar_inspect_gz(tarball) {
    Error(error) ->
      Error(ExtractInvalid("could not read tar.gz archive: " <> error))
    Ok(entries) -> {
      case entries {
        [entry] ->
          case entry.name == expected {
            False ->
              Error(ExtractInvalid(
                "archive contains `"
                <> entry.name
                <> "` but `"
                <> expected
                <> "` was expected",
              ))
            True ->
              case entry.kind == "regular" {
                False ->
                  Error(ExtractInvalid(
                    "archive member `" <> expected <> "` is not a regular file",
                  ))
                True ->
                  case entry.size <= max_uncompressed_size {
                    False ->
                      Error(ExtractInvalid(
                        "archive member is too large: "
                        <> int_string(entry.size)
                        <> " bytes",
                      ))
                    True -> extract_member(artifact, tarball, expected)
                  }
              }
          }
        [] -> Error(ExtractInvalid("archive is empty"))
        _ ->
          Error(ExtractInvalid(
            "archive must contain exactly one file, found "
            <> int_string(list.length(entries)),
          ))
      }
    }
  }
}

fn extract_member(
  artifact: Artifact,
  tarball: BitArray,
  expected: String,
) -> Result(BitArray, NifflerError) {
  case ffi.tar_extract_gz_member(tarball, expected) {
    Error(error) ->
      Error(ExtractInvalid("could not extract archive member: " <> error))
    Ok(contents) -> {
      let expected_magic = magic_for_target(artifact.target)
      let actual_magic = magic(contents)
      case actual_magic == expected_magic {
        True -> Ok(contents)
        False ->
          Error(ExtractInvalid(
            "artifact does not look like a "
            <> expected_magic
            <> " shared library (magic: "
            <> actual_magic
            <> ")",
          ))
      }
    }
  }
}

fn magic_for_target(target: String) -> String {
  case string.contains(target, "windows") {
    True -> "pe"
    False ->
      case string.contains(target, "darwin") {
        True -> "macho"
        False -> "elf"
      }
  }
}

fn magic(contents: BitArray) -> String {
  case contents {
    <<0x7F, 0x45, 0x4C, 0x46, _:bits>> -> "elf"
    <<0xFE, 0xED, 0xFA, 0xCF, _:bits>> -> "macho"
    <<0xCF, 0xFA, 0xED, 0xFE, _:bits>> -> "macho"
    <<0xCA, 0xFE, 0xBA, 0xBE, _:bits>> -> "macho"
    <<0x4D, 0x5A, _:bits>> -> "pe"
    _ -> "unknown"
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
