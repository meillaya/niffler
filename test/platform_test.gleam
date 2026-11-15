import gleam/option.{None, Some}
import gleeunit/should
import niffler_precompiled/platform

fn linux_facts(arch: String) -> platform.Facts {
  platform.Facts(
    system_architecture: arch,
    os_type: #("unix", "linux"),
    wordsize: 8,
    nif_version: "2.17",
    otp_release: "28",
  )
}

pub fn linux_gnu_target_test() {
  platform.current_target(
    linux_facts("x86_64-pc-linux-gnu"),
    platform.no_overrides(),
  )
  |> should.equal(Ok("x86_64-unknown-linux-gnu"))
}

pub fn linux_arm_target_test() {
  platform.current_target(
    linux_facts("aarch64-unknown-linux-gnu"),
    platform.no_overrides(),
  )
  |> should.equal(Ok("aarch64-unknown-linux-gnu"))
}

pub fn alpine_target_test() {
  platform.current_target(
    linux_facts("x86_64-alpine-linux-musl"),
    platform.no_overrides(),
  )
  |> should.equal(Ok("x86_64-unknown-linux-musl"))
}

pub fn darwin_kernel_suffix_test() {
  platform.current_target(
    platform.Facts(
      system_architecture: "aarch64-apple-darwin23.6.0",
      os_type: #("unix", "darwin"),
      wordsize: 8,
      nif_version: "2.17",
      otp_release: "28",
    ),
    platform.no_overrides(),
  )
  |> should.equal(Ok("aarch64-apple-darwin"))
}

pub fn darwin_intel_target_test() {
  platform.current_target(
    platform.Facts(
      system_architecture: "x86_64-apple-darwin23.6.0",
      os_type: #("unix", "darwin"),
      wordsize: 8,
      nif_version: "2.17",
      otp_release: "28",
    ),
    platform.no_overrides(),
  )
  |> should.equal(Ok("x86_64-apple-darwin"))
}

pub fn windows_target_test() {
  platform.current_target(
    platform.Facts(
      system_architecture: "win32",
      os_type: #("win32", "nt"),
      wordsize: 8,
      nif_version: "2.17",
      otp_release: "28",
    ),
    platform.no_overrides(),
  )
  |> should.equal(Ok("x86_64-pc-windows-msvc"))
}

pub fn unsupported_target_test() {
  platform.current_target(
    linux_facts("armv7-unknown-linux-gnueabihf"),
    platform.no_overrides(),
  )
  |> should.be_error
}

pub fn target_override_test() {
  let overrides =
    platform.EnvOverrides(
      target: Some("aarch64-unknown-linux-musl"),
      arch: None,
      vendor: None,
      os: None,
      abi: None,
    )
  platform.current_target(linux_facts("x86_64-pc-linux-gnu"), overrides)
  |> should.equal(Ok("aarch64-unknown-linux-musl"))
}

pub fn extension_test() {
  platform.extension("x86_64-unknown-linux-gnu") |> should.equal("so")
  platform.extension("aarch64-apple-darwin") |> should.equal("so")
  platform.extension("x86_64-pc-windows-msvc") |> should.equal("dll")
}

pub fn compatible_nif_version_selection_test() {
  platform.select_nif_version("2.17", ["2.15", "2.16", "2.18"])
  |> should.equal(Ok("2.16"))
  platform.select_nif_version("2.17", ["2.17"])
  |> should.equal(Ok("2.17"))
  platform.select_nif_version("2.17", ["2.18"])
  |> should.be_error
  platform.select_nif_version("2.16", ["2.15", "2.17"])
  |> should.equal(Ok("2.15"))
}

pub fn otp_requirement_test() {
  platform.otp_requirement("2.15") |> should.equal("OTP 22+")
  platform.otp_requirement("2.17") |> should.equal("OTP 26+")
  platform.otp_requirement("2.18") |> should.equal("OTP 29+")
}
