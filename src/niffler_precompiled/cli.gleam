//// Command line interface for niffler.
////
//// Invoke with `gleam run -m niffler_precompiled -- <command>` or with the
//// standalone escript.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import niffler_precompiled/cache
import niffler_precompiled/config as nif_config
import niffler_precompiled/errors
import niffler_precompiled/fetch
import niffler_precompiled/ffi
import niffler_precompiled/loader_template
import niffler_precompiled/manifest
import niffler_precompiled/paths
import niffler_precompiled/platform
import niffler_precompiled/project
import niffler_precompiled/workflow_template

pub fn main() {
  let arguments = ffi.plain_args()
  run(arguments)
}

/// Entry point used by the escript, where arguments arrive as a list rather
/// than through `init:get_plain_arguments/0`.
pub fn main_with_args(arguments: List(String)) -> Nil {
  run(arguments)
}

fn run(arguments: List(String)) -> Nil {
  case arguments {
    [] -> print_help()
    ["--help"] | ["-h"] | ["help"] -> print_help()
    ["--version"] | ["-V"] | ["version"] -> println("niffler " <> version())
    [command, ..rest] ->
      case command {
        "init" -> command_init(rest)
        "generate" -> command_generate(rest)
        "build" -> command_build(rest)
        "package" -> command_package(rest)
        "manifest" -> command_manifest(rest)
        "verify" -> command_verify(rest)
        "prefetch" -> command_prefetch(rest)
        "doctor" -> command_doctor(rest)
        "cache" -> command_cache(rest)
        "smoke" -> command_smoke(rest)
        "hex" -> command_hex(rest)
        other -> usage_error("unknown command `" <> other <> "`")
      }
  }
}

fn version() -> String {
  "0.1.0"
}

// ---------------------------------------------------------------------------
// Argument parsing

