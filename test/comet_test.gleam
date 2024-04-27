import comet.{attribute, attributes, debug, error, info, warning}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleeunit
import gleeunit/should
import level.{type Level, Debug, Error, Info, Panic, Warning}

pub fn main() {
  gleeunit.main()
}

type Attribute {
  Service(String)
  Latency(Float)
  StatusCode(Int)
  Success(Bool)
  AnError(String)
}

// todo: tests were removed since log handlers are not yet implemented.
pub fn metadata_test() {
  let logs =
    comet.new()
    |> comet.with_level(Debug)
    |> test_configure("metadata_test")

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
  |> attribute(AnError("input not accepted"))
  |> attribute(Success(False))
  |> warning("access log")

  log
  |> attribute(Latency(402.0))
  |> attribute(StatusCode(500))
  |> attribute(AnError("database connection error"))
  |> attribute(Success(False))
  |> error("access log")

  should.equal(process.call(logs, Get, 200), [
    "level: debug | [Service(\"comet\")] | did this work? hi mom",
    "level: info | [Service(\"comet\"), Latency(24.2), StatusCode(200), Success(True)] | access log",
    "level: warn | [Success(False), AnError(\"input not accepted\"), StatusCode(400), Latency(102.2), Service(\"comet\")] | access log",
    "level: error | [Success(False), AnError(\"database connection error\"), StatusCode(500), Latency(402.0), Service(\"comet\")] | access log",
  ])
  process.send(logs, Close)
}

pub fn multi_handler_test() {
  let logs =
    comet.new()
    |> comet.with_level(Debug)
    |> test_configure("multi_handler_test")

  let logs2 =
    comet.new()
    |> comet.with_level(Info)
    |> comet.with_formatter(formatter)
    |> test_handler("multi_handler_test_2")
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
  |> attribute(AnError("input not accepted"))
  |> attribute(Success(False))
  |> warning("access log")

  log
  |> attribute(Latency(402.0))
  |> attribute(StatusCode(500))
  |> attribute(AnError("database connection error"))
  |> attribute(Success(False))
  |> error("access log")

  should.equal(process.call(logs, Get, 200), [
    "level: debug | [Service(\"comet\")] | did this work? hi mom",
    "level: info | [Service(\"comet\"), Latency(24.2), StatusCode(200), Success(True)] | access log",
    "level: warn | [Success(False), AnError(\"input not accepted\"), StatusCode(400), Latency(102.2), Service(\"comet\")] | access log",
    "level: error | [Success(False), AnError(\"database connection error\"), StatusCode(500), Latency(402.0), Service(\"comet\")] | access log",
  ])

  should.equal(process.call(logs2, Get, 200), [
    "-- access log", "-- access log", "-- access log",
  ])
  process.send(logs, Close)
  process.send(logs2, Close)
}

fn levels(level: Level) -> String {
  case level {
    Debug -> "DEBG"
    Info -> "INFO"
    Warning -> "WARN"
    Error -> "Error"
    Panic -> "PANIC"
  }
}

pub fn level_text_test() {
  let logs =
    comet.new()
    |> comet.with_level(Debug)
    |> comet.with_level_text(levels)
    |> test_configure("level_text_test")

  let log = comet.log()

  log
  |> debug("should be DEBG")

  log
  |> info("should be INFO")

  log
  |> warning("should be WARN")

  log
  |> error("should be ERR")

  should.equal(process.call(logs, Get, 200), [
    "level: DEBG | [] | should be DEBG", "level: INFO | [] | should be INFO",
    "level: WARN | [] | should be WARN", "level: Error | [] | should be ERR",
  ])
  process.send(logs, Close)
}

fn formatter(_, entry: comet.Entry(Attribute)) {
  "-- " <> entry.message
}

type Message {
  Log(String)
  Get(Subject(List(String)))
  Close
}

pub fn formatter_test() {
  let ctx =
    comet.new()
    |> comet.with_level(Debug)
    |> comet.with_formatter(formatter)
    |> comet.configure()

  let logs =
    ctx
    |> comet.with_formatter(formatter)
    |> test_handler("formatter_test")

  let log =
    comet.log()
    |> attribute(Service("comet"))

  log
  |> info("something")

  log
  |> error("something else")

  should.equal(process.call(logs, Get, 200), [
    "-- something", "-- something else",
  ])
  process.send(logs, Close)
}

fn log_handler() -> Subject(Message) {
  let assert Ok(pid) =
    actor.start([], fn(msg: Message, logs: List(String)) -> actor.Next(
      Message,
      List(String),
    ) {
      case msg {
        Log(data) -> actor.continue(list.append(logs, [data]))
        Get(ret) -> {
          process.send(ret, logs)
          actor.continue(logs)
        }
        Close -> actor.Stop(process.Normal)
      }
    })
  pid
}

fn test_configure(
  ctx: comet.Context(Attribute),
  name: String,
) -> Subject(Message) {
  comet.configure(ctx)
  |> comet.with_formatter(comet.text_formatter)
  |> test_handler(name)
}

fn test_handler(ctx: comet.Context(Attribute), name: String) -> Subject(Message) {
  let handler = log_handler()
  comet.add_handler(ctx, name, fn(data: String) {
    process.send(handler, Log(data))
    Nil
  })
  handler
}
