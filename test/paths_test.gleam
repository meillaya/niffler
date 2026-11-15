import gleam/option.{None, Some}
import gleeunit/should
import niffler_precompiled/paths

pub fn cache_override_test() {
  paths.cache_root(Some("/custom/cache"), "/home/user/.cache/niffler")
  |> should.equal("/custom/cache")
  paths.cache_root(Some(""), "/home/user/.cache/niffler")
  |> should.equal("/home/user/.cache/niffler")
  paths.cache_root(None, "/home/user/.cache/niffler")
  |> should.equal("/home/user/.cache/niffler")
}

pub fn artifact_paths_test() {
  paths.artifact_relative_path("abc", "so")
  |> should.equal("artifacts/abc.so")
  paths.artifact_filename("abc", "dll") |> should.equal("abc.dll")
}

pub fn split_path_list_test() {
  paths.split_path_list("/a:/b:", ":") |> should.equal(["/a", "/b"])
  paths.split_path_list("/a;/b", ";") |> should.equal(["/a", "/b"])
}

pub fn source_build_path_test() {
  paths.source_build_relative_path(
    "demo",
    "1.0.0",
    "x86_64-unknown-linux-gnu",
    "fingerprint",
    "libdemo.so",
  )
  |> should.equal(
    "build/demo/1.0.0/x86_64-unknown-linux-gnu/fingerprint/libdemo.so",
  )
}
