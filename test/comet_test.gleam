import comet.{attribute, attributes, debug, error, info, warning}
import comet/level.{type Level, Debug, Error, Info, Warning}
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/javascript/array
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam_community/ansi
import gleeunit
import gleeunit/should

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

fn attribute_serializer(a: Attribute) -> #(String, json.Json) {
  case a {
    Service(value) -> #("service", json.string(value))
    Latency(value) -> #("latency", json.float(value))
    StatusCode(value) -> #("statusCode", json.int(value))
    Success(value) -> #("success", json.bool(value))
    AnError(value) -> #("error", json.string(value))
  }
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
    "level=debug attributes=[Service(\"comet\")] msg=did this work? hi mom",
    "level=info attributes=[Service(\"comet\"), Latency(24.2), StatusCode(200), Success(True)] msg=access log",
    "level=warn attributes=[Success(False), AnError(\"input not accepted\"), StatusCode(400), Latency(102.2), Service(\"comet\")] msg=access log",
    "level=error attributes=[Success(False), AnError(\"database connection error\"), StatusCode(500), Latency(402.1), Service(\"comet\")] msg=access log",
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
    "level=debug attributes=[Service(\"comet\")] msg=did this work? hi mom",
    "level=info attributes=[Service(\"comet\"), Latency(24.2), StatusCode(200), Success(True)] msg=access log",
    "level=warn attributes=[Success(False), AnError(\"input not accepted\"), StatusCode(400), Latency(102.2), Service(\"comet\")] msg=access log",
    "level=error attributes=[Success(False), AnError(\"database connection error\"), StatusCode(500), Latency(402.1), Service(\"comet\")] msg=access log",
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
    Error -> "ERR"
  }
}

pub fn level_text_test() {
  let logs =
    comet.new()
    |> comet.with_level(Debug)
    |> comet.timestamp(False)
    |> comet.with_formatter(comet.text_formatter)
    |> comet.with_level_text(levels)
    |> comet.configure
    |> test_handler("level_text_test")

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
    "level=DEBG attributes=[] msg=should be DEBG",
    "level=INFO attributes=[] msg=should be INFO",
    "level=WARN attributes=[] msg=should be WARN",
    "level=ERR attributes=[] msg=should be ERR",
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

pub fn json_test() {
  let logs =
    comet.new()
    |> comet.with_formatter(comet.json_formatter(attribute_serializer))
    |> comet.timestamp(False)
    |> comet.configure
    |> test_handler("json_test")

  comet.log()
  |> attributes([Service("comet"), Success(True)])
  |> info("a thing")

  comet.log()
  |> attribute(AnError("access denied"))
  |> error("a bad thing")

  should.equal(get_logs(logs), [
    "{\"msg\":\"a thing\",\"level\":\"info\",\"service\":\"comet\",\"success\":true}",
    "{\"msg\":\"a bad thing\",\"level\":\"error\",\"error\":\"access denied\"}",
  ])
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
  ctx
  |> comet.with_level_text(level.level_text_ansi)
  |> comet.with_formatter(comet.text_formatter)
  |> comet.configure
  |> comet.timestamp(False)
  |> test_handler(name)
}

@target(javascript)
fn test_configure(ctx: comet.Context(Attribute), name: String) -> String {
  ctx
  |> comet.with_level_text(level.level_text_ansi)
  |> comet.with_formatter(comet.text_formatter)
  |> comet.configure
  |> comet.timestamp(False)
  |> test_handler_wrapper(name)
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

@external(javascript, "./logs.mjs", "removeHandler")
fn remove_handler(name: String) -> Nil

@target(erlang)
fn close(logs) {
  process.send(logs, Close)
}

@target(erlang)
fn test_handler(ctx: comet.Context(Attribute), name: String) -> Subject(Message) {
  let handler = log_handler()
  comet.set_handler(ctx, name, fn(data: String) {
    process.send(handler, Log(ansi.strip(data)))
    Nil
  })
  handler
}

@target(javascript)
fn test_handler(ctx: comet.Context(Attribute), name: String) -> String {
  test_handler_wrapper(ctx, name)
  name
}

@target(javascript)
fn test_handler_wrapper(
  ctx: comet.Context(Attribute),
  name: String,
) -> comet.Handler {
  let js_handler = test_handler_js(name)
  let handler = fn(str: String) -> Nil { js_handler(ansi.strip(str)) }
  ctx
  |> comet.add_handler(name, handler)
  handler
}

@target(javascript)
@external(javascript, "./logs.mjs", "testHandler")
fn test_handler_js(msg: String) -> comet.Handler

@target(javascript)
fn get_logs(name: String) -> List(String) {
  array.to_list(get_logs_js(name))
}

@target(javascript)
@external(javascript, "./logs.mjs", "getTestLogs")
fn get_logs_js(name: String) -> array.Array(String)
