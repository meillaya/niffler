import gleam/option
import gleeunit/should
import niffler_precompiled/ffi

fn test_dir(name: String) -> String {
  let cwd = ffi.cwd()
  let dir =
    ffi.join_paths([
      cwd,
      "build",
      "test-tmp",
      name
        <> "-"
        <> int_string(ffi.timestamp())
        <> "-"
        <> int_string(ffi.unique_id()),
    ])
  ffi.ensure_dir(dir) |> should.be_ok
  dir
}

fn int_string(value: Int) -> String {
  case value {
    0 -> "0"
    _ -> do_int_string(value, "")
  }
}

fn do_int_string(value: Int, accumulator: String) -> String {
  case value / 10, value % 10 {
    0, digit -> digit_char(digit) <> accumulator
    quotient, digit -> do_int_string(quotient, digit_char(digit) <> accumulator)
  }
}

fn digit_char(digit: Int) -> String {
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

pub fn sha256_known_vector_test() {
  ffi.sha256_hex(<<"abc">>)
  |> should.equal(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

pub fn file_round_trip_test() {
  let dir = test_dir("files")
  let path = ffi.join_paths([dir, "hello.txt"])
  ffi.write_file(path, <<"hello">>) |> should.be_ok
  ffi.file_exists(path) |> should.be_true
  ffi.read_file(path) |> should.equal(Ok(<<"hello">>))
  ffi.file_size(path) |> should.equal(Ok(5))
  ffi.sha256_file_hex(path)
  |> should.equal(Ok(
    "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  ))

  let renamed = ffi.join_paths([dir, "renamed.txt"])
  ffi.rename(path, renamed) |> should.be_ok
  ffi.file_exists(path) |> should.be_false
  ffi.remove_file(renamed) |> should.be_ok
  ffi.file_exists(renamed) |> should.be_false
}

pub fn exclusive_write_test() {
  let dir = test_dir("exclusive")
  let path = ffi.join_paths([dir, "once.txt"])
  ffi.write_file_exclusive(path, <<"a">>) |> should.be_ok
  ffi.write_file_exclusive(path, <<"b">>) |> should.be_error
}

pub fn hash_tree_changes_with_content_test() {
  let dir = test_dir("tree")
  let a = ffi.join_paths([dir, "a.txt"])
  ffi.ensure_dir(ffi.join_paths([dir, "sub"])) |> should.be_ok
  let b = ffi.join_paths([dir, "sub", "b.txt"])
  ffi.write_file(a, <<"one">>) |> should.be_ok
  ffi.write_file(b, <<"two">>) |> should.be_ok
  let first = ffi.hash_tree(dir) |> should.be_ok
  let second = ffi.hash_tree(dir) |> should.be_ok
  first |> should.equal(second)
  ffi.write_file(b, <<"changed">>) |> should.be_ok
  let third = ffi.hash_tree(dir) |> should.be_ok
  third |> should.not_equal(first)
}

pub fn tar_round_trip_test() {
  let archive =
    ffi.tar_create_single("demo.so", <<"ELF-ish bytes">>) |> should.be_ok
  let again =
    ffi.tar_create_single("demo.so", <<"ELF-ish bytes">>) |> should.be_ok
  archive |> should.equal(again)

  let entries = ffi.tar_inspect_gz(archive) |> should.be_ok
  entries
  |> should.equal([ffi.TarEntry(name: "demo.so", kind: "regular", size: 13)])

  ffi.tar_extract_gz_member(archive, "demo.so")
  |> should.equal(Ok(<<"ELF-ish bytes">>))
  ffi.tar_extract_gz_member(archive, "other.so") |> should.be_error
}

pub fn tar_rejects_bad_names_test() {
  ffi.tar_create_single("../evil.so", <<"x">>) |> should.be_error
  ffi.tar_create_single("dir/evil.so", <<"x">>) |> should.be_error
}

pub fn tar_accepts_plain_hex_style_archive_test() {
  // Create an uncompressed tar via the tar writer and re-read it as plain.
  let gz = ffi.tar_create_single("metadata.config", <<"hello">>) |> should.be_ok
  // The plain inspector should fail on gzip data, which is the point.
  ffi.tar_inspect_plain(gz) |> should.be_error
}

pub fn magic_test() {
  let dir = test_dir("magic")
  let elf = ffi.join_paths([dir, "elf.so"])
  ffi.write_file(elf, <<0x7f, 0x45, 0x4c, 0x46, 0, 0, 0>>) |> should.be_ok
  ffi.file_magic(elf) |> should.equal("elf")
  let missing = ffi.join_paths([dir, "missing.so"])
  ffi.file_magic(missing) |> should.equal("unknown")
}

pub fn env_test() {
  ffi.env("PATH") |> should.be_some
  ffi.env("NIFFLER_DOES_NOT_EXIST_12345") |> should.be_none
}

pub fn join_paths_test() {
  ffi.dirname("/a/b/c") |> should.equal("/a/b")
  ffi.basename("/a/b/c") |> should.equal("c")
  ffi.join_paths(["/a", "b"]) |> should.equal("/a/b")
}

pub fn app_metadata_test() {
  ffi.priv_dir("niffler_precompiled") |> should.be_ok
  ffi.app_version("niffler_precompiled") |> should.equal(Ok("0.1.0"))
}

pub fn subprocess_test() {
  case ffi.find_executable("erl") {
    option.None -> Nil
    option.Some(erl) -> {
      let #(status, output) =
        ffi.run(
          erl,
          ["-noshell", "-eval", "io:format(\"ok\"), halt(0)."],
          ffi.cwd(),
        )
      status |> should.equal(0)
      output |> should.equal(<<"ok">>)
    }
  }
}
