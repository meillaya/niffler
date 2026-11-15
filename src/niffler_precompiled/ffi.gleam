//// Typed wrappers around the Erlang FFI module.

import gleam/option.{type Option}

pub type HttpResult {
  HttpOk(status: Int, body: BitArray)
  HttpError(reason: String)
}

pub type TarEntry {
  TarEntry(name: String, kind: String, size: Int)
}

// ---------------------------------------------------------------------------
// Platform facts

@external(erlang, "niffler_precompiled_ffi", "os_type")
pub fn os_type() -> #(String, String)

@external(erlang, "niffler_precompiled_ffi", "system_architecture")
pub fn system_architecture() -> String

@external(erlang, "niffler_precompiled_ffi", "nif_version")
pub fn nif_version() -> String

@external(erlang, "niffler_precompiled_ffi", "otp_release")
pub fn otp_release() -> String

@external(erlang, "niffler_precompiled_ffi", "wordsize")
pub fn wordsize() -> Int

// ---------------------------------------------------------------------------
// Environment and paths

@external(erlang, "niffler_precompiled_ffi", "env")
pub fn env(name: String) -> Option(String)

@external(erlang, "niffler_precompiled_ffi", "home_dir")
pub fn home_dir() -> String

@external(erlang, "niffler_precompiled_ffi", "user_cache_dir")
pub fn user_cache_dir(app: String) -> String

@external(erlang, "niffler_precompiled_ffi", "cwd")
pub fn cwd() -> String

@external(erlang, "niffler_precompiled_ffi", "path_separator")
pub fn path_separator() -> String

@external(erlang, "niffler_precompiled_ffi", "join_paths")
pub fn join_paths(parts: List(String)) -> String

@external(erlang, "niffler_precompiled_ffi", "dirname")
pub fn dirname(path: String) -> String

@external(erlang, "niffler_precompiled_ffi", "basename")
pub fn basename(path: String) -> String

@external(erlang, "niffler_precompiled_ffi", "absname")
pub fn absname(path: String) -> String

// ---------------------------------------------------------------------------
// Files

@external(erlang, "niffler_precompiled_ffi", "read_file")
pub fn read_file(path: String) -> Result(BitArray, String)

@external(erlang, "niffler_precompiled_ffi", "write_file")
pub fn write_file(path: String, contents: BitArray) -> Result(Nil, String)

@external(erlang, "niffler_precompiled_ffi", "write_file_exclusive")
pub fn write_file_exclusive(
  path: String,
  contents: BitArray,
) -> Result(Nil, String)

@external(erlang, "niffler_precompiled_ffi", "file_exists")
pub fn file_exists(path: String) -> Bool

@external(erlang, "niffler_precompiled_ffi", "file_size")
pub fn file_size(path: String) -> Result(Int, String)

@external(erlang, "niffler_precompiled_ffi", "ensure_dir")
pub fn ensure_dir(path: String) -> Result(Nil, String)

@external(erlang, "niffler_precompiled_ffi", "remove_file")
pub fn remove_file(path: String) -> Result(Nil, String)

@external(erlang, "niffler_precompiled_ffi", "rename")
pub fn rename(from: String, to: String) -> Result(Nil, String)

@external(erlang, "niffler_precompiled_ffi", "list_dir")
pub fn list_dir(path: String) -> Result(List(String), String)

@external(erlang, "niffler_precompiled_ffi", "set_file_mode")
pub fn set_file_mode(path: String, mode: Int) -> Result(Nil, String)

// ---------------------------------------------------------------------------
// Hashes

@external(erlang, "niffler_precompiled_ffi", "sha256_hex")
pub fn sha256_hex(contents: BitArray) -> String

@external(erlang, "niffler_precompiled_ffi", "sha256_file_hex")
pub fn sha256_file_hex(path: String) -> Result(String, String)

@external(erlang, "niffler_precompiled_ffi", "hash_tree")
pub fn hash_tree(directory: String) -> Result(String, String)

// ---------------------------------------------------------------------------
// OTP application metadata

@external(erlang, "niffler_precompiled_ffi", "priv_dir")
pub fn priv_dir(app: String) -> Result(String, String)

@external(erlang, "niffler_precompiled_ffi", "app_version")
pub fn app_version(app: String) -> Result(String, String)

@external(erlang, "niffler_precompiled_ffi", "file_magic")
pub fn file_magic(path: String) -> String

// ---------------------------------------------------------------------------
// HTTP(S)

@external(erlang, "niffler_precompiled_ffi", "http_get")
pub fn http_get(
  url: String,
  allow_insecure: Bool,
  ca_bundle: String,
) -> HttpResult

// ---------------------------------------------------------------------------
// Tar archives

@external(erlang, "niffler_precompiled_ffi", "tar_create_single")
pub fn tar_create_single(
  name: String,
  contents: BitArray,
) -> Result(BitArray, String)

@external(erlang, "niffler_precompiled_ffi", "tar_inspect_gz")
pub fn tar_inspect_gz(contents: BitArray) -> Result(List(TarEntry), String)

@external(erlang, "niffler_precompiled_ffi", "tar_extract_gz_member")
pub fn tar_extract_gz_member(
  contents: BitArray,
  name: String,
) -> Result(BitArray, String)

@external(erlang, "niffler_precompiled_ffi", "tar_inspect_plain")
pub fn tar_inspect_plain(contents: BitArray) -> Result(List(TarEntry), String)

@external(erlang, "niffler_precompiled_ffi", "tar_extract_plain_member")
pub fn tar_extract_plain_member(
  contents: BitArray,
  name: String,
) -> Result(BitArray, String)

// ---------------------------------------------------------------------------
// Subprocesses and VM helpers

@external(erlang, "niffler_precompiled_ffi", "run")
pub fn run(
  executable: String,
  arguments: List(String),
  cwd: String,
) -> #(Int, BitArray)

@external(erlang, "niffler_precompiled_ffi", "find_executable")
pub fn find_executable(name: String) -> Option(String)

@external(erlang, "niffler_precompiled_ffi", "sleep")
pub fn sleep(milliseconds: Int) -> Nil

@external(erlang, "niffler_precompiled_ffi", "halt_vm")
pub fn halt_vm(code: Int) -> Nil

@external(erlang, "niffler_precompiled_ffi", "plain_args")
pub fn plain_args() -> List(String)

@external(erlang, "niffler_precompiled_ffi", "unique_id")
pub fn unique_id() -> Int

@external(erlang, "niffler_precompiled_ffi", "timestamp")
pub fn timestamp() -> Int

@external(erlang, "niffler_precompiled_ffi", "remove_tree")
pub fn remove_tree(path: String) -> Result(Nil, String)

@external(erlang, "niffler_precompiled_ffi", "raise")
pub fn raise(package: String, message: String) -> Nil

@external(erlang, "niffler_precompiled_ffi", "print")
pub fn print(message: String) -> Nil

@external(erlang, "niffler_precompiled_ffi", "eprint")
pub fn eprint(message: String) -> Nil
