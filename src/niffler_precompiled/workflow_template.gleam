//// Generated GitHub Actions release workflow.

import gleam/list
import gleam/string
import niffler_precompiled/config
import niffler_precompiled/project

pub fn render(
  root_config: config.Config,
  _package: project.PackageInfo,
) -> String {
  let targets = root_config.targets
  let jobs = targets |> list.map(render_matrix_entry) |> string.join("")

  "name: niffler release\n"
  <> "\n"
  <> "on:\n"
  <> "  push:\n"
  <> "    tags:\n"
  <> "      - \"v*\"\n"
  <> "permissions:\n"
  <> "  contents: write\n"
  <> "  id-token: write\n"
  <> "  attestations: write\n"
  <> "\n"
  <> "concurrency:\n"
  <> "  group: niffler-${{ github.ref }}\n"
  <> "  cancel-in-progress: false\n"
  <> "\n"
  <> "jobs:\n"
  <> "  build:\n"
  <> "    name: ${{ matrix.target }} (${{ matrix.os }})\n"
  <> "    runs-on: ${{ matrix.os }}\n"
  <> "    strategy:\n"
  <> "      fail-fast: false\n"
  <> "      matrix:\n"
  <> "        include:\n"
  <> jobs
  <> "    steps:\n"
  <> "      - uses: actions/checkout@v4\n"
  <> "      - uses: erlef/setup-beam@v1\n"
  <> "        with:\n"
  <> "          otp-version: \"28\"\n"
  <> "          gleam-version: \"1.19.2\"\n"
  <> "      - uses: dtolnay/rust-toolchain@stable\n"
  <> "      - run: gleam deps download\n"
  <> "      - name: Install cross\n"
  <> "        if: matrix.cross\n"
  <> "        run: cargo install cross --version 0.2.5 --locked\n"
  <> "      - name: Build artifact (cross)\n"
  <> "        if: matrix.cross\n"
  <> "        run: |\n"
  <> "          gleam run -m niffler_precompiled -- build --target ${{ matrix.target }} --dist dist --use-cross\n"
  <> "      - name: Build artifact (native)\n"
  <> "        if: ${{ !matrix.cross }}\n"
  <> "        run: |\n"
  <> "          gleam run -m niffler_precompiled -- build --target ${{ matrix.target }} --dist dist\n"
  <> "      - name: Smoke-test artifact\n"
  <> "        if: ${{ !matrix.cross }}\n"
  <> "        shell: bash\n"
  <> "        run: |\n"
  <> "          ARTIFACT=$(find dist -maxdepth 1 -name \"*.tar.gz\" | head -n1)\n"
  <> "          gleam run -m niffler_precompiled -- smoke --artifact \"$ARTIFACT\" --module "
  <> root_config.module
  <> "\n"
  <> "      - uses: actions/attest-build-provenance@v2\n"
  <> "        with:\n"
  <> "          subject-path: dist/*.tar.gz\n"
  <> "      - uses: actions/upload-artifact@v4\n"
  <> "        with:\n"
  <> "          name: niffler-${{ matrix.target }}\n"
  <> "          path: dist/*.tar.gz\n"
  <> "\n"
  <> "  release:\n"
  <> "    needs: build\n"
  <> "    runs-on: ubuntu-24.04\n"
  <> "    steps:\n"
  <> "      - uses: actions/checkout@v4\n"
  <> "      - uses: erlef/setup-beam@v1\n"
  <> "        with:\n"
  <> "          otp-version: \"28\"\n"
  <> "          gleam-version: \"1.19.2\"\n"
  <> "      - uses: actions/download-artifact@v4\n"
  <> "        with:\n"
  <> "          path: dist\n"
  <> "          merge-multiple: true\n"
  <> "      - name: Manifest\n"
  <> "        run: |\n"
  <> "          gleam deps download\n"
  <> "          VERSION=\"${GITHUB_REF_NAME#v}\"\n"
  <> "          gleam run -m niffler_precompiled -- manifest --dist dist --version \"$VERSION\" --write\n"
  <> "          gleam run -m niffler_precompiled -- manifest --dist dist --version \"$VERSION\" --check\n"
  <> "      - name: Release\n"
  <> "        env:\n"
  <> "          GH_TOKEN: ${{ github.token }}\n"
  <> "        run: |\n"
  <> "          gh release create \"${GITHUB_REF_NAME}\" dist/*.tar.gz priv/niffler.json --generate-notes --draft\n"
  <> "          gh release edit \"${GITHUB_REF_NAME}\" --draft=false\n"
  <> "\n"
  <> "  hex:\n"
  <> "    needs: release\n"
  <> "    runs-on: ubuntu-24.04\n"
  <> "    environment: hexpm\n"
  <> "    if: vars.NIFFLER_PUBLISH_HEX == 'true'\n"
  <> "    steps:\n"
  <> "      - uses: actions/checkout@v4\n"
  <> "      - uses: erlef/setup-beam@v1\n"
  <> "        with:\n"
  <> "          otp-version: \"28\"\n"
  <> "          gleam-version: \"1.19.2\"\n"
  <> "      - name: Fetch manifest asset\n"
  <> "        env:\n"
  <> "          GH_TOKEN: ${{ github.token }}\n"
  <> "        run: |\n"
  <> "          gh release download \"${GITHUB_REF_NAME}\" --pattern niffler.json --dir dist/release\n"
  <> "          cp dist/release/niffler.json priv/niffler.json\n"
  <> "      - run: gleam deps download\n"
  <> "      - name: Validate Hex package\n"
  <> "        run: gleam run -m niffler_precompiled -- hex check --online\n"
  <> "      - name: Emit Hex tarball\n"
  <> "        run: gleam run -m niffler_precompiled -- hex emit\n"
  <> "      - name: Publish\n"
  <> "        env:\n"
  <> "          HEXPM_API_KEY: ${{ secrets.HEXPM_API_KEY }}\n"
  <> "        run: gleam publish --yes\n"
}

fn render_matrix_entry(target: String) -> String {
  let os = runner_for(target)
  let cross = case string.contains(target, "musl") {
    True -> "true"
    False -> "false"
  }
  "          - target: "
  <> target
  <> "\n"
  <> "            os: "
  <> os
  <> "\n"
  <> "            cross: "
  <> cross
  <> "\n"
}

fn runner_for(target: String) -> String {
  case target {
    "x86_64-unknown-linux-gnu" -> "ubuntu-22.04"
    "aarch64-unknown-linux-gnu" -> "ubuntu-22.04-arm"
    "x86_64-unknown-linux-musl" -> "ubuntu-22.04"
    "aarch64-unknown-linux-musl" -> "ubuntu-22.04-arm"
    "x86_64-apple-darwin" -> "macos-15-intel"
    "aarch64-apple-darwin" -> "macos-15"
    "x86_64-pc-windows-msvc" -> "windows-2025"
    _ -> "ubuntu-22.04"
  }
}
