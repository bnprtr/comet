import comet.{attribute, debug, error, info, warning}
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
  |> comet.level(comet.Debug)
  |> comet.configure()

  let log =
    comet.log()
    |> attribute(Service("comet"))

  log
  |> debug("did this work? hi mom")

  log
  |> attribute(Latency(24.2))
  |> attribute(StatusCode(200))
  |> attribute(Success(True))
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
