import gleeunit/should
import niffler_precompiled/toml

pub fn parse_niffler_config_test() {
  let document =
    toml.parse(
      "
# a comment
[nif]
module = \"demo_nif\"   # trailing comment
crate = \"demo_nif\"

[release]
repo = \"owner/demo\"
targets = [
  \"x86_64-unknown-linux-gnu\",
  \"aarch64-apple-darwin\",
]
",
    )
    |> should.be_ok

  toml.table_names(document) |> should.equal(["nif", "release"])

  let nif = toml.table(document, "nif") |> should.be_ok
  toml.get_string(nif, "module") |> should.equal(Ok("demo_nif"))

  let release = toml.table(document, "release") |> should.be_ok
  toml.get_string(release, "repo") |> should.equal(Ok("owner/demo"))
  toml.get_string_array(release, "targets")
  |> should.equal(Ok(["x86_64-unknown-linux-gnu", "aarch64-apple-darwin"]))
}

pub fn literal_strings_and_escapes_test() {
  let document =
    toml.parse(
      "[nif]
module = \"a\\tb\"
crate = 'c:\\path'
",
    )
    |> should.be_ok
  let entries = toml.table(document, "nif") |> should.be_ok
  toml.get_string(entries, "module") |> should.equal(Ok("a\tb"))
  toml.get_string(entries, "crate") |> should.equal(Ok("c:\\path"))
}

pub fn duplicate_key_test() {
  toml.parse("[nif]\nmodule = \"a\"\nmodule = \"b\"\n") |> should.be_error
}

pub fn duplicate_table_test() {
  toml.parse("[nif]\nmodule = \"a\"\n[nif]\ncrate = \"b\"\n") |> should.be_error
}

pub fn nested_table_rejected_test() {
  toml.parse("[release.extra]\nrepo = \"a/b\"\n") |> should.be_error
}

pub fn key_before_table_rejected_test() {
  toml.parse("module = \"a\"\n") |> should.be_error
}

pub fn unterminated_array_test() {
  toml.parse("[release]\ntargets = [\"a\",\n") |> should.be_error
}

pub fn scalar_values_test() {
  let document =
    toml.parse("[nif]\ncount = 42\non = true\noff = false\n") |> should.be_ok
  let entries = toml.table(document, "nif") |> should.be_ok
  toml.get_int(entries, "count") |> should.equal(Ok(42))
  toml.get_bool(entries, "on") |> should.equal(Ok(True))
  toml.get_bool(entries, "off") |> should.equal(Ok(False))
}

pub fn missing_table_test() {
  toml.parse("[nif]\nmodule = \"a\"\n")
  |> should.be_ok
  |> toml.table("release")
  |> should.be_error
}
