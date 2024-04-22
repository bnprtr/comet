import birl
import comet.{
  BoolAttr, DEBUG, ERROR, FloatAttr, INFO, IntAttr, StrAttr, TRACE, TimeAttr,
  WARN,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn log_test() {
  comet.init()
  |> comet.with_attributes([TimeAttr("timestamp", birl.utc_now())])
  |> comet.log(INFO, "fooooooo", [
    BoolAttr("is_true", True),
    StrAttr("key", "value"),
    IntAttr("age", 27),
    FloatAttr("chances", 33.3333),
  ])
}
