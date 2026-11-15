import gleeunit
import gleeunit/should
import niffler_precompiled

pub fn main() {
  gleeunit.main()
}

pub fn version_is_set_test() {
  niffler_precompiled.version
  |> should.equal("0.1.0")
}