type Options {
  Options(
    values: List(#(String, String)),
    switches: List(String),
    positional: List(String),
  )
}

fn empty_options() -> Options {
  Options([], [], [])
}

fn parse_options(
  arguments: List(String),
  value_flags: List(String),
) -> Result(Options, String) {
  parse_options_loop(arguments, value_flags, empty_options())
}

fn parse_options_loop(
  arguments: List(String),
  value_flags: List(String),
  options: Options,
) -> Result(Options, String) {
  case arguments {
    [] -> Ok(options)
    [argument, ..rest] -> {
      case string.starts_with(argument, "--") {
        True -> {
          let name = string.drop_start(argument, 2)
          case string.split(name, "=") {
            [name, value] ->
              parse_options_loop(
                rest,
                value_flags,
                Options(
                  [#(name, value), ..options.values],
                  options.switches,
                  options.positional,
                ),
              )
            _ ->
              case list.contains(value_flags, name) {
                True ->
                  case rest {
                    [value, ..remaining] ->
                      parse_options_loop(
                        remaining,
                        value_flags,
                        Options(
                          [#(name, value), ..options.values],
                          options.switches,
                          options.positional,
                        ),
                      )
                    [] -> Error("flag --" <> name <> " needs a value")
                  }
                False ->
                  parse_options_loop(
                    rest,
                    value_flags,
                    Options(
                      options.values,
                      [name, ..options.switches],
                      options.positional,
                    ),
                  )
              }
          }
        }
        False -> {
          case string.starts_with(argument, "-") {
            True ->
              parse_options_loop(
                rest,
                value_flags,
                Options(
                  options.values,
                  [string.drop_start(argument, 1), ..options.switches],
                  [argument, ..options.positional],
                ),
              )
            False ->
              parse_options_loop(
                rest,
                value_flags,
                Options(options.values, options.switches, [
                  argument,
                  ..options.positional
                ]),
              )
          }
        }
      }
    }
  }
}

fn value(options: Options, name: String) -> Option(String) {
  case list.find(options.values, fn(entry) { entry.0 == name }) {
    Ok(entry) -> Some(entry.1)
    Error(_) -> None
  }
}

fn values(options: Options, name: String) -> List(String) {
  options.values
  |> list.filter(fn(entry) { entry.0 == name })
  |> list.map(fn(entry) { entry.1 })
}

fn switch(options: Options, name: String) -> Bool {
  list.contains(options.switches, name)
}

fn require_value(
  options: Options,
  name: String,
  command: String,
) -> Result(String, String) {
  case value(options, name) {
    Some(found) -> Ok(found)
    None -> Error("`" <> command <> "` requires --" <> name)
  }
}

fn split_commas(value: String) -> List(String) {
  value
  |> string.split(",")
  |> list.map(string.trim)
  |> list.filter(fn(part) { part != "" })
}

// ---------------------------------------------------------------------------
// Output and exit helpers

fn println(message: String) -> Nil {
  ffi.print(message <> "\n")
}

fn eprintln(message: String) -> Nil {
  ffi.eprint(message <> "\n")
}

fn unwrap(result: Result(a, String)) -> a {
  case result {
    Ok(value) -> value
    Error(error) -> {
      fail(error)
      panic as "unreachable"
    }
  }
}

fn fail(message: String) -> Nil {
  eprintln("niffler: " <> message)
  ffi.halt_vm(1)
}

fn usage_error(message: String) -> Nil {
  eprintln("niffler: " <> message)
  eprintln("")
  print_help()
  ffi.halt_vm(2)
}

fn print_help() -> Nil {
  println(
    "niffler "
    <> version()
    <> " - precompiled Rust NIF distribution for Gleam\n"
    <> "\n"
    <> "Usage: niffler <command> [options]\n"
    <> "\n"
    <> "Commands:\n"
    <> "  init       Scaffold niffler.toml, a Rust crate, a loader, and the release workflow\n"
    <> "  generate   Regenerate the Erlang loader and release workflow\n"
    <> "  build      Build (and package) a NIF artifact for one or more targets\n"
    <> "  package    Package an existing .so/.dylib/.dll into a release tarball\n"
    <> "  manifest   Generate or check priv/niffler.json from dist artifacts\n"
    <> "  verify     Verify local or remote artifacts against the manifest\n"
    <> "  prefetch   Download and verify artifacts into the cache or an artifact dir\n"
    <> "  doctor     Print environment, manifest, and configuration diagnostics\n"
    <> "  cache      Inspect or clean the NIF cache (path|list|clean)\n"
    <> "  smoke      Load a built artifact in a temporary Erlang VM\n"
    <> "  hex        Validate and emit a Hex package (check|emit)\n"
    <> "\n"
    <> "Global options: --help, --version\n"
    <> "Exit codes: 0 success, 1 failure, 2 usage error",
  )
}

// ---------------------------------------------------------------------------
// init

fn command_init(arguments: List(String)) -> Nil {
  let options =
    unwrap(
      parse_options(arguments, [
        "repo",
        "crate",
        "module",
        "functions",
        "targets",
      ]),
    )
  let root = project_root()
  let package =
    unwrap(project.package_info(root) |> result.map_error(fn(error) { error }))
  let package =
    unwrap(case package.target == "erlang" {
      True -> Ok(package)
      False ->
        Error(
          "niffler packages must target Erlang; set `target = \"erlang\"` in gleam.toml (found `"
          <> package.target
          <> "`)",
        )
    })
  let repo = unwrap(require_value(options, "repo", "init"))
  let crate = option_default(value(options, "crate"), package.name <> "_nif")
  let module = option_default(value(options, "module"), crate)
  let functions_text = value(options, "functions")
  let functions = case functions_text {
    Some(text) -> split_commas(text)
    None ->
      case switch(options, "no-example") {
        True -> []
        False -> ["add/2"]
      }
  }
  let targets = case value(options, "targets") {
    Some(text) -> split_commas(text)
    None -> nif_config.default_targets()
  }
  let config_text = render_config(module, crate, functions, repo, targets)
  let decoded = unwrap(nif_config.decode(config_text))
  let _ = decoded
  let version = package.version
  let base_url =
    "https://github.com/" <> repo <> "/releases/download/v" <> version
  let manifest_text =
    manifest.encode(manifest.empty(
      package.name,
      version,
      module,
      crate,
      base_url,
    ))
  let loader =
    loader_template.render(package.name, module, parse_functions(functions))
  let source = ffi.join_paths([root, "priv", "native", crate])
  let workflow = workflow_template.render(decoded, package)

  let files = [
    #(ffi.join_paths([root, "niffler.toml"]), config_text),
    #(ffi.join_paths([root, "priv", "niffler.json"]), manifest_text),
    #(loader_path(root, module), loader),
    #(ffi.join_paths([source, "Cargo.toml"]), cargo_toml(crate, version)),
    #(ffi.join_paths([source, "src", "lib.rs"]), rust_example(module)),
    #(ffi.join_paths([source, ".cargo", "config.toml"]), cargo_config()),
    #(ffi.join_paths([source, "README.md"]), crate_readme(crate, module)),
    #(ffi.join_paths([root, "rust-toolchain.toml"]), toolchain()),
    #(
      ffi.join_paths([root, ".github", "workflows", "niffler-release.yml"]),
      workflow,
    ),
  ]

  let existing =
    files
    |> list.filter(fn(file) { ffi.file_exists(file.0) })
    |> list.map(fn(file) { file.0 })
  case existing, switch(options, "force") {
    [], _ -> Nil
    _, True -> Nil
    _, False ->
      fail(
        "refusing to overwrite existing files (use --force):\n  "
        <> string.join(existing, "\n  "),
      )
  }

  case switch(options, "dry-run") {
    True -> {
      println("would write:")
      list.each(files, fn(file) { println("  " <> file.0) })
    }
    False -> {
      let _ = unwrap(write_all(files))
      append_gitignore(root)
      let _ = generate_lockfile(root, source, crate)
      println("Created niffler project files.")
      println("")
      println("Next steps:")
      println("  1. Add Gleam externals calling `" <> module <> "` functions.")
      println(
        "  2. Replace the example NIF in priv/native/"
        <> crate
        <> "/src/lib.rs.",
      )
      println("  3. Run: niffler doctor")
      println("  4. Run: NIFFLER_BUILD=1 gleam test")
      println("  5. Tag a release to run the generated workflow.")
    }
  }
}

fn write_all(files: List(#(String, String))) -> Result(Nil, String) {
  case files {
    [] -> Ok(Nil)
    [file, ..rest] -> {
      let _ =
        unwrap(
          project.write_text_file(file.0, file.1)
          |> result.map_error(fn(error) { error }),
        )
      write_all(rest)
    }
  }
}

fn option_default(option: Option(String), default: String) -> String {
  case option {
    Some(value) -> value
    None -> default
  }
}

fn parse_functions(functions: List(String)) -> List(nif_config.Function) {
  functions
  |> list.filter_map(fn(text) {
    case string.split(text, "/") {
      [name, arity] ->
        case int.parse(arity) {
          Ok(arity) -> Ok(nif_config.Function(name, arity))
          Error(_) -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

fn render_config(
  module: String,
  crate: String,
  functions: List(String),
  repo: String,
  targets: List(String),
) -> String {
  let function_list =
    "["
    <> string.join(
      list.map(functions, fn(value) { "\"" <> value <> "\"" }),
      ", ",
    )
    <> "]"
  let target_list =
    "[\n"
    <> string.join(
      list.map(targets, fn(target) { "  \"" <> target <> "\"," }),
      "\n",
    )
    <> "\n]"
  "[nif]\n"
  <> "module = \""
  <> module
  <> "\"\n"
  <> "crate = \""
  <> crate
  <> "\"\n"
  <> "functions = "
  <> function_list
  <> "\n"
  <> "\n"
  <> "[release]\n"
  <> "repo = \""
  <> repo
  <> "\"\n"
  <> "targets = "
  <> target_list
  <> "\n"
}

fn cargo_toml(crate: String, version: String) -> String {
  "[package]\n"
  <> "name = \""
  <> crate
  <> "\"\n"
  <> "version = \""
  <> version
  <> "\"\n"
  <> "edition = \"2021\"\n"
  <> "\n"
  <> "[lib]\n"
  <> "crate-type = [\"cdylib\"]\n"
  <> "\n"
  <> "[dependencies]\n"
  <> "rustler = \"0.39\"\n"
  <> "\n"
  <> "[profile.release]\n"
  <> "lto = true\n"
}

fn rust_example(module: String) -> String {
  "use rustler::nif;\n"
  <> "\n"
  <> "// Replace this example with the NIFs your package exposes.\n"
  <> "#[nif]\n"
  <> "fn add(a: i64, b: i64) -> i64 {\n"
  <> "    a + b\n"
  <> "}\n"
  <> "\n"
  <> "// The module name must equal the generated Erlang loader module.\n"
  <> "rustler::init!(\""
  <> module
  <> "\");\n"
}

fn cargo_config() -> String {
  "[target.x86_64-unknown-linux-musl]\n"
  <> "rustflags = [\"-C\", \"target-feature=-crt-static\"]\n"
  <> "\n"
  <> "[target.aarch64-unknown-linux-musl]\n"
  <> "rustflags = [\"-C\", \"target-feature=-crt-static\"]\n"
}

fn crate_readme(crate: String, module: String) -> String {
  "# "
  <> crate
  <> "\n\nRust NIF crate for the `"
  <> module
  <> "` Erlang loader module.\n\nBuild artifacts with `niffler build`; the NIF entry name must be\n`"
  <> module
  <> "`.\n"
}

fn toolchain() -> String {
  "[toolchain]\nchannel = \"1.99.0\"\ncomponents = [\"rustfmt\", \"clippy\"]\n"
}

fn append_gitignore(root: String) -> Nil {
  let path = ffi.join_paths([root, ".gitignore"])
  let existing = case project.read_text(path) {
    Ok(text) -> text
    Error(_) -> ""
  }
  let additions = ["/dist/", "priv/native/*/target", "niffler.escript"]
  let missing =
    additions
    |> list.filter(fn(entry) { !string.contains(existing, entry) })
  case missing {
    [] -> Nil
    _ -> {
      let separator = case string.ends_with(existing, "\n") || existing == "" {
        True -> ""
        False -> "\n"
      }
      let _ =
        project.write_text_file(
          path,
          existing <> separator <> string.join(missing, "\n") <> "\n",
        )
      Nil
    }
  }
}

fn generate_lockfile(
  root: String,
  source: String,
  crate: String,
) -> Result(Nil, String) {
  let _ = root
  let _ = crate
  case ffi.find_executable("cargo") {
    None -> Ok(Nil)
    Some(cargo) -> {
      let #(status, output) =
        ffi.run(
          cargo,
          [
            "generate-lockfile",
            "--manifest-path",
            ffi.join_paths([source, "Cargo.toml"]),
          ],
          source,
        )
      case status {
        0 -> Ok(Nil)
        _ -> {
          eprintln(
            "niffler: warning: could not generate Cargo.lock; run `cargo generate-lockfile` in "
            <> source
            <> "\n"
            <> project.output_string(output),
          )
          Ok(Nil)
        }
      }
    }
  }
}

fn loader_path(root: String, module: String) -> String {
  project.loader_path(root, module)
}

// ---------------------------------------------------------------------------
// generate

fn command_generate(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, []))
  let root = project_root()
  let package = unwrap(project.package_info(root))
  let root_config = unwrap(project.read_config(root))
  let expected_loader =
    loader_template.render(
      package.name,
      root_config.module,
      root_config.functions,
    )
  let expected_workflow = workflow_template.render(root_config, package)
  let loader_file = project.loader_path(root, root_config.module)
  let workflow_file =
    ffi.join_paths([root, ".github", "workflows", "niffler-release.yml"])
  let mismatches =
    [
      #(loader_file, expected_loader),
      #(workflow_file, expected_workflow),
    ]
    |> list.filter(fn(pair) {
      case project.read_text(pair.0) {
        Ok(current) -> current != pair.1
        Error(_) -> True
      }
    })
    |> list.map(fn(pair) { pair.0 })

  case switch(options, "check") {
    True ->
      case mismatches {
        [] -> println("generated files are up to date")
        _ ->
          fail(
            "generated files are stale (run `niffler generate`):\n  "
            <> string.join(mismatches, "\n  "),
          )
      }
    False -> {
      let _ =
        unwrap(
          write_all([
            #(loader_file, expected_loader),
            #(workflow_file, expected_workflow),
          ]),
        )
      println("generated:")
      println("  " <> loader_file)
      println("  " <> workflow_file)
    }
  }
}

// ---------------------------------------------------------------------------
// package

fn command_package(arguments: List(String)) -> Nil {
  let options =
    unwrap(
      parse_options(arguments, ["target", "binary", "nif-version", "dist"]),
    )
  let root = project_root()
  let package = unwrap(project.package_info(root))
  let root_config = unwrap(project.read_config(root))
  let target =
    option_default(
      value(options, "target"),
      host_target() |> option_default_result("x86_64-unknown-linux-gnu"),
    )
  let nif_version =
    option_default(
      value(options, "nif-version"),
      option_default(root_config.nif_version, "2.15"),
    )
  let dist =
    option_default(value(options, "dist"), ffi.join_paths([root, "dist"]))
  let binary = case value(options, "binary") {
    Some(path) -> Ok(ffi.absname(path))
    None -> find_built_binary(root, root_config.crate, target)
  }
  let binary = unwrap(binary)
  let artifact =
    unwrap(package_artifact(
      root_config.crate,
      package.version,
      nif_version,
      target,
      binary,
      dist,
    ))
  println("packaged " <> artifact.0)
  println("  sha256 (asset): " <> artifact.1)
  println("  sha256 (nif):   " <> artifact.2)
}

fn package_artifact(
  crate: String,
  package_version: String,
  nif_version: String,
  target: String,
  binary: String,
  dist: String,
) -> Result(#(String, String, String), String) {
  let contents =
    unwrap(
      ffi.read_file(binary)
      |> result.map_error(fn(error) {
        "could not read binary " <> binary <> ": " <> error
      }),
    )
  let extension = platform.extension(target)
  let inner_name = crate <> "." <> extension
  let tarball =
    unwrap(
      ffi.tar_create_single(inner_name, contents)
      |> result.map_error(fn(error) { "could not package artifact: " <> error }),
    )
  let filename =
    project.artifact_filename(crate, package_version, nif_version, target)
  let path = ffi.join_paths([dist, filename])
  let _ = unwrap(ffi.ensure_dir(dist) |> result.map_error(fn(error) { error }))
  let _ =
    unwrap(
      ffi.write_file(path, tarball) |> result.map_error(fn(error) { error }),
    )
  let asset_sha = ffi.sha256_hex(tarball)
  let nif_sha = ffi.sha256_hex(contents)
  Ok(#(path, asset_sha, nif_sha))
}

fn find_built_binary(
  root: String,
  crate: String,
  target: String,
) -> Result(String, String) {
  let extension = platform.extension(target)
  let names = case extension {
    "dll" -> [crate <> ".dll"]
    _ -> ["lib" <> crate <> ".so", "lib" <> crate <> ".dylib"]
  }
  let directories = [
    ffi.join_paths([root, "dist", "target", target, "release"]),
    ffi.join_paths([root, "dist", "target", "release"]),
    ffi.join_paths([root, "target", target, "release"]),
    ffi.join_paths([root, "target", "release"]),
  ]
  let found =
    list.find_map(directories, fn(directory) {
      list.find_map(names, fn(name) {
        let path = ffi.join_paths([directory, name])
        case ffi.file_exists(path) {
          True -> Ok(path)
          False -> Error(Nil)
        }
      })
    })
  case found {
    Ok(path) -> Ok(path)
    Error(_) ->
      Error(
        "could not find a built NIF for "
        <> target
        <> "; looked in:\n  "
        <> string.join(directories, "\n  "),
      )
  }
}

fn host_target() -> Option(String) {
  let facts =
    platform.Facts(
      system_architecture: ffi.system_architecture(),
      os_type: ffi.os_type(),
      wordsize: ffi.wordsize(),
      nif_version: ffi.nif_version(),
      otp_release: ffi.otp_release(),
    )
  case platform.current_target(facts, platform.no_overrides()) {
    Ok(target) -> Some(target)
    Error(_) -> None
  }
}

fn option_default_result(option: Option(String), default: String) -> String {
  case option {
    Some(value) -> value
    None -> default
  }
}

// ---------------------------------------------------------------------------
// build

fn command_build(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, ["target", "dist"]))
  let root = project_root()
  let package = unwrap(project.package_info(root))
  let root_config = unwrap(project.read_config(root))
  let targets = case values(options, "target") {
    [] -> [option_default_result(host_target(), "x86_64-unknown-linux-gnu")]
    found -> found
  }
  let dist =
    option_default(value(options, "dist"), ffi.join_paths([root, "dist"]))
  let use_cross = switch(options, "use-cross")
  let no_smoke = switch(options, "no-smoke")
  let host = host_target()
  list.each(targets, fn(target) {
    case build_target(root, root_config, package, target, dist, use_cross) {
      Error(error) -> fail(error)
      Ok(#(path, _asset_sha, _nif_sha)) -> {
        println("built " <> path)
        let should_smoke = !no_smoke && host == Some(target)
        case should_smoke {
          True ->
            smoke_artifact(
              root,
              path,
              root_config.module,
              root_config.functions,
            )
          False -> Nil
        }
      }
    }
  })
}

fn build_target(
  root: String,
  root_config: nif_config.Config,
  package: project.PackageInfo,
  target: String,
  dist: String,
  use_cross: Bool,
) -> Result(#(String, String, String), String) {
  let _ =
    unwrap(case list.contains(platform.supported_targets, target) {
      True -> Ok(Nil)
      False -> Error("unsupported target `" <> target <> "`")
    })
  let executable = case use_cross {
    True ->
      case ffi.find_executable("cross") {
        Some(path) -> path
        None -> ""
      }
    False ->
      case ffi.find_executable("cargo") {
        Some(path) -> path
        None -> ""
      }
  }
  let _ =
    unwrap(case executable {
      "" ->
        Error(
          "could not find "
          <> case use_cross {
            True -> "cross"
            False -> "cargo"
          }
          <> " on PATH",
        )
      _ -> Ok(Nil)
    })
  let source = project.source_directory(root, root_config)
  let target_directory = ffi.join_paths([root, "dist", "target"])
  let arguments = [
    "build",
    "--release",
    "--locked",
    "--target",
    target,
    "--manifest-path",
    ffi.join_paths([source, "Cargo.toml"]),
    "--target-dir",
    target_directory,
  ]
  let #(status, output) = ffi.run(executable, arguments, source)
  case status {
    0 -> {
      let release = ffi.join_paths([target_directory, target, "release"])
      let extension = platform.extension(target)
      let names = case extension {
        "dll" -> [root_config.crate <> ".dll"]
        _ -> [
          "lib" <> root_config.crate <> ".so",
          "lib" <> root_config.crate <> ".dylib",
        ]
      }
      let built =
        list.find_map(names, fn(name) {
          let path = ffi.join_paths([release, name])
          case ffi.file_exists(path) {
            True -> Ok(path)
            False -> Error(Nil)
          }
        })
      case built {
        Error(_) -> Error("cargo succeeded but no NIF was found in " <> release)
        Ok(binary) -> {
          let nif_version =
            unwrap(detect_nif_version(executable, source, root_config))
          package_artifact(
            root_config.crate,
            package.version,
            nif_version,
            target,
            binary,
            dist,
          )
        }
      }
    }
    _ ->
      Error(
        "build failed for " <> target <> ":\n" <> project.output_string(output),
      )
  }
}

fn detect_nif_version(
  cargo: String,
  source: String,
  root_config: nif_config.Config,
) -> Result(String, String) {
  let #(status, output) =
    ffi.run(
      cargo,
      [
        "tree",
        "-e",
        "features",
        "-i",
        "rustler",
        "--prefix",
        "none",
        "-f",
        "{p};{f}",
      ],
      source,
    )
  case status == 0 {
    False -> Ok(option_default(root_config.nif_version, "2.15"))
    True -> {
      let text = project.output_string(output)
      let detected =
        text
        |> string.split("\n")
        |> list.flat_map(fn(part) { string.split(part, ";") })
        |> list.filter(fn(part) { string.starts_with(part, "nif_version_2_") })
        |> list.map(fn(part) { string.replace(part, "nif_version_", "") })
        |> list.map(fn(part) { string.replace(part, "_", ".") })
        |> list.sort(fn(a, b) { string.compare(b, a) })
        |> list.first
      case detected {
        Ok(version) -> Ok(version)
        Error(_) -> Ok(option_default(root_config.nif_version, "2.15"))
      }
    }
  }
}

fn smoke_artifact(
  root: String,
  artifact_path: String,
  module: String,
  functions: List(nif_config.Function),
) -> Nil {
  case run_smoke(root, artifact_path, module, functions) {
    Ok(_) -> println("smoke: loaded " <> module <> " successfully")
    Error(error) -> fail("smoke test failed: " <> error)
  }
}

// ---------------------------------------------------------------------------
// manifest

fn command_manifest(arguments: List(String)) -> Nil {
  let options =
    unwrap(parse_options(arguments, ["dist", "base-url", "version"]))
  let root = project_root()
  let package = unwrap(project.package_info(root))
  let root_config = unwrap(project.read_config(root))
  let dist =
    option_default(value(options, "dist"), ffi.join_paths([root, "dist"]))
  let version = option_default(value(options, "version"), package.version)
  let base_url =
    option_default(
      value(options, "base-url"),
      project.base_url(root_config, package, version),
    )
  let artifacts = unwrap(collect_artifacts(root_config, package, dist))
  let missing_targets =
    root_config.targets
    |> list.filter(fn(target) {
      !list.any(artifacts, fn(artifact) { artifact.target == target })
    })
  case missing_targets {
    [] -> Nil
    _ ->
      fail(
        "missing artifacts for targets: "
        <> string.join(missing_targets, ", ")
        <> " (run `niffler build` for each target, or pass --dist with all artifacts)",
      )
  }
  let source_path = case string.starts_with(root_config.path, "priv/") {
    True -> string.drop_start(root_config.path, 5)
    False -> root_config.path
  }
  let manifest_value =
    manifest.Manifest(
      package: package.name,
      version: version,
      nif_module: root_config.module,
      crate: root_config.crate,
      source_path: source_path,
      base_url: base_url,
      artifacts: artifacts,
    )
  case
    manifest.validate(
      manifest_value,
      manifest.ValidateOptions(
        allow_insecure_base_url: switch(options, "allow-insecure"),
        require_artifacts: True,
      ),
    )
  {
    Error(error) -> fail("invalid manifest: " <> error)
    Ok(_) -> Nil
  }
  let encoded = manifest.encode(manifest_value)
  case switch(options, "json") {
    True -> ffi.print(encoded)
    False -> {
      let path = ffi.join_paths([root, "priv", "niffler.json"])
      case switch(options, "check") {
        True ->
          case project.read_text(path) {
            Ok(current) ->
              case current == encoded {
                True -> println("manifest is up to date")
                False ->
                  fail(
                    "priv/niffler.json is stale; run `niffler manifest --write`",
                  )
              }
            Error(_) ->
              fail(
                "priv/niffler.json is missing; run `niffler manifest --write`",
              )
          }
        False -> {
          let _ =
            unwrap(
              project.write_text_file(path, encoded)
              |> result.map_error(fn(error) { error }),
            )
          println("wrote " <> path)
          println(
            "  "
            <> int_string(list.length(artifacts))
            <> " artifacts, base_url "
            <> base_url,
          )
        }
      }
    }
  }
}

fn collect_artifacts(
  root_config: nif_config.Config,
  package: project.PackageInfo,
  dist: String,
) -> Result(List(manifest.Artifact), String) {
  use names <- result.try(
    ffi.list_dir(dist)
    |> result.map_error(fn(_) { "dist directory does not exist: " <> dist }),
  )
  collect_artifacts_loop(names, root_config, package, dist, [])
}

fn collect_artifacts_loop(
  names: List(String),
  root_config: nif_config.Config,
  package: project.PackageInfo,
  dist: String,
  accumulator: List(manifest.Artifact),
) -> Result(List(manifest.Artifact), String) {
  case names {
    [] -> Ok(list.reverse(accumulator))
    [name, ..rest] ->
      case project.parse_artifact_filename(root_config.crate, name) {
        None ->
          collect_artifacts_loop(rest, root_config, package, dist, accumulator)
        Some(#(version, nif_version, target)) ->
          case list.contains(root_config.targets, target) {
            False ->
              collect_artifacts_loop(
                rest,
                root_config,
                package,
                dist,
                accumulator,
              )
            True ->
              case version == package.version {
                False ->
                  Error(
                    "artifact "
                    <> name
                    <> " has version "
                    <> version
                    <> " but gleam.toml says "
                    <> package.version,
                  )
                True ->
                  case
                    artifact_hashes(
                      root_config.crate,
                      target,
                      ffi.join_paths([dist, name]),
                    )
                  {
                    Error(error) -> Error(error)
                    Ok(#(sha256, size)) ->
                      collect_artifacts_loop(rest, root_config, package, dist, [
                        manifest.Artifact(
                          target: target,
                          nif_version: nif_version,
                          file: name,
                          sha256: sha256,
                          size: size,
                        ),
                        ..accumulator
                      ])
                  }
              }
          }
      }
  }
}

fn artifact_hashes(
  crate: String,
  target: String,
  path: String,
) -> Result(#(String, Int), String) {
  let tarball =
    unwrap(ffi.read_file(path) |> result.map_error(fn(error) { error }))
  let expected = crate <> "." <> platform.extension(target)
  let entries =
    unwrap(ffi.tar_inspect_gz(tarball) |> result.map_error(fn(error) { error }))
  case entries {
    [entry] if entry.name == expected && entry.kind == "regular" -> {
      let contents =
        unwrap(
          ffi.tar_extract_gz_member(tarball, expected)
          |> result.map_error(fn(error) { error }),
        )
      Ok(#(ffi.sha256_hex(contents), bit_array.byte_size(contents)))
    }
    _ ->
      Error(
        "artifact "
        <> path
        <> " must contain exactly one regular file named "
        <> expected,
      )
  }
}

// ---------------------------------------------------------------------------
// verify

fn command_verify(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, ["manifest", "dist"]))
  let root = project_root()
  let manifest_path =
    option_default(value(options, "manifest"), project.manifest_path(root))
  let manifest_value = unwrap(project.read_manifest_file(manifest_path))
  let dist =
    Some(option_default(value(options, "dist"), ffi.join_paths([root, "dist"])))
  let online = switch(options, "online")
  let failures =
    manifest_value.artifacts
    |> list.filter(fn(artifact) {
      let result = verify_artifact(manifest_value, artifact, dist, online)
      case result {
        Ok(_) -> False
        Error(error) -> {
          eprintln("FAIL " <> artifact.file <> ": " <> error)
          True
        }
      }
    })
  case list.length(failures) {
    0 ->
      println(
        "verified "
        <> int_string(list.length(manifest_value.artifacts))
        <> " artifacts",
      )
    count -> fail(int_string(count) <> " artifact(s) failed verification")
  }
}

fn verify_artifact(
  manifest_value: manifest.Manifest,
  artifact: manifest.Artifact,
  dist: Option(String),
  online: Bool,
) -> Result(Nil, String) {
  let expected =
    manifest_value.crate <> "." <> platform.extension(artifact.target)
  let tarball = case dist {
    Some(dist) -> {
      let path = ffi.join_paths([dist, artifact.file])
      case ffi.read_file(path) {
        Ok(contents) -> Ok(contents)
        Error(_) -> Error("missing " <> path)
      }
    }
    None -> Error("")
  }
  case tarball {
    Ok(contents) -> verify_tarball(contents, expected, artifact)
    Error(_) if online -> {
      let body =
        unwrap(
          fetch.download(manifest.artifact_url(manifest_value, artifact))
          |> result.map_error(fn(error) { errors.message(error) }),
        )
      verify_tarball(body, expected, artifact)
    }
    Error(error) -> Error(error)
  }
}

fn verify_tarball(
  contents: BitArray,
  expected: String,
  artifact: manifest.Artifact,
) -> Result(Nil, String) {
  let entries =
    unwrap(
      ffi.tar_inspect_gz(contents) |> result.map_error(fn(error) { error }),
    )
  case entries {
    [entry] if entry.name == expected -> {
      let inner =
        unwrap(
          ffi.tar_extract_gz_member(contents, expected)
          |> result.map_error(fn(error) { error }),
        )
      let actual_sha = ffi.sha256_hex(inner)
      let actual_size = bit_array.byte_size(inner)
      case actual_sha == artifact.sha256 && actual_size == artifact.size {
        True -> Ok(Nil)
        False ->
          Error(
            "hash/size mismatch (expected "
            <> artifact.sha256
            <> "/"
            <> int_string(artifact.size)
            <> ", got "
            <> actual_sha
            <> "/"
            <> int_string(actual_size)
            <> ")",
          )
      }
    }
    _ -> Error("invalid archive contents")
  }
}

// ---------------------------------------------------------------------------
// prefetch

fn command_prefetch(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, ["manifest", "to-dir"]))
  let root = project_root()
  let manifest_path =
    option_default(value(options, "manifest"), project.manifest_path(root))
  let manifest_value = unwrap(project.read_manifest_file(manifest_path))
  let selected = case switch(options, "all") {
    True -> manifest_value.artifacts
    False -> {
      let target =
        option_default_result(host_target(), "x86_64-unknown-linux-gnu")
      let runtime = ffi.nif_version()
      case manifest.select_artifact(manifest_value, target, runtime) {
        Ok(artifact) -> [artifact]
        Error(_) -> []
      }
    }
  }
  case selected {
    [] -> fail("no artifact matches the current platform")
    _ ->
      list.each(selected, fn(artifact) {
        case
          prefetch_artifact(manifest_value, artifact, value(options, "to-dir"))
        {
          Error(error) -> fail(error)
          Ok(path) -> println("cached " <> path)
        }
      })
  }
}

fn prefetch_artifact(
  manifest_value: manifest.Manifest,
  artifact: manifest.Artifact,
  to_dir: Option(String),
) -> Result(String, String) {
  let extension = platform.extension(artifact.target)
  case to_dir {
    Some(directory) -> {
      let directory = ffi.absname(directory)
      let _ =
        unwrap(
          ffi.ensure_dir(directory) |> result.map_error(fn(error) { error }),
        )
      let body =
        unwrap(
          fetch.download(manifest.artifact_url(manifest_value, artifact))
          |> result.map_error(fn(error) { errors.message(error) }),
        )
      let expected = manifest_value.crate <> "." <> extension
      let inner =
        unwrap(
          ffi.tar_extract_gz_member(body, expected)
          |> result.map_error(fn(error) { error }),
        )
      let actual = ffi.sha256_hex(inner)
      let actual_size = bit_array.byte_size(inner)
      case actual == artifact.sha256 && actual_size == artifact.size {
        False -> Error("downloaded artifact failed verification")
        True -> {
          let path =
            ffi.join_paths([
              directory,
              paths.artifact_filename(artifact.sha256, extension),
            ])
          let _ =
            unwrap(
              ffi.write_file(path, inner)
              |> result.map_error(fn(error) { error }),
            )
          Ok(path)
        }
      }
    }
    None -> {
      let body =
        unwrap(
          fetch.download(manifest.artifact_url(manifest_value, artifact))
          |> result.map_error(fn(error) { errors.message(error) }),
        )
      let expected = manifest_value.crate <> "." <> extension
      let inner =
        unwrap(
          ffi.tar_extract_gz_member(body, expected)
          |> result.map_error(fn(error) { error }),
        )
      case
        ffi.sha256_hex(inner) == artifact.sha256
        && bit_array.byte_size(inner) == artifact.size
      {
        False -> Error("downloaded artifact failed verification")
        True -> {
          let stored =
            unwrap(
              cache.store(inner, artifact.sha256, extension)
              |> result.map_error(fn(error) { error }),
            )
          Ok(cache.strip_extension(stored, extension))
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// doctor

fn command_doctor(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, []))
  let _ = options
  let root = project_root()
  println("niffler " <> version())
  println("  cwd:            " <> root)
  println("  OTP release:    " <> ffi.otp_release())
  println("  NIF version:    " <> ffi.nif_version())
  println("  architecture:   " <> ffi.system_architecture())
  println("  wordsize:       " <> int_string(ffi.wordsize()))
  println("  cache root:     " <> cache.root())
  println(
    "  offline:        "
    <> bool_string(fetch.flag("NIFFLER_OFFLINE"))
    <> "   build: "
    <> bool_string(fetch.flag("NIFFLER_BUILD")),
  )
  case host_target() {
    Some(target) -> println("  detected target:" <> " " <> target)
    None -> println("  detected target: unknown")
  }
  case ffi.find_executable("cargo") {
    Some(path) -> println("  cargo:          " <> path)
    None -> println("  cargo:          not found")
  }
  case ffi.env("NIFFLER_GLEAM") {
    Some(path) if path != "" -> println("  gleam:          " <> path)
    _ ->
      case ffi.find_executable("gleam") {
        Some(path) -> println("  gleam:          " <> path)
        None -> println("  gleam:          not found")
      }
  }
  case project.package_info(root) {
    Error(error) -> println("  package:        " <> error)
    Ok(package) -> {
      println("  package:        " <> package.name <> " " <> package.version)
      case project.read_config(root) {
        Error(error) -> println("  niffler.toml:   " <> error)
        Ok(root_config) -> {
          let source = project.source_directory(root, root_config)
          println("  nif module:     " <> root_config.module)
          println("  source crate:   " <> source)
          println(
            "  source present: "
            <> bool_string(
              ffi.file_exists(ffi.join_paths([source, "Cargo.toml"])),
            ),
          )
          println(
            "  loader present: "
            <> bool_string(
              ffi.file_exists(project.loader_path(root, root_config.module)),
            ),
          )
          let path = project.manifest_path(root)
          case project.read_manifest_file(path) {
            Error(error) -> println("  manifest:       invalid: " <> error)
            Ok(manifest_value) -> {
              println(
                "  manifest:       "
                <> int_string(list.length(manifest_value.artifacts))
                <> " artifacts, version "
                <> manifest_value.version,
              )
              case host_target() {
                Some(target) -> {
                  case
                    manifest.select_artifact(
                      manifest_value,
                      target,
                      ffi.nif_version(),
                    )
                  {
                    Ok(artifact) ->
                      println("  selected:       " <> artifact.file)
                    Error(_) ->
                      println("  selected:       none for this platform")
                  }
                }
                None -> Nil
              }
            }
          }
        }
      }
    }
  }
  Nil
}

fn bool_string(value: Bool) -> String {
  case value {
    True -> "yes"
    False -> "no"
  }
}

// ---------------------------------------------------------------------------
// cache

fn command_cache(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, ["package"]))
  let subcommand = case options.positional {
    [subcommand] -> subcommand
    _ -> "path"
  }
  case subcommand {
    "path" -> println(cache.root())
    "list" -> {
      let artifacts = ffi.join_paths([cache.root(), "artifacts"])
      case ffi.list_dir(artifacts) {
        Ok(names) ->
          names
          |> list.sort(string.compare)
          |> list.each(fn(name) { println(ffi.join_paths([artifacts, name])) })
        Error(_) -> println("cache is empty: " <> cache.root())
      }
    }
    "clean" -> {
      case switch(options, "all") {
        True -> {
          let _ = ffi.remove_tree(cache.root())
          println("removed " <> cache.root())
        }
        False ->
          case value(options, "package") {
            Some(package) -> {
              let _ = clear_package_cache(package)
              println("removed cached artifacts for " <> package)
            }
            None ->
              usage_error("`cache clean` requires --all or --package <name>")
          }
      }
    }
    other -> usage_error("unknown cache subcommand `" <> other <> "`")
  }
}

// ---------------------------------------------------------------------------
// smoke

fn command_smoke(arguments: List(String)) -> Nil {
  let options =
    unwrap(parse_options(arguments, ["manifest", "artifact", "module"]))
  let root = project_root()
  let root_config = case project.read_config(root) {
    Ok(root_config) -> Some(root_config)
    Error(_) -> None
  }
  let module = case value(options, "module") {
    Some(module) -> module
    None ->
      case root_config {
        Some(root_config) -> root_config.module
        None -> "niffler_smoke_target"
      }
  }
  let functions = case root_config {
    Some(root_config) -> root_config.functions
    None -> []
  }
  let artifact = case value(options, "artifact") {
    Some(path) -> path
    None -> {
      let dist = ffi.join_paths([root, "dist"])
      case ffi.list_dir(dist) {
        Ok(names) ->
          case
            names
            |> list.filter(fn(name) { string.ends_with(name, ".tar.gz") })
            |> list.first
          {
            Ok(name) -> ffi.join_paths([dist, name])
            Error(_) ->
              unwrap(Error(
                "no artifact found in " <> dist <> "; pass --artifact",
              ))
          }
        Error(_) -> unwrap(Error("no dist directory; pass --artifact"))
      }
    }
  }
  case run_smoke(root, artifact, module, functions) {
    Ok(_) -> println("smoke: loaded " <> module <> " successfully")
    Error(error) -> fail("smoke failed: " <> error)
  }
}

fn run_smoke(
  root: String,
  artifact_path: String,
  module: String,
  functions: List(nif_config.Function),
) -> Result(Nil, String) {
  let tarball =
    unwrap(
      ffi.read_file(artifact_path)
      |> result.map_error(fn(error) {
        "could not read " <> artifact_path <> ": " <> error
      }),
    )
  let entries =
    unwrap(ffi.tar_inspect_gz(tarball) |> result.map_error(fn(error) { error }))
  let member = case entries {
    [entry] -> entry.name
    _ -> ""
  }
  case member {
    "" -> Error("artifact must contain exactly one shared library")
    _ -> {
      let contents =
        unwrap(
          ffi.tar_extract_gz_member(tarball, member)
          |> result.map_error(fn(error) { error }),
        )
      let directory =
        ffi.join_paths([
          root,
          "dist",
          ".smoke-"
            <> int_string(ffi.timestamp())
            <> "-"
            <> int_string(ffi.unique_id()),
        ])
      let _ =
        unwrap(
          ffi.ensure_dir(directory) |> result.map_error(fn(error) { error }),
        )
      let library = ffi.join_paths([directory, member])
      let _ =
        unwrap(
          ffi.write_file(library, contents)
          |> result.map_error(fn(error) { error }),
        )
      let loader_path = ffi.join_paths([directory, module <> ".erl"])
      let stubs =
        functions
        |> list.map(fn(function) {
          function.name
          <> "("
          <> argument_list(function.arity)
          <> ") -> erlang:nif_error(nif_not_loaded).\n"
        })
        |> string.join("")
      let exports = case functions {
        [] -> "niffler_smoke/0"
        _ ->
          "niffler_smoke/0, "
          <> string.join(
            list.map(functions, fn(function) {
              function.name <> "/" <> int_string(function.arity)
            }),
            ", ",
          )
      }
      let loader_source =
        "-module("
        <> module
        <> ").\n"
        <> "-on_load(init/0).\n"
        <> "-export(["
        <> exports
        <> "]).\n"
        <> "init() -> erlang:load_nif(\""
        <> erase_extension(library)
        <> "\", []).\n"
        <> "niffler_smoke() -> ok.\n"
        <> stubs
      let _ = unwrap(project.write_text_file(loader_path, loader_source))
      let erlc = case ffi.find_executable("erlc") {
        Some(path) -> path
        None -> ""
      }
      case erlc {
        "" -> Error("erlc was not found on PATH")
        _ -> {
          let #(status, output) =
            ffi.run(erlc, ["-o", directory, loader_path], directory)
          case status == 0 {
            False -> Error("erlc failed:\n" <> project.output_string(output))
            True -> {
              let erl = case ffi.find_executable("erl") {
                Some(path) -> path
                None -> ""
              }
              case erl {
                "" -> Error("erl was not found on PATH")
                _ -> {
                  let expression = module <> ":niffler_smoke(), halt(0)."
                  let #(run_status, run_output) =
                    ffi.run(
                      erl,
                      ["-noshell", "-pa", directory, "-eval", expression],
                      directory,
                    )
                  case run_status == 0 {
                    True -> Ok(Nil)
                    False ->
                      Error(
                        "could not load the NIF with the "
                        <> module
                        <> " loader:\n"
                        <> project.output_string(run_output),
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

fn argument_list(arity: Int) -> String {
  argument_list_loop(arity, 0, [])
}

fn argument_list_loop(
  arity: Int,
  index: Int,
  accumulator: List(String),
) -> String {
  case index >= arity {
    True -> string.join(list.reverse(accumulator), ", ")
    False ->
      argument_list_loop(arity, index + 1, [
        "_A" <> int_string(index),
        ..accumulator
      ])
  }
}

fn erase_extension(path: String) -> String {
  case string.ends_with(path, ".dylib") {
    True -> string.slice(path, 0, string.length(path) - 6)
    False ->
      case string.ends_with(path, ".so") || string.ends_with(path, ".dll") {
        True -> string.slice(path, 0, string.length(path) - 3)
        False -> path
      }
  }
}

// ---------------------------------------------------------------------------
// hex

fn command_hex(arguments: List(String)) -> Nil {
  let options = unwrap(parse_options(arguments, ["manifest", "output"]))
  let subcommand = case options.positional {
    [subcommand] -> subcommand
    _ -> "check"
  }
  case subcommand {
    "check" -> hex_check(options, False)
    "emit" -> hex_check(options, True)
    other -> usage_error("unknown hex subcommand `" <> other <> "`")
  }
}

fn hex_check(options: Options, emit: Bool) -> Nil {
  let root = project_root()
  let package = unwrap(project.package_info(root))
  let root_config = unwrap(project.read_config(root))
  let manifest_path =
    option_default(value(options, "manifest"), project.manifest_path(root))
  let manifest_value = unwrap(project.read_manifest_file(manifest_path))
  let _ =
    unwrap(project.write_text_file(
      project.manifest_path(root),
      manifest.encode(manifest_value),
    ))
  let _ = unwrap(validate_package(root, package, root_config, manifest_value))
  case switch(options, "online") {
    True -> verify_remote(root_config, package, manifest_value)
    False -> Nil
  }
  let tarball_path = unwrap(export_hex_tarball(root, package))
  let _ =
    unwrap(validate_hex_tarball(
      root,
      package,
      root_config,
      manifest_value,
      tarball_path,
    ))
  case emit {
    False ->
      println(
        "hex: package is valid; run `niffler hex emit` to produce the publishable tarball",
      )
    True -> {
      let output =
        option_default(
          value(options, "output"),
          ffi.join_paths([
            root,
            "dist",
            "hex",
            package.name <> "-" <> package.version <> ".tar",
          ]),
        )
      let _ =
        unwrap(
          ffi.ensure_dir(ffi.dirname(output))
          |> result.map_error(fn(error) { error }),
        )
      let bytes =
        unwrap(
          ffi.read_file(tarball_path) |> result.map_error(fn(error) { error }),
        )
      let _ =
        unwrap(
          ffi.write_file(output, bytes) |> result.map_error(fn(error) { error }),
        )
      let sha = ffi.sha256_hex(bytes)
      let _ =
        unwrap(project.write_text_file(
          output <> ".sha256",
          sha <> "  " <> ffi.basename(output) <> "\n",
        ))
      println("emitted " <> output)
      println("  sha256: " <> sha)
      println("")
      println("Publish with:")
      println("  gleam publish --yes")
    }
  }
}

fn validate_package(
  root: String,
  package: project.PackageInfo,
  root_config: nif_config.Config,
  manifest_value: manifest.Manifest,
) -> Result(Nil, String) {
  let _ =
    unwrap(case package.target == "erlang" {
      True -> Ok(Nil)
      False -> Error("package target must be erlang for NIF packages")
    })
  let _ =
    unwrap(case package.description == "" {
      True ->
        Error("gleam.toml needs a non-empty description before publishing")
      False -> Ok(Nil)
    })
  let _ =
    unwrap(case package.licences == [] {
      True -> Error("gleam.toml needs at least one licence before publishing")
      False -> Ok(Nil)
    })
  let _ =
    unwrap(
      case
        ffi.file_exists(ffi.join_paths([root, "README.md"]))
        || ffi.file_exists(ffi.join_paths([root, "README"]))
      {
        True -> Ok(Nil)
        False -> Error("a README is required for `gleam publish`")
      },
    )
  let _ =
    unwrap(case manifest_value.package == package.name {
      True -> Ok(Nil)
      False -> Error("manifest package does not match gleam.toml")
    })
  let _ =
    unwrap(case manifest_value.version == package.version {
      True -> Ok(Nil)
      False ->
        Error(
          "manifest version does not match gleam.toml; run niffler manifest",
        )
    })
  let _ =
    unwrap(
      case
        manifest_value.nif_module == root_config.module
        && manifest_value.crate == root_config.crate
      {
        True -> Ok(Nil)
        False -> Error("manifest nif module/crate do not match niffler.toml")
      },
    )
  let _ =
    unwrap(case manifest_value.artifacts != [] {
      True -> Ok(Nil)
      False -> Error("manifest has no artifacts")
    })
  let missing =
    root_config.targets
    |> list.filter(fn(target) {
      !list.any(manifest_value.artifacts, fn(artifact) {
        artifact.target == target
      })
    })
  let _ =
    unwrap(case missing {
      [] -> Ok(Nil)
      _ ->
        Error(
          "manifest is missing artifacts for: " <> string.join(missing, ", "),
        )
    })
  let _ = unwrap(validate_loader(root, root_config))
  let _ = unwrap(validate_rust_source(root, root_config))
  let _ = unwrap(check_priv_binaries(root))
  Ok(Nil)
}

fn validate_loader(
  root: String,
  root_config: nif_config.Config,
) -> Result(Nil, String) {
  let path = project.loader_path(root, root_config.module)
  case project.read_text(path) {
    Error(_) -> Error("missing generated loader " <> path)
    Ok(contents) -> {
      case string.contains(contents, "niffler_precompiled:artifact_path") {
        False -> Error("loader does not call niffler_precompiled:artifact_path")
        True -> Ok(Nil)
      }
    }
  }
}

fn validate_rust_source(
  root: String,
  root_config: nif_config.Config,
) -> Result(Nil, String) {
  let source = project.source_directory(root, root_config)
  let cargo_toml = ffi.join_paths([source, "Cargo.toml"])
  let cargo_lock = ffi.join_paths([source, "Cargo.lock"])
  case ffi.file_exists(cargo_toml) {
    False -> Error("missing Rust crate: " <> cargo_toml)
    True ->
      case ffi.file_exists(cargo_lock) {
        False ->
          Error(
            "missing Cargo.lock in "
            <> source
            <> "; run `cargo generate-lockfile` (needed for source fallback)",
          )
        True -> Ok(Nil)
      }
  }
}

fn check_priv_binaries(root: String) -> Result(Nil, String) {
  scan_for_binaries(ffi.join_paths([root, "priv"]), "")
}

fn scan_for_binaries(
  directory: String,
  relative: String,
) -> Result(Nil, String) {
  case ffi.list_dir(directory) {
    Error(_) -> Ok(Nil)
    Ok(names) ->
      list.try_each(names, fn(name) {
        let path = ffi.join_paths([directory, name])
        let relative_path = case relative {
          "" -> name
          _ -> relative <> "/" <> name
        }
        case ffi.file_size(path) {
          Ok(_) -> {
            case
              string.ends_with(name, ".so")
              || string.ends_with(name, ".dll")
              || string.ends_with(name, ".dylib")
            {
              True ->
                Error(
                  "priv/ must not contain compiled native libraries for Hex publishing: "
                  <> relative_path,
                )
              False -> Ok(Nil)
            }
          }
          Error(_) ->
            case name == "target" {
              True ->
                Error(
                  "priv/ must not contain a cargo target directory: "
                  <> relative_path,
                )
              False -> scan_for_binaries(path, relative_path)
            }
        }
      })
  }
}

fn validate_hex_tarball(
  root: String,
  package: project.PackageInfo,
  root_config: nif_config.Config,
  manifest_value: manifest.Manifest,
  tarball_path: String,
) -> Result(Nil, String) {
  let bytes =
    unwrap(ffi.read_file(tarball_path) |> result.map_error(fn(error) { error }))
  let _ =
    unwrap(case bit_array.byte_size(bytes) <= 16_777_216 {
      True -> Ok(Nil)
      False -> Error("Hex tarball exceeds the 16 MiB limit")
    })
  case bit_array.byte_size(bytes) > 8_388_608 {
    True ->
      println(
        "warning: Hex tarball is larger than 8 MiB; publishing may be rejected by older tooling",
      )
    False -> Nil
  }
  let entries =
    unwrap(
      ffi.tar_inspect_plain(bytes) |> result.map_error(fn(error) { error }),
    )
  let names = list.map(entries, fn(entry) { entry.name })
  let _ =
    unwrap(
      case
        list.contains(names, "VERSION")
        && list.contains(names, "metadata.config")
        && list.contains(names, "contents.tar.gz")
        && list.contains(names, "CHECKSUM")
      {
        True -> Ok(Nil)
        False ->
          Error("unexpected Hex tarball layout: " <> string.join(names, ", "))
      },
    )
  let version =
    unwrap(
      ffi.tar_extract_plain_member(bytes, "VERSION")
      |> result.map_error(fn(error) { error }),
    )
  let metadata =
    unwrap(
      ffi.tar_extract_plain_member(bytes, "metadata.config")
      |> result.map_error(fn(error) { error }),
    )
  let contents_tar =
    unwrap(
      ffi.tar_extract_plain_member(bytes, "contents.tar.gz")
      |> result.map_error(fn(error) { error }),
    )
  let checksum =
    unwrap(
      ffi.tar_extract_plain_member(bytes, "CHECKSUM")
      |> result.map_error(fn(error) { error }),
    )
  let metadata_text = project.output_string(metadata)
  let _ =
    unwrap(
      case
        string.contains(metadata_text, package.name)
        && string.contains(metadata_text, package.version)
        && string.contains(metadata_text, "gleam")
      {
        True -> Ok(Nil)
        False ->
          Error("Hex metadata is missing package name/version/build tool")
      },
    )
  let content_entries =
    unwrap(
      ffi.tar_inspect_gz(contents_tar) |> result.map_error(fn(error) { error }),
    )
  let content_names = list.map(content_entries, fn(entry) { entry.name })
  let _ =
    unwrap(case list.length(content_entries) <= 10_000 {
      True -> Ok(Nil)
      False -> Error("Hex tarball contains too many files")
    })
  let _ =
    unwrap(
      case list.find(content_names, fn(name) { string.length(name) > 255 }) {
        Ok(_) -> Error("Hex tarball contains a path longer than 255 bytes")
        Error(_) -> Ok(Nil)
      },
    )
  let uncompressed =
    list.fold(content_entries, 0, fn(total, entry) { total + entry.size })
  let _ =
    unwrap(case uncompressed <= 134_217_728 {
      True -> Ok(Nil)
      False ->
        Error("Hex tarball contents exceed the 128 MiB uncompressed limit")
    })
  let required = [
    "priv/niffler.json",
    "priv/native/" <> root_config.crate <> "/Cargo.toml",
    "priv/native/" <> root_config.crate <> "/Cargo.lock",
    "src/" <> root_config.module <> ".erl",
  ]
  let missing =
    required
    |> list.filter(fn(path) { !list.contains(content_names, path) })
  let _ =
    unwrap(case missing {
      [] -> Ok(Nil)
      _ -> Error("Hex tarball is missing: " <> string.join(missing, ", "))
    })
  let unexpected_binary =
    content_names
    |> list.filter(fn(name) {
      string.ends_with(name, ".so")
      || string.ends_with(name, ".dll")
      || string.ends_with(name, ".dylib")
    })
  let _ =
    unwrap(case unexpected_binary {
      [] -> Ok(Nil)
      _ ->
        Error(
          "Hex tarball contains native binaries: "
          <> string.join(unexpected_binary, ", "),
        )
    })
  // Recompute the Hex checksum: sha256(VERSION || metadata || contents.tar.gz).
  let recomputed =
    ffi.sha256_hex(bit_array.concat([version, metadata, contents_tar]))
    |> string.uppercase
  let stored = project.output_string(checksum) |> string.trim
  let _ =
    unwrap(case recomputed == stored {
      True -> Ok(Nil)
      False -> Error("Hex tarball checksum does not match its contents")
    })
  let _ = manifest_value
  let _ = root
  Ok(Nil)
}

fn export_hex_tarball(
  root: String,
  package: project.PackageInfo,
) -> Result(String, String) {
  let gleam =
    unwrap(case ffi.env("NIFFLER_GLEAM") {
      Some(path) if path != "" -> Ok(path)
      _ ->
        case ffi.find_executable("gleam") {
          Some(path) -> Ok(path)
          None -> Error("could not find the gleam executable")
        }
    })
  let #(status, output) = ffi.run(gleam, ["export", "hex-tarball"], root)
  case status {
    0 -> {
      let path =
        ffi.join_paths([
          root,
          "build",
          package.name <> "-" <> package.version <> ".tar",
        ])
      case ffi.file_exists(path) {
        True -> Ok(path)
        False -> Error("gleam export did not produce " <> path)
      }
    }
    _ ->
      Error(
        "gleam export hex-tarball failed:\n" <> project.output_string(output),
      )
  }
}

fn verify_remote(
  root_config: nif_config.Config,
  package: project.PackageInfo,
  manifest_value: manifest.Manifest,
) -> Nil {
  let _ = root_config
  let _ = package
  list.each(manifest_value.artifacts, fn(artifact) {
    case fetch.download(manifest.artifact_url(manifest_value, artifact)) {
      Error(error) ->
        fail("online verification failed: " <> errors.message(error))
      Ok(body) -> {
        let expected =
          manifest_value.crate <> "." <> platform.extension(artifact.target)
        case ffi.tar_extract_gz_member(body, expected) {
          Error(error) -> fail("online verification failed: " <> error)
          Ok(inner) -> {
            case ffi.sha256_hex(inner) == artifact.sha256 {
              True -> Nil
              False ->
                fail("online artifact hash mismatch for " <> artifact.file)
            }
          }
        }
      }
    }
  })
  println("online verification passed")
}

// ---------------------------------------------------------------------------
// small helpers

fn clear_package_cache(package: String) -> Nil {
  let _ = ffi.remove_tree(ffi.join_paths([cache.root(), "build", package]))
  let artifacts = ffi.join_paths([cache.root(), "artifacts"])
  case ffi.list_dir(artifacts) {
    Ok(names) ->
      list.each(names, fn(name) {
        let _ = ffi.remove_file(ffi.join_paths([artifacts, name]))
        Nil
      })
    Error(_) -> Nil
  }
}

fn project_root() -> String {
  case ffi.env("NIFFLER_ROOT") {
    Some(path) if path != "" -> ffi.absname(path)
    _ -> ffi.cwd()
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
