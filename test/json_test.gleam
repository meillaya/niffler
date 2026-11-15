import gleeunit/should
import niffler_precompiled/json

pub fn parse_object_test() {
  let result =
    json.parse(
      "{\"name\": \"demo\", \"count\": 2, \"ok\": true, \"nothing\": null, \"list\": [1, 2.5, \"x\"]}",
    )
    |> should.be_ok

  json.field_string(result, "name") |> should.equal(Ok("demo"))
  json.field_int(result, "count") |> should.equal(Ok(2))
  json.object_get(result, "ok") |> should.equal(Ok(json.JBool(True)))
  json.object_get(result, "nothing") |> should.equal(Ok(json.JNull))

  let list = json.field_array(result, "list") |> should.be_ok
  list
  |> should.equal([json.JInt(1), json.JFloat(2.5), json.JString("x")])
}

pub fn parse_unicode_test() {
  let value = json.parse("\"caf\\u00e9 \\ud83d\\ude00\"") |> should.be_ok
  value |> should.equal(json.JString("café 😀"))
}

pub fn parse_rejects_trailing_data_test() {
  json.parse("{} trailing") |> should.be_error
  json.parse("[1,]") |> should.be_error
}

pub fn parse_rejects_duplicate_keys_test() {
  json.parse("{\"a\": 1, \"a\": 2}") |> should.be_error
}

pub fn parse_rejects_invalid_escape_test() {
  json.parse("\"\\q\"") |> should.be_error
  json.parse("\"unterminated") |> should.be_error
}

pub fn parse_rejects_empty_test() {
  json.parse("") |> should.be_error
}

pub fn encode_is_deterministic_test() {
  let value =
    json.JObject([
      #("b", json.JString("second")),
      #("a", json.JString("first")),
    ])
  json.encode(value)
  |> should.equal("{\n  \"a\": \"first\",\n  \"b\": \"second\"\n}")
}

pub fn encode_escapes_strings_test() {
  json.encode(json.JString("a\"b\\c\nd\t"))
  |> should.equal("\"a\\\"b\\\\c\\nd\\t\"")
}

pub fn round_trip_test() {
  let input = "{\"a\": [1, 2, 3], \"b\": {\"c\": false}}"
  let parsed = json.parse(input) |> should.be_ok
  let encoded = json.encode(parsed)
  json.parse(encoded) |> should.equal(Ok(parsed))
}

pub fn accessors_reject_wrong_types_test() {
  json.as_string(json.JInt(1)) |> should.be_error
  json.as_array(json.JObject([])) |> should.be_error
  json.field_string(json.JObject([]), "missing") |> should.be_error
}
