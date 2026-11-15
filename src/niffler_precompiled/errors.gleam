//// Runtime and CLI error values.

pub type NifflerError {
  ManifestMissing(String)
  ManifestInvalid(String)
  PackageMismatch(expected: String, actual: String)
  VersionMismatch(expected: String, actual: String)
  UnsupportedPlatform(String)
  UnsupportedNifVersion(target: String, required: String, runtime: String)
  OfflineMissing(String)
  HttpStatus(Int, String)
  HttpNetwork(String)
  TooLarge(Int, Int)
  ChecksumMismatch(expected: String, actual: String)
  ExtractInvalid(String)
  CacheWriteFailed(String)
  SourceMissing(String)
  CargoMissing
  CargoFailed(Int, String)
  LoadFailed(String)
}

pub fn message(error: NifflerError) -> String {
  case error {
    ManifestMissing(package) ->
      "niffler: no precompiled NIF manifest found for `"
      <> package
      <> "`. The package is missing priv/niffler.json; reinstall it or ask its maintainer to run `niffler manifest` before publishing."
    ManifestInvalid(reason) ->
      "niffler: the precompiled NIF manifest is invalid: " <> reason
    PackageMismatch(expected, actual) ->
      "niffler: manifest is for package `"
      <> actual
      <> "` but `"
      <> expected
      <> "` was requested. The installed package files are inconsistent."
    VersionMismatch(expected, actual) ->
      "niffler: manifest version `"
      <> actual
      <> "` does not match the installed package version `"
      <> expected
      <> "`. Run `niffler manifest` before publishing the package."
    UnsupportedPlatform(target) ->
      "niffler: no precompiled NIF is available for target `"
      <> target
      <> "`. Set NIFFLER_BUILD=1 to build from the bundled Rust source (requires cargo and Rust), or use niffler prefetch on a supported platform."
    UnsupportedNifVersion(target, required, runtime) ->
      "niffler: the `"
      <> target
      <> "` artifact requires NIF version "
      <> required
      <> " but this runtime supports "
      <> runtime
      <> ". Upgrade Erlang/OTP, or set NIFFLER_BUILD=1 to build from source."
    OfflineMissing(reason) ->
      "niffler: offline mode is enabled and the artifact is not available locally: "
      <> reason
      <> ". Run `niffler prefetch` (or set NIFFLER_ARTIFACT_DIR) before going offline."
    HttpStatus(status, url) ->
      "niffler: could not download the NIF artifact (HTTP "
      <> int_to_string(status)
      <> "): "
      <> url
    HttpNetwork(reason) ->
      "niffler: could not download the NIF artifact: " <> reason
    TooLarge(limit, actual) ->
      "niffler: the NIF artifact is too large ("
      <> int_to_string(actual)
      <> " bytes, limit "
      <> int_to_string(limit)
      <> " bytes)."
    ChecksumMismatch(expected, actual) ->
      "niffler: NIF artifact checksum mismatch (expected "
      <> expected
      <> ", got "
      <> actual
      <> "). The download was rejected and will not be loaded. Clear the cache entry with `niffler cache clean --all` and retry."
    ExtractInvalid(reason) ->
      "niffler: the NIF artifact is not a valid archive: " <> reason
    CacheWriteFailed(reason) ->
      "niffler: could not write to the NIF cache: " <> reason
    SourceMissing(path) ->
      "niffler: source fallback was requested but the bundled Rust crate is missing at "
      <> path
      <> ". Reinstall the package or ask its maintainer to publish priv/native/<crate>."
    CargoMissing ->
      "niffler: source fallback requires cargo on PATH but it was not found. Install Rust or use a package release with a precompiled artifact."
    CargoFailed(status, output) ->
      "niffler: cargo build failed (exit "
      <> int_to_string(status)
      <> "):\n"
      <> output
    LoadFailed(reason) -> "niffler: erlang:load_nif failed: " <> reason
  }
}

fn int_to_string(value: Int) -> String {
  case value {
    0 -> "0"
    _ -> do_int_to_string(value, "")
  }
}

fn do_int_to_string(value: Int, accumulator: String) -> String {
  case value / 10, value % 10 {
    0, digit -> digit_string(digit) <> accumulator
    quotient, digit ->
      do_int_to_string(quotient, digit_string(digit) <> accumulator)
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
