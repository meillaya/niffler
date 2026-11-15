import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import niffler_precompiled/config
import niffler_precompiled/loader_template

const valid_config =
  "
[nif]
module = \"demo_nif\"
crate = \"demo_nif\"
functions = [\"add/2\", \"version/0\"]

[release]
repo = \"owner/demo\"
"

pub fn valid_config_test() {
  let parsed = config.decode(valid_config) |> should.be_ok
  parsed.module |> should.equal("demo_nif")
  parsed.crate |> should.equal("demo_nif")
  parsed.path |> should.equal("priv/native/demo_nif")
  parsed.repo |> should.equal("owner/demo")
  parsed.functions
  |> should.equal([config.Function("add", 2), config.Function("version", 0)])
  parsed.targets |> should.equal(config.default_targets())
  parsed.nif_version |> should.equal(None)
}

pub fn explicit_values_test() {
  let parsed =
    config.decode(
      "[nif]\nmodule = \"demo_nif\"\ncrate = \"demo_nif\"\npath = \"priv/native/custom\"\nnif_version = \"2.17\"\n\n[release]\nrepo = \"owner/demo\"\ntargets = [\"x86_64-unknown-linux-gnu\"]\nbase_url = \"https://example.com/artifacts\"\n",
    )
    |> should.be_ok
  parsed.path |> should.equal("priv/native/custom")
  parsed.nif_version |> should.equal(Some("2.17"))
  parsed.targets |> should.equal(["x86_64-unknown-linux-gnu"])
  parsed.base_url |> should.equal(Some("https://example.com/artifacts"))
}

pub fn rejects_invalid_identifier_test() {
  config.decode(
    "[nif]\nmodule = \"Demo\"\ncrate = \"demo\"\n\n[release]\nrepo = \"a/b\"\n",
  )
  |> should.be_error
}

pub fn rejects_path_outside_priv_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\npath = \"native/demo\"\n\n[release]\nrepo = \"a/b\"\n",
  )
  |> should.be_error
}

pub fn rejects_bad_repo_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\n\n[release]\nrepo = \"not-a-repo\"\n",
  )
  |> should.be_error
}

pub fn rejects_unsupported_target_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\n\n[release]\nrepo = \"a/b\"\ntargets = [\"sparc-unknown-linux-gnu\"]\n",
  )
  |> should.be_error
}

pub fn rejects_duplicate_target_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\n\n[release]\nrepo = \"a/b\"\ntargets = [\"x86_64-unknown-linux-gnu\", \"x86_64-unknown-linux-gnu\"]\n",
  )
  |> should.be_error
}

pub fn rejects_unknown_key_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\nmystery = \"x\"\n\n[release]\nrepo = \"a/b\"\n",
  )
  |> should.be_error
}

pub fn rejects_invalid_function_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\nfunctions = [\"add\"]\n\n[release]\nrepo = \"a/b\"\n",
  )
  |> should.be_error
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\nfunctions = [\"init/0\"]\n\n[release]\nrepo = \"a/b\"\n",
  )
  |> should.be_error
}

pub fn rejects_insecure_base_url_test() {
  config.decode(
    "[nif]\nmodule = \"demo\"\ncrate = \"demo\"\n\n[release]\nrepo = \"a/b\"\nbase_url = \"http://example.com\"\n",
  )
  |> should.be_error
}

pub fn loader_template_test() {
  let rendered =
    loader_template.render("demo", "demo_nif", [
      config.Function("add", 2),
      config.Function("version", 0),
    ])
  rendered |> should_contain("-module(demo_nif).")
  rendered |> should_contain("-on_load(init/0).")
  rendered |> should_contain("-export([add/2, version/0]).")
  rendered |> should_contain("niffler_precompiled:artifact_path(<<\"demo\">>)")
  rendered |> should_contain("add(_Arg0, _Arg1) ->")
  rendered |> should_contain("erlang:nif_error(nif_not_loaded).")
}

fn should_contain(haystack: String, needle: String) {
  string.contains(haystack, needle) |> should.be_true()
}
