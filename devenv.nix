{ pkgs, config, ... }:
{
  languages.gleam.enable = true;
  languages.gleam.package = pkgs.gleam;

  languages.erlang.enable = true;
  languages.erlang.package = pkgs.beamPackages.erlang;
  languages.erlang.lsp.enable = false;

  # Rust toolchain for the source-fallback integration fixtures, python3 for
  # the HTTP server the integration suite uses to serve fixture artifacts.
  # `stdenv.cc` provides the C linker cargo needs to build cdylib NIFs.
  packages = with pkgs; [
    jq
    curl
    git
    python3
    cargo
    rustc
    stdenv.cc
  ];

  # Keep the Gleam/Hex/cargo cache inside the project so the environment is
  # reproducible and works on machines with a read-only home cache.
  env.XDG_CACHE_HOME = "${config.devenv.root}/.cache";

  scripts.test.exec = "gleam test";
  scripts.check.exec = "gleam format --check src test && gleam build --warnings-as-errors";
  scripts.integration.exec = "bash integration/run.sh";

  enterShell = ''
    gleam --version
    erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'
    cargo --version
    rustc --version
    python3 --version
  '';

  enterTest = ''
    gleam format --check src test
    gleam build --warnings-as-errors
    gleam test
  '';
}
