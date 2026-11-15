//// HTTP(S) download of artifacts with retries.

import gleam/option.{None, Some}
import niffler_precompiled/errors.{type NifflerError, HttpNetwork}
import niffler_precompiled/ffi

const max_attempts = 3

pub fn download(url: String) -> Result(BitArray, NifflerError) {
  let allow_insecure = flag("NIFFLER_ALLOW_INSECURE_URLS")
  let ca_bundle = case ffi.env("NIFFLER_CACERTS") {
    Some(path) -> path
    None -> ""
  }
  attempt(url, allow_insecure, ca_bundle, 1)
}

fn attempt(
  url: String,
  allow_insecure: Bool,
  ca_bundle: String,
  count: Int,
) -> Result(BitArray, NifflerError) {
  case ffi.http_get(url, allow_insecure, ca_bundle) {
    ffi.HttpOk(_status, body) -> Ok(body)
    ffi.HttpError(reason) -> {
      case count < max_attempts {
        True -> {
          let _ = ffi.sleep(250 * count)
          attempt(url, allow_insecure, ca_bundle, count + 1)
        }
        False -> Error(HttpNetwork(reason))
      }
    }
  }
}

pub fn flag(name: String) -> Bool {
  case ffi.env(name) {
    Some(value) -> value == "1" || value == "true"
    None -> False
  }
}

pub fn env_or_empty(name: String) -> String {
  case ffi.env(name) {
    Some(value) -> value
    None -> ""
  }
}
