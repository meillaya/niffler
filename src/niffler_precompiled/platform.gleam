//// Platform detection and NIF version compatibility.
////
//// The normalization rules mirror what rustler_precompiled does for Elixir:
//// OTP reports a system architecture triple that is close to, but not always
//// equal to, a Rust target triple. Windows is the main special case ("win32"
//// for both 32- and 64-bit OTP), and macOS appends a kernel version to the OS
//// component.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order}
import gleam/string
import niffler_precompiled/checksum

pub const supported_targets = [
  "x86_64-unknown-linux-gnu",
  "aarch64-unknown-linux-gnu",
  "x86_64-unknown-linux-musl",
  "aarch64-unknown-linux-musl",
  "x86_64-apple-darwin",
  "aarch64-apple-darwin",
  "x86_64-pc-windows-msvc",
]

pub type Facts {
  Facts(
    system_architecture: String,
    os_type: #(String, String),
    wordsize: Int,
    nif_version: String,
    otp_release: String,
  )
}

pub type EnvOverrides {
  EnvOverrides(
    target: Option(String),
    arch: Option(String),
    vendor: Option(String),
    os: Option(String),
    abi: Option(String),
  )
}

pub fn no_overrides() -> EnvOverrides {
  EnvOverrides(None, None, None, None, None)
}

/// Detect the Rust target triple for the current platform.
pub fn current_target(
  facts: Facts,
  overrides: EnvOverrides,
) -> Result(String, String) {
  case overrides.target {
    Some(target) -> {
      case list.contains(supported_targets, target) {
        True -> Ok(target)
        False ->
          Error(
            "NIFFLER_TARGET is not a supported target: "
            <> target
            <> ". Supported: "
            <> string.join(supported_targets, ", "),
          )
      }
    }
    None -> {
      let #(os_kind, _os_name) = facts.os_type
      case os_kind {
        "win32" -> detect_windows(facts, overrides)
        "unix" -> detect_unix(facts, overrides)
        other ->
          Error("Unsupported operating system reported by OTP: " <> other)
      }
    }
  }
}

fn detect_windows(
  facts: Facts,
  overrides: EnvOverrides,
) -> Result(String, String) {
  let arch = case overrides.arch {
    Some(arch) -> normalize_arch(arch)
    None ->
      case facts.wordsize {
        8 -> "x86_64"
        4 -> "i686"
        _ -> "unknown"
      }
  }
  let vendor = option_or(overrides.vendor, "pc")
  let os = option_or(overrides.os, "windows")
  let abi = option_or(overrides.abi, "msvc")
  let target = string.join([arch, vendor, os, abi], "-")
  case list.contains(supported_targets, target) {
    True -> Ok(target)
    False ->
      Error(
        "Precompiled NIFs are not available for this Windows target: " <> target,
      )
  }
}

fn detect_unix(
  facts: Facts,
  overrides: EnvOverrides,
) -> Result(String, String) {
  let parts = string.split(facts.system_architecture, "-")
  let #(arch, vendor, os, abi) = case parts {
    [arch, vendor, os, abi] -> #(arch, vendor, os, Some(abi))
    [arch, vendor, os] -> #(arch, vendor, os, None)
    _ -> #(
      option_or(overrides.arch, "unknown"),
      option_or(overrides.vendor, "unknown"),
      option_or(overrides.os, "unknown"),
      overrides.abi,
    )
  }

  let arch = normalize_arch(option_or(overrides.arch, arch))
  let os = normalize_os(option_or(overrides.os, os))
  let vendor = normalize_vendor(option_or(overrides.vendor, vendor), os)
  let abi = case overrides.abi {
    Some(value) -> Some(value)
    None -> abi
  }

  let target = case abi {
    Some(abi) -> string.join([arch, vendor, os, abi], "-")
    None -> string.join([arch, vendor, os], "-")
  }

  case list.contains(supported_targets, target) {
    True -> Ok(target)
    False ->
      Error(
        "Precompiled NIFs are not available for this target: "
        <> target
        <> ". This runtime reported system_architecture="
        <> facts.system_architecture,
      )
  }
}

fn normalize_arch(arch: String) -> String {
  case arch {
    "amd64" -> "x86_64"
    "arm64" -> "aarch64"
    "arm" -> "aarch64"
    "riscv64" -> "riscv64gc"
    "i386" -> "i686"
    other -> other
  }
}

fn normalize_vendor(vendor: String, os: String) -> String {
  case os {
    "linux" ->
      case vendor {
        "pc" | "redhat" | "suse" | "alpine" -> "unknown"
        _ -> vendor
      }
    _ -> vendor
  }
}

fn normalize_os(os: String) -> String {
  case string.starts_with(os, "darwin") {
    True -> "darwin"
    False ->
      case string.starts_with(os, "linux") {
        True -> "linux"
        False -> os
      }
  }
}

fn option_or(option: Option(String), default: String) -> String {
  case option {
    Some(value) -> value
    None -> default
  }
}

/// File extension OTP appends to a NIF path on this target.
pub fn extension(target: String) -> String {
  case string.contains(target, "windows") {
    True -> "dll"
    False -> "so"
  }
}

/// The highest manifest NIF version that this runtime can load.
pub fn select_nif_version(
  runtime: String,
  available: List(String),
) -> Result(String, Nil) {
  case checksum.parse_nif_version(runtime) {
    Error(_) -> Error(Nil)
    Ok(#(major, minor)) -> {
      let compatible =
        available
        |> list.filter(fn(version) {
          case checksum.parse_nif_version(version) {
            Ok(#(available_major, available_minor)) ->
              available_major == major && available_minor <= minor
            Error(_) -> False
          }
        })
        |> list.sort(fn(a, b) { compare_nif_versions(a, b) })
      case list.last(compatible) {
        Ok(version) -> Ok(version)
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn compare_nif_versions(a: String, b: String) -> Order {
  case checksum.parse_nif_version(a), checksum.parse_nif_version(b) {
    Ok(#(a_major, a_minor)), Ok(#(b_major, b_minor)) -> {
      case a_major - b_major {
        0 ->
          case a_minor - b_minor {
            difference if difference < 0 -> order.Lt
            0 -> order.Eq
            _ -> order.Gt
          }
        difference if difference < 0 -> order.Lt
        _ -> order.Gt
      }
    }
    _, _ -> order.Eq
  }
}

/// Human-readable table used by the doctor command and error messages.
pub fn supported_nif_versions() -> List(String) {
  ["2.14", "2.15", "2.16", "2.17", "2.18"]
}

pub fn otp_requirement(nif_version: String) -> String {
  case checksum.parse_nif_version(nif_version) {
    Ok(#(2, 14)) -> "OTP 21+"
    Ok(#(2, 15)) -> "OTP 22+"
    Ok(#(2, 16)) -> "OTP 24+"
    Ok(#(2, 17)) -> "OTP 26+"
    Ok(#(2, 18)) -> "OTP 29+"
    _ -> "unknown OTP requirement"
  }
}

pub fn wordsize_to_arch(wordsize: Int) -> String {
  case wordsize {
    8 -> "x86_64"
    4 -> "i686"
    _ -> "unknown"
  }
}
