{
  lib,
  stdenv,
  fetchFromGitHub,
  gleam,
  beamPackages,
  makeWrapper,
  git,
  cargo,
  rustc,
  curl,
  src,
  version,
}:

let
  inherit (beamPackages) erlang;

  # The only runtime dependency of the CLI. Vendoring it as a path
  # dependency keeps the Nix build offline and avoids a Hex cache.
  gleamStdlib = fetchFromGitHub {
    owner = "gleam-lang";
    repo = "stdlib";
    rev = "v1.0.5";
    hash = "sha256-onOUf1lYTj+rQxPMSM8V8PXdJEyuBiEJsqc2Z/m+kw0=";
  };
in
stdenv.mkDerivation {
  pname = "niffler";
  inherit version src;

  nativeBuildInputs = [
    gleam
    erlang
    makeWrapper
  ];

  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p work
    cp -r ${src}/src work/src
    cd work

    cat > gleam.toml <<EOF
    name = "niffler_precompiled"
    version = "${version}"
    target = "erlang"

    [dependencies]
    gleam_stdlib = { path = "${gleamStdlib}" }
    EOF

    export HOME="$TMPDIR"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$XDG_CACHE_HOME"

    gleam build --target erlang
    escript ${./build_escript.escript} niffler.escript \
      build/dev/erlang/niffler_precompiled/ebin \
      build/dev/erlang/gleam_stdlib/ebin

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/niffler"
    cp niffler.escript "$out/share/niffler/niffler.escript"

    # The CLI shells out to gleam/cargo for some commands (source fallback
    # builds, package-manager checks), so keep those tools on PATH. `git` and
    # `curl` are used by the authoring/prefetch flows.
    makeWrapper ${erlang}/bin/escript "$out/bin/niffler" \
      --add-flags "$out/share/niffler/niffler.escript" \
      --prefix PATH : ${
        lib.makeBinPath [
          gleam
          erlang
          git
          cargo
          rustc
          curl
        ]
      }

    runHook postInstall
  '';

  meta = with lib; {
    description = "Precompiled Rust NIF distribution for Gleam packages: per-platform artifacts, verified manifests, caching, source fallback, and Hex packaging";
    license = licenses.asl20;
    mainProgram = "niffler";
    platforms = platforms.unix;
  };
}
