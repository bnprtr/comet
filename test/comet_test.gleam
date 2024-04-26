import comet.{attribute, attributes, debug, error, info, warning}
import gleeunit

pub fn main() {
  gleeunit.main()
}

type Attribute {
  Service(String)
  Latency(Float)
  StatusCode(Int)
  Success(Bool)
  Err(String)
}

// todo: tests were removed since log handlers are not yet implemented.
pub fn metadata_test() {
  comet.new()
  |> comet.with_level(comet.Debug)
  |> comet.configure()

  let log =
    comet.log()
    |> attribute(Service("comet"))

  log
  |> debug("did this work? hi mom")

  log
  |> attributes([Latency(24.2), StatusCode(200), Success(True)])
  |> info("access log")

  log
  |> attribute(Latency(102.2))
  |> attribute(StatusCode(400))
  |> attribute(Err("input not accepted"))
  |> attribute(Success(False))
  |> warning("access log")

  log
  |> attribute(Latency(402.0))
  |> attribute(StatusCode(500))
  |> attribute(Err("database connection error"))
  |> attribute(Success(False))
  |> error("access log")
}

fn levels(level: comet.Level) -> String {
  case level {
    comet.Debug -> "DEBG"
    comet.Info -> "INFO"
    comet.Warning -> "WARN"
    comet.Err -> "ERR"
    comet.Panic -> "PANIC"
  }
}

pub fn level_text_test() {
  comet.new()
  |> comet.with_level(comet.Debug)
  |> comet.with_level_text(levels)
  |> comet.configure

  let log = comet.log()

  log
  |> debug("should be DEBG")

  log
  |> info("should be INFO")

  log
  |> warning("should be WARN")

  log
  |> error("should be ERR")
}

@target(erlang)
fn formatter(_, _) {
  ["JUST THIS"]
}

@target(javascript)
fn formatter(_, _) {
  "JUST THIS"
}

pub fn formatter_test() {
  comet.new()
  |> comet.with_level(comet.Debug)
  |> comet.with_formatter(formatter)
  |> comet.configure()

  let log =
    comet.log()
    |> attribute(Service("comet"))

  log
  |> info("something")
}
