import comet.{attribute, attributes, debug, error, info, warning}
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/javascript/array
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
  |> attribute(Latency(402.1))
  |> attribute(StatusCode(500))
  |> attribute(AnError("database connection error"))
  |> attribute(Success(False))
  |> error("access log")

  should.equal(get_logs(logs), [
    "level: debug | [Service(\"comet\")] | did this work? hi mom",
    "level: info | [Service(\"comet\"), Latency(24.2), StatusCode(200), Success(True)] | access log",
    "level: warn | [Success(False), AnError(\"input not accepted\"), StatusCode(400), Latency(102.2), Service(\"comet\")] | access log",
    "level: error | [Success(False), AnError(\"database connection error\"), StatusCode(500), Latency(402.1), Service(\"comet\")] | access log",
  ])
  close(logs)
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
  |> attribute(Latency(402.1))
  |> attribute(StatusCode(500))
  |> attribute(AnError("database connection error"))
  |> attribute(Success(False))
  |> error("access log")

  should.equal(get_logs(logs), [
    "level: debug | [Service(\"comet\")] | did this work? hi mom",
    "level: info | [Service(\"comet\"), Latency(24.2), StatusCode(200), Success(True)] | access log",
    "level: warn | [Success(False), AnError(\"input not accepted\"), StatusCode(400), Latency(102.2), Service(\"comet\")] | access log",
    "level: error | [Success(False), AnError(\"database connection error\"), StatusCode(500), Latency(402.1), Service(\"comet\")] | access log",
  ])

  should.equal(get_logs(logs2), [
    "-- access log", "-- access log", "-- access log",
  ])
  close(logs)
  close(logs2)
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

  should.equal(get_logs(logs), [
    "level: DEBG | [] | should be DEBG", "level: INFO | [] | should be INFO",
    "level: WARN | [] | should be WARN", "level: Error | [] | should be ERR",
  ])
  close(logs)
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

  should.equal(get_logs(logs), ["-- something", "-- something else"])
  close(logs)
}

@target(erlang)
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

@target(erlang)
fn test_configure(
  ctx: comet.Context(Attribute),
  name: String,
) -> Subject(Message) {
  comet.configure(ctx)
  |> comet.with_formatter(comet.text_formatter)
  |> test_handler(name)
}

@target(javascript)
fn test_configure(ctx: comet.Context(Attribute), name: String) -> String {
  ctx
  |> comet.with_formatter(comet.text_formatter)
  |> comet.configure
  |> comet.add_handler(name, test_handler_js(name))
  name
}

@target(erlang)
fn get_logs(logs: Subject(Message)) -> List(String) {
  process.call(logs, Get, 200)
}

@target(javascript)
fn close(name) {
  remove_handler(name)
}

@external(javascript, "./logs.mjs", "remove_handler")
fn remove_handler(name: String) -> Nil

@target(erlang)
fn close(logs) {
  process.send(logs, Close)
}

@target(erlang)
fn test_handler(ctx: comet.Context(Attribute), name: String) -> Subject(Message) {
  let handler = log_handler()
  comet.add_handler(ctx, name, fn(data: String) {
    process.send(handler, Log(data))
    Nil
  })
  handler
}

@target(javascript)
fn test_handler(ctx: comet.Context(Attribute), name: String) -> String {
  ctx
  |> comet.add_handler(name, test_handler_js(name))
  name
}

@target(javascript)
@external(javascript, "./logs.mjs", "test_handler")
fn test_handler_js(msg: String) -> comet.Handler

@target(javascript)
fn get_logs(name: String) -> List(String) {
  array.to_list(get_logs_js(name))
}

@target(javascript)
@external(javascript, "./logs.mjs", "get_test_logs")
fn get_logs_js(name: String) -> array.Array(String)
